#!/usr/bin/env bash
# Deploy a tagged candidate revision, including the first-service bootstrap case.
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 PROJECT REGION IMAGE_URI RUNTIME_SA SERVICE_NAME PUBLIC_ACCESS" >&2
  exit 2
fi

readonly project_id="$1"
readonly region="$2"
readonly image_uri="$3"
readonly runtime_sa="$4"
readonly service_name="$5"
readonly public_access="$6"

case "${public_access}" in
  true) access_flag='--allow-unauthenticated' ;;
  false) access_flag='--no-allow-unauthenticated' ;;
  *)
    echo "PUBLIC_ACCESS must be true or false" >&2
    exit 2
    ;;
esac

deploy_revision() {
  gcloud run deploy "${service_name}" \
    --project="${project_id}" \
    --region="${region}" \
    --image="${image_uri}" \
    --service-account="${runtime_sa}" \
    "$@" \
    --tag=candidate \
    "${access_flag}" \
    --quiet
}

if gcloud run services describe "${service_name}" \
  --project="${project_id}" \
  --region="${region}" \
  >/dev/null 2>&1; then
  deploy_revision --no-traffic
else
  echo "Cloud Run bootstrap: the first revision will serve traffic after it is ready"
  deploy_revision
fi
