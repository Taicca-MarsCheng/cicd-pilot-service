import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SELECTOR = ROOT / "scripts" / "deploy" / "select_traffic_url.py"


class CloudRunHealthCheckTest(unittest.TestCase):
    def test_selects_candidate_url_by_tag_not_array_position(self) -> None:
        service = {
            "status": {
                "traffic": [
                    {
                        "revisionName": "service-old",
                        "percent": 100,
                        "url": "https://stable.example.test",
                    },
                    {
                        "revisionName": "service-new",
                        "percent": 0,
                        "tag": "candidate",
                        "url": "https://candidate.example.test",
                    },
                ]
            }
        }

        result = subprocess.run(
            ["python3", str(SELECTOR), "candidate"],
            input=json.dumps(service),
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "https://candidate.example.test")

    def test_health_endpoint_avoids_cloud_run_reserved_z_suffix(self) -> None:
        app_source = (ROOT / "app" / "main.py").read_text()
        deploy_config = (ROOT / "cloudbuild-deploy.yaml").read_text()

        self.assertIn('@app.get("/health")', app_source)
        self.assertIn('"$${candidate_url}/health"', deploy_config)
        self.assertIn("select_traffic_url.py candidate", deploy_config)
        self.assertNotIn("/healthz", app_source)
        self.assertNotIn("/healthz", deploy_config)
        self.assertNotIn("status.traffic[?tag", deploy_config)


if __name__ == "__main__":
    unittest.main()
