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

    def test_trigger_updates_substitutions_before_inline_config(self) -> None:
        update_command = "gcloud builds triggers update github"
        self.assertEqual(self.updater.count(update_command), 2)
        substitutions = self.updater.index("--update-substitutions")
        inline_config = self.updater.index("--inline-config")
        self.assertLess(substitutions, inline_config)


if __name__ == "__main__":
    unittest.main()
