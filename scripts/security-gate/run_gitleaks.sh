#!/bin/sh
# Build the exact incremental patch and scan it without printing its contents.
set -eu

repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
diff_output="${DIFF_OUTPUT:-${repo_root}/.security-diff.patch}"
changed_files_output="${CHANGED_FILES_OUTPUT:-${repo_root}/.security-changed-files.txt}"
base_ref="${BASE_REF:-}"
diff_range="${SECURITY_DIFF_RANGE:-}"

if ! command -v git >/dev/null 2>&1; then
  echo "security-gate: git is required" >&2
  exit 2
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "security-gate: gitleaks is required" >&2
  exit 2
fi

cd "${repo_root}"

if [ -z "${diff_range}" ] && [ -n "${base_ref}" ]; then
  if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
    case "${base_ref}" in
      origin/*) base_branch=${base_ref#origin/} ;;
      *) base_branch=${base_ref} ;;
    esac
    git fetch --no-tags --depth=100 origin "${base_branch}"
    base_ref=FETCH_HEAD
  fi
  merge_base=$(git merge-base "${base_ref}" HEAD)
  diff_range="${merge_base}..HEAD"
fi

if [ -z "${diff_range}" ]; then
  if git rev-parse --verify --quiet 'HEAD^' >/dev/null; then
    diff_range='HEAD^..HEAD'
  else
    empty_tree=$(git hash-object -t tree /dev/null)
    diff_range="${empty_tree}..HEAD"
  fi
fi

git diff --binary --no-ext-diff "${diff_range}" -- >"${diff_output}"
git diff --name-only --diff-filter=ACMR "${diff_range}" -- >"${changed_files_output}"

if [ ! -s "${diff_output}" ]; then
  echo "security-gate: no changed content to scan"
  exit 0
fi

echo "security-gate: scanning incremental diff with Gitleaks"
if ! gitleaks --no-banner --redact stdin <"${diff_output}"; then
  echo "security-gate: blocked by Gitleaks; secret values were redacted" >&2
  exit 1
fi

echo "security-gate: Gitleaks passed"

