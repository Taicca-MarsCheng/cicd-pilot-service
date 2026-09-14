"""Minimal HTTP service used to verify the CI/CD pilot."""

from flask import Flask, Response


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/")
    def index() -> Response:
        return Response("cicd-pilot-service is running\n", mimetype="text/plain")

    @app.get("/healthz")
    def healthz() -> Response:
        return Response("ok\n", status=200, mimetype="text/plain")

    return app


app = create_app()

