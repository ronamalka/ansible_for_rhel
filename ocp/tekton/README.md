# Tekton pipeline for demo-web

Builds the Flask sample app from a ConfigMap source bundle and deploys it to a target namespace on OpenShift.

## Prerequisites

- OpenShift Pipelines operator installed (`oc get csv -n openshift-operators | grep pipelines`)
- Namespace with permission to create PipelineRuns (typically the target namespace)

## Resources

| File | Purpose |
|------|---------|
| `rbac.yaml` | ServiceAccount and Role for pipeline tasks |
| `pipeline.yaml` | Tasks and Pipeline (fetch → buildah → deploy) |
| `pipelinerun-template.yaml` | Example PipelineRun (Ansible substitutes parameters) |

## Manual install (bastion)

```bash
export TARGET_NS=demo-web-test
oc create namespace "${TARGET_NS}" --dry-run=client -o yaml | oc apply -f -
oc apply -f ocp/tekton/rbac.yaml -n "${TARGET_NS}"
oc apply -f ocp/tekton/pipeline.yaml -n "${TARGET_NS}"

# Create source ConfigMap from repo
oc create configmap demo-web-source \
  --from-file=app.py=apps/demo-web/app.py \
  --from-file=requirements.txt=apps/demo-web/requirements.txt \
  --from-file=Dockerfile=apps/demo-web/Dockerfile \
  -n "${TARGET_NS}" --dry-run=client -o yaml | oc apply -f -

# Launch pipeline
sed "s/REPLACE_NAMESPACE/${TARGET_NS}/g; s/REPLACE_APP_NAME/demo-web/g; s/REPLACE_SOURCE_CONFIGMAP/demo-web-source/g" \
  ocp/tekton/pipelinerun-template.yaml | oc create -f - -n "${TARGET_NS}"

oc get pipelinerun -n "${TARGET_NS}"
oc get route -n "${TARGET_NS}"
```

## Image registry

Images are pushed to the cluster internal registry:

```
image-registry.openshift-image-registry.svc:5000/<namespace>/<app-name>:latest
```

## Ansible integration

`roles/openshift_app_deploy` detects Tekton (`pipelines.tekton.dev` CRD). When present it applies these manifests and creates a PipelineRun. Otherwise it uses direct Deployment/Service/Route manifests (no build step; uses embedded ConfigMap + UBI Python image).
