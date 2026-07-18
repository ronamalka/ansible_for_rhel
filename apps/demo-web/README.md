# Demo Web Application

Simple containerized Flask application used by the **DEMO - Deploy App on OpenShift** automation.

## Behavior

- `GET /` returns an HTML page: **Hello from {namespace}**
- `GET /healthz` returns JSON for readiness checks
- Reads `NAMESPACE` and `APP_NAME` from environment variables at runtime

## Local development

```bash
cd apps/demo-web
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export NAMESPACE=local-dev APP_NAME=demo-web
python app.py
curl http://127.0.0.1:8080/
```

## Container build

```bash
podman build -t demo-web:latest .
podman run --rm -p 8080:8080 -e NAMESPACE=demo demo-web:latest
```

On OpenShift, the Tekton pipeline (or Ansible direct-deploy fallback) builds this image into the cluster internal registry and deploys it with a Route.
