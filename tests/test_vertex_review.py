import importlib.util
import unittest
from pathlib import Path


SCRIPT = (
    Path(__file__).parents[1]
    / "scripts"
    / "security-gate"
    / "run_vertex_review.py"
)
SPEC = importlib.util.spec_from_file_location("run_vertex_review", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VertexEndpointTest(unittest.TestCase):
    def test_global_location_uses_unprefixed_api_host(self) -> None:
        self.assertEqual(
            MODULE.build_vertex_endpoint(
                "example-project", "global", "gemini-3.1-flash-lite"
            ),
            "https://aiplatform.googleapis.com/v1/projects/example-project/"
            "locations/global/publishers/google/models/"
            "gemini-3.1-flash-lite:generateContent",
        )

    def test_regional_location_uses_regional_api_host(self) -> None:
        self.assertEqual(
            MODULE.build_vertex_endpoint(
                "example-project", "asia-east1", "regional-model"
            ),
            "https://asia-east1-aiplatform.googleapis.com/v1/projects/"
            "example-project/locations/asia-east1/publishers/google/models/"
            "regional-model:generateContent",
        )


if __name__ == "__main__":
    unittest.main()
