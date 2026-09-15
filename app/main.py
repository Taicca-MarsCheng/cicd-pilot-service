"""Minimal HTTP service used to verify the CI/CD pilot."""

from flask import Flask, Response


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/")
    def index() -> Response:
        return Response("cicd-pilot-service is running\n", mimetype="text/plain")

    @app.get("/health")
    def health() -> Response:
        # Controlled failure used to verify that an unhealthy candidate never
        # receives production traffic. This commit must not remain on main.
        return Response("rollback test\n", status=503, mimetype="text/plain")

    return app


app = create_app()
