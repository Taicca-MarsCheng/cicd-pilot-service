import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[1]


class FakeResponse:
    def __init__(self, body: str, status: int = 200, mimetype: str = "") -> None:
        self.body = body
        self.status_code = status
        self.mimetype = mimetype


class FakeFlask:
    def __init__(self, _name: str) -> None:
        self.routes = {}

    def get(self, path: str):
        def register(handler):
            self.routes[path] = handler
            return handler

        return register


class ApplicationTest(unittest.TestCase):
    def load_app_module(self):
        fake_flask = types.ModuleType("flask")
        fake_flask.Flask = FakeFlask
        fake_flask.Response = FakeResponse
        spec = importlib.util.spec_from_file_location(
            "cicd_pilot_app", ROOT / "app" / "main.py"
        )
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"flask": fake_flask}):
            spec.loader.exec_module(module)
        return module

    def test_health_endpoint_returns_http_200(self) -> None:
        module = self.load_app_module()
        app = module.create_app()

        response = app.routes["/health"]()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.body, "ok\n")


if __name__ == "__main__":
    unittest.main()
