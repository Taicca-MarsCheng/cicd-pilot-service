#!/usr/bin/env bash
# Usage: ./docs/update-security-gate.sh <repo-name> [region]
# Repairs or updates an existing PR trigger without recreating it.
set -euo pipefail

readonly PROJECT_ID="${PROJECT_ID:-taicca-geminiapi}"
readonly AI_MODEL="${AI_MODEL:-gemini-3.1-flash-lite}"
readonly AI_LOCATION="${AI_LOCATION:-global}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] \
  || die "Usage: $0 <repo-name> [region]"
readonly REPO_NAME="$1"
readonly REGION="${2:-asia-east1}"
readonly TRIGGER_NAME="${REPO_NAME}-security-gate"
readonly RUNTIME_SA_EMAIL="sa-${REPO_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
readonly GITHUB_DEPLOY_KEY_SECRET="${GITHUB_DEPLOY_KEY_SECRET:-${REPO_NAME}-github-deploy-key}"

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "${repo_root}"

default_build_sa_resource=$(gcloud builds get-default-service-account \
  --project="${PROJECT_ID}" --region="${REGION}" \
  --format='value(serviceAccountEmail)')
default_build_sa_email=${default_build_sa_resource##*/}
readonly BUILD_SA_EMAIL="${BUILD_SA_EMAIL:-${default_build_sa_email}}"
[[ -n "${BUILD_SA_EMAIL}" ]] || die "cannot resolve Cloud Build service account"

gcloud builds triggers describe "${TRIGGER_NAME}" \
  --project="${PROJECT_ID}" --region="${REGION}" >/dev/null \
  || die "trigger not found: ${TRIGGER_NAME}"
gcloud secrets describe "${GITHUB_DEPLOY_KEY_SECRET}" \
  --project="${PROJECT_ID}" >/dev/null \
  || die "secret not found: ${GITHUB_DEPLOY_KEY_SECRET}"

echo "Plan:"
echo "  trigger:           ${TRIGGER_NAME}"
echo "  build identity:    ${BUILD_SA_EMAIL}"
echo "  deploy-key secret: ${GITHUB_DEPLOY_KEY_SECRET}"
read -r -p "Type ${REPO_NAME} to update the PR gate: " confirmation
[[ "${confirmation}" == "${REPO_NAME}" ]] || die "cancelled"

gcloud secrets add-iam-policy-binding "${GITHUB_DEPLOY_KEY_SECRET}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${BUILD_SA_EMAIL}" \
  --role=roles/secretmanager.secretAccessor \
  --condition=None >/dev/null

substitutions="_SERVICE_NAME=${REPO_NAME},_REGION=${REGION},_RUNTIME_SA=${RUNTIME_SA_EMAIL},_AI_MODEL=${AI_MODEL},_AI_LOCATION=${AI_LOCATION},_GITHUB_DEPLOY_KEY_SECRET=${GITHUB_DEPLOY_KEY_SECRET}"
gcloud builds triggers update github "${TRIGGER_NAME}" \
  --update-substitutions="${substitutions}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

gcloud builds triggers update github "${TRIGGER_NAME}" \
  --inline-config=cloudbuild-pr-check.yaml \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

echo "Security gate updated. Push a new PR commit; do not retry the old build."
