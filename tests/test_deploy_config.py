import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class DeploySecurityGateTest(unittest.TestCase):
    def test_gitleaks_handles_cloud_build_single_commit_checkout(self) -> None:
        config = (ROOT / "cloudbuild-deploy.yaml").read_text()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            repo = temp / "repo"
            fake_bin = temp / "bin"
            repo.mkdir()
            fake_bin.mkdir()

            subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Test"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "test@example.com"],
                check=True,
            )
            (repo / "app.py").write_text("print('healthy')\n")
            subprocess.run(["git", "-C", str(repo), "add", "app.py"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "commit", "--quiet", "-m", "initial"],
                check=True,
            )

            gitleaks = fake_bin / "gitleaks"
            gitleaks.write_text("#!/bin/sh\ncat >/dev/null\n")
            gitleaks.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            env["REPO_ROOT"] = str(repo)
            env["DIFF_OUTPUT"] = str(temp / "security-diff.patch")
            env["CHANGED_FILES_OUTPUT"] = str(temp / "changed-files.txt")
            if "SECURITY_DIFF_RANGE=HEAD^..HEAD" in config:
                env["SECURITY_DIFF_RANGE"] = "HEAD^..HEAD"

            result = subprocess.run(
                [str(ROOT / "scripts" / "security-gate" / "run_gitleaks.sh")],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
