#!/usr/bin/env python3
"""Minimal Flask demo app for OpenShift deployment."""

import os

from flask import Flask, jsonify

app = Flask(__name__)

NAMESPACE = os.environ.get("NAMESPACE", "unknown")
APP_NAME = os.environ.get("APP_NAME", "demo-web")


@app.route("/")
def index():
    return (
        f"<html><head><title>{APP_NAME}</title></head>"
        f"<body><h1>Hello from {NAMESPACE}</h1>"
        f"<p>Deployed by Ansible on OpenShift.</p>"
        f"<p>App: <strong>{APP_NAME}</strong></p>"
        f"</body></html>"
    )


@app.route("/healthz")
def healthz():
    return jsonify(status="ok", namespace=NAMESPACE, app=APP_NAME)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
