import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class PrivateRepositoryBootstrapTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = (ROOT / "cloudbuild-pr-check.yaml").read_text()
        cls.onboarding = (ROOT / "docs" / "onboard-new-repo.sh").read_text()
        cls.updater = (ROOT / "docs" / "update-security-gate.sh").read_text()

    def test_private_fetch_receives_repo_scoped_deploy_key(self) -> None:
        self.assertIn("secretEnv:", self.config)
        self.assertIn("GITHUB_DEPLOY_KEY", self.config)
        self.assertIn("availableSecrets:", self.config)
        self.assertIn("_GITHUB_DEPLOY_KEY_SECRET", self.config)

    def test_fetch_uses_ssh_and_pinned_github_host_key(self) -> None:
        self.assertIn("git@github.com:${REPO_FULL_NAME}.git", self.config)
        self.assertIn(
            "github.com ssh-ed25519 "
            "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
            self.config,
        )

    def test_onboarding_requires_and_scopes_secret_access(self) -> None:
        self.assertIn("GITHUB_DEPLOY_KEY_SECRET", self.onboarding)
        self.assertIn("gcloud secrets add-iam-policy-binding", self.onboarding)
        self.assertIn("roles/secretmanager.secretAccessor", self.onboarding)

    def test_trigger_uses_full_import_instead_of_invalid_partial_patch(self) -> None:
        self.assertNotIn("gcloud builds triggers update github", self.updater)
        self.assertIn("gcloud builds triggers import", self.updater)
        self.assertIn("repositoryEventConfig:", self.updater)
        self.assertIn("includeBuildLogs: INCLUDE_BUILD_LOGS_WITH_STATUS", self.updater)

    def test_updater_generates_valid_full_trigger_config(self) -> None:
        with tempfile.TemporaryDirectory() as fake_bin:
            Path(fake_bin, "gcloud").symlink_to(ROOT / "tests" / "fixtures" / "gcloud")
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            result = subprocess.run(
                [
                    str(ROOT / "docs" / "update-security-gate.sh"),
                    "cicd-pilot-service",
                    "asia-east1",
                ],
                cwd=ROOT,
                env=env,
                input="cicd-pilot-service\n",
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Security gate updated", result.stdout)


if __name__ == "__main__":
    unittest.main()
