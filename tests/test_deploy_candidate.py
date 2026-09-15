import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
DEPLOY_SCRIPT = ROOT / "scripts" / "deploy" / "deploy_candidate.sh"


class DeployCandidateTest(unittest.TestCase):
    def run_deploy(
        self, service_exists: bool, public_access: str = "true"
    ) -> list[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            log_file = temp / "gcloud.log"

            gcloud = fake_bin / "gcloud"
            gcloud.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >>\"$GCLOUD_LOG\"\n"
                "if [ \"$1 $2 $3\" = 'run services describe' ]; then\n"
                "  [ \"$SERVICE_EXISTS\" = 'true' ]\n"
                "  exit $?\n"
                "fi\n"
                "exit 0\n"
            )
            gcloud.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            env["GCLOUD_LOG"] = str(log_file)
            env["SERVICE_EXISTS"] = "true" if service_exists else "false"

            result = subprocess.run(
                [
                    str(DEPLOY_SCRIPT),
                    "test-project",
                    "asia-east1",
                    "asia-east1-docker.pkg.dev/test/repo/service:abc1234",
                    "runtime@test-project.iam.gserviceaccount.com",
                    "cicd-pilot-service",
                    public_access,
                ],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            calls = log_file.read_text().splitlines() if log_file.exists() else []

        self.assertEqual(result.returncode, 0, result.stderr)
        return calls

    def test_first_deploy_omits_unsupported_no_traffic_flag(self) -> None:
        calls = self.run_deploy(service_exists=False)
        deploy_call = next(call for call in calls if call.startswith("run deploy "))
        self.assertNotIn("--no-traffic", deploy_call)
        self.assertIn("--tag=candidate", deploy_call)

    def test_existing_service_deploys_candidate_without_traffic(self) -> None:
        calls = self.run_deploy(service_exists=True)
        deploy_call = next(call for call in calls if call.startswith("run deploy "))
        self.assertIn("--no-traffic", deploy_call)

    def test_private_service_disallows_unauthenticated_access(self) -> None:
        calls = self.run_deploy(service_exists=True, public_access="false")
        deploy_call = next(call for call in calls if call.startswith("run deploy "))
        self.assertIn("--no-allow-unauthenticated", deploy_call)

    def test_cloud_build_calls_tested_deploy_script(self) -> None:
        config = (ROOT / "cloudbuild-deploy.yaml").read_text()
        self.assertIn("scripts/deploy/deploy_candidate.sh", config)


if __name__ == "__main__":
    unittest.main()
