import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class GovernancePolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.context = (ROOT / "CONTEXT.md").read_text()
        cls.readme = (ROOT / "README.md").read_text()
        cls.runbook = (ROOT / "docs" / "MANUAL_RUNBOOK.md").read_text()
        cls.spec = (ROOT / "docs" / "system-spec.md").read_text()

    def test_core_mode_is_current_and_governed_mode_is_retained(self) -> None:
        for document in (self.context, self.readme, self.runbook, self.spec):
            self.assertIn("核心開發模式", document)
            self.assertIn("協作者治理模式", document)

    def test_core_mode_keeps_deployment_gate(self) -> None:
        self.assertIn("部署關卡", self.context)
        self.assertIn("Gitleaks + Vertex AI", self.spec)
        self.assertIn("失敗即停止建置與部署", self.spec)

    def test_onboarding_defaults_to_core_mode(self) -> None:
        result = subprocess.run(
            [str(ROOT / "docs" / "onboard-new-repo.sh")],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 64)
        self.assertIn("GOVERNANCE_PHASE (core|governed)", result.stderr)
        onboarding = (ROOT / "docs" / "onboard-new-repo.sh").read_text()
        self.assertIn('GOVERNANCE_PHASE="${GOVERNANCE_PHASE:-core}"', onboarding)
        self.assertIn("Leave branch protection off in core mode", onboarding)


if __name__ == "__main__":
    unittest.main()
