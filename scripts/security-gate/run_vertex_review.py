#!/usr/bin/env python3
"""Review an incremental Git diff with Vertex AI and fail closed."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

BLOCKING_SEVERITIES = {"CRITICAL", "HIGH"}
ALL_SEVERITIES = BLOCKING_SEVERITIES | {"MEDIUM", "LOW"}
DEFAULT_MAX_DIFF_BYTES = 500_000

RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "required": ["pass", "findings"],
    "properties": {
        "pass": {"type": "BOOLEAN"},
        "findings": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "required": ["severity", "category", "file", "line", "summary"],
                "properties": {
                    "severity": {
                        "type": "STRING",
                        "enum": ["CRITICAL", "HIGH", "MEDIUM", "LOW"],
                    },
                    "category": {"type": "STRING"},
                    "file": {"type": "STRING"},
                    "line": {"type": "INTEGER"},
                    "summary": {"type": "STRING"},
                },
            },
        },
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=os.getenv("GOOGLE_CLOUD_PROJECT"))
    parser.add_argument("--location", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--pr-number", default="")
    parser.add_argument("--diff-file", type=Path, required=True)
    parser.add_argument("--changed-files-file", type=Path, required=True)
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument(
        "--output", type=Path, default=Path("/workspace/.vertex-review.json")
    )
    parser.add_argument(
        "--max-diff-bytes",
        type=int,
        default=int(os.getenv("MAX_DIFF_BYTES", DEFAULT_MAX_DIFF_BYTES)),
    )
    return parser.parse_args()


def validate_result(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"pass", "findings"}:
        raise ValueError("response must contain only pass and findings")
    if not isinstance(value["pass"], bool) or not isinstance(value["findings"], list):
        raise ValueError("pass must be boolean and findings must be an array")

    required = {"severity", "category", "file", "line", "summary"}
    for index, finding in enumerate(value["findings"]):
        if not isinstance(finding, dict) or set(finding) != required:
            raise ValueError(f"finding {index} has an invalid shape")
        if finding["severity"] not in ALL_SEVERITIES:
            raise ValueError(f"finding {index} has an invalid severity")
        if not isinstance(finding["line"], int):
            raise ValueError(f"finding {index} line must be an integer")
        for key in ("category", "file", "summary"):
            if not isinstance(finding[key], str):
                raise ValueError(f"finding {index} {key} must be a string")

    blocked = any(
        item["severity"] in BLOCKING_SEVERITIES for item in value["findings"]
    )
    if value["pass"] == blocked:
        raise ValueError("pass conflicts with finding severities")
    return value


def call_vertex(
    project: str, location: str, model: str, system_prompt: str, request: dict[str, Any]
) -> dict[str, Any]:
    import google.auth
    from google.auth.transport.requests import AuthorizedSession

    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    session = AuthorizedSession(credentials)
    endpoint = (
        f"https://{location}-aiplatform.googleapis.com/v1/projects/{project}"
        f"/locations/{location}/publishers/google/models/{model}:generateContent"
    )
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": [
            {
                "role": "user",
                "parts": [{"text": json.dumps(request, ensure_ascii=False)}],
            }
        ],
        "generationConfig": {
            "temperature": 0,
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
        },
    }
    response = session.post(endpoint, json=payload, timeout=120)
    response.raise_for_status()
    body = response.json()
    try:
        text = "".join(
            part.get("text", "")
            for part in body["candidates"][0]["content"]["parts"]
        )
    except (KeyError, IndexError, TypeError) as exc:
        raise ValueError("Vertex AI returned no review candidate") from exc
    return validate_result(json.loads(text))


def main() -> int:
    args = parse_args()
    if not args.project:
        print("security-gate: --project is required", file=sys.stderr)
        return 2
    if not args.prompt_file.is_file() or not args.diff_file.is_file():
        print("security-gate: prompt or diff file is missing", file=sys.stderr)
        return 2

    diff_bytes = args.diff_file.read_bytes()
    if len(diff_bytes) > args.max_diff_bytes:
        print(
            f"security-gate: diff is {len(diff_bytes)} bytes; "
            f"limit is {args.max_diff_bytes}; refusing to truncate",
            file=sys.stderr,
        )
        return 2
    if not diff_bytes:
        result = {"pass": True, "findings": []}
    else:
        changed_files = [
            line
            for line in args.changed_files_file.read_text(encoding="utf-8").splitlines()
            if line
        ]
        request = {
            "repo": args.repo,
            "pr_number": int(args.pr_number) if args.pr_number.isdigit() else None,
            "diff": diff_bytes.decode("utf-8", errors="replace"),
            "changed_files": changed_files,
        }
        try:
            result = call_vertex(
                args.project,
                args.location,
                args.model,
                args.prompt_file.read_text(encoding="utf-8"),
                request,
            )
        except Exception as exc:  # Fail closed; details are safe metadata only.
            print(
                f"security-gate: Vertex review failed: {type(exc).__name__}: {exc}",
                file=sys.stderr,
            )
            return 2

    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for finding in result["findings"]:
        summary = " ".join(finding["summary"].split())[:300]
        print(
            f"[{finding['severity']}] {finding['category']} "
            f"{finding['file']}:{finding['line']} - {summary}"
        )

    if any(
        finding["severity"] in BLOCKING_SEVERITIES
        for finding in result["findings"]
    ):
        print("security-gate: blocked by Vertex AI review", file=sys.stderr)
        return 1
    print("security-gate: Vertex AI review passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

