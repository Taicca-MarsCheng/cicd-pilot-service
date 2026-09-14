#!/usr/bin/env bash
# Usage: ./docs/add-secret.sh <repo-name> <secret-name>
# This script changes Secret Manager and IAM state. It never echoes the value.
set -euo pipefail

readonly PROJECT_ID="${PROJECT_ID:-taicca-geminiapi}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || die "Usage: $0 <repo-name> <secret-name>"
readonly REPO_NAME="$1"
readonly SECRET_NAME="$2"
readonly SA_EMAIL="sa-${REPO_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

[[ "${REPO_NAME}" =~ ^[a-z][a-z0-9-]{1,48}[a-z0-9]$ ]] || die "invalid repo-name"
[[ "${SECRET_NAME}" =~ ^[A-Za-z][A-Za-z0-9_-]{0,254}$ ]] || die "invalid secret-name"
command -v gcloud >/dev/null 2>&1 || die "gcloud is required"

gcloud iam service-accounts describe "${SA_EMAIL}" \
  --project="${PROJECT_ID}" >/dev/null \
  || die "runtime service account does not exist: ${SA_EMAIL}"

read -r -s -p "Paste the one-time secret value (input is hidden): " secret_value
echo
[[ -n "${secret_value}" ]] || die "secret value cannot be empty"
trap 'unset secret_value' EXIT

if gcloud secrets describe "${SECRET_NAME}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  printf '%s' "${secret_value}" | gcloud secrets versions add "${SECRET_NAME}" \
    --project="${PROJECT_ID}" --data-file=- >/dev/null
  echo "Added a new version to secret: ${SECRET_NAME}"
else
  printf '%s' "${secret_value}" | gcloud secrets create "${SECRET_NAME}" \
    --project="${PROJECT_ID}" \
    --replication-policy=automatic \
    --data-file=- >/dev/null
  echo "Created secret: ${SECRET_NAME}"
fi
unset secret_value

gcloud secrets add-iam-policy-binding "${SECRET_NAME}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role=roles/secretmanager.secretAccessor \
  --condition=None >/dev/null

echo "Granted ${SA_EMAIL} access to ${SECRET_NAME}; share only the secret name."

