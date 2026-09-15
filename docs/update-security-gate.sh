#!/usr/bin/env bash
# Usage: ./docs/update-security-gate.sh <repo-name> [region]
# Repairs or updates an existing PR trigger without recreating it.
set -euo pipefail

readonly PROJECT_ID="${PROJECT_ID:-taicca-geminiapi}"
readonly GITHUB_CONNECTION="${GITHUB_CONNECTION:-github-taicca-marscheng}"
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
readonly REPOSITORY_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/connections/${GITHUB_CONNECTION}/repositories/${REPO_NAME}"

[[ "${REPO_NAME}" =~ ^[a-z][a-z0-9-]{1,48}[a-z0-9]$ ]] \
  || die "invalid repository name"
[[ "${REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]] || die "invalid region"
[[ "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "invalid project ID"
[[ "${GITHUB_CONNECTION}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid connection name"
[[ "${AI_MODEL}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid model ID"
[[ "${AI_LOCATION}" =~ ^(global|us|eu|[a-z]+-[a-z]+[0-9]+)$ ]] \
  || die "invalid AI location"
[[ "${GITHUB_DEPLOY_KEY_SECRET}" =~ ^[A-Za-z0-9_-]{1,255}$ ]] \
  || die "invalid deploy-key secret name"

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "${repo_root}"

default_build_sa_resource=$(gcloud builds get-default-service-account \
  --project="${PROJECT_ID}" --region="${REGION}" \
  --format='value(serviceAccountEmail)')
default_build_sa_email=${default_build_sa_resource##*/}
readonly BUILD_SA_EMAIL="${BUILD_SA_EMAIL:-${default_build_sa_email}}"
[[ -n "${BUILD_SA_EMAIL}" ]] || die "cannot resolve Cloud Build service account"

trigger_id=$(gcloud builds triggers describe "${TRIGGER_NAME}" \
  --project="${PROJECT_ID}" --region="${REGION}" --format='value(id)')
[[ -n "${trigger_id}" ]] || die "trigger not found: ${TRIGGER_NAME}"
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

trigger_config=$(mktemp)
cleanup_config() {
  rm -f "${trigger_config}"
}
trap cleanup_config EXIT

{
  printf 'id: %s\n' "${trigger_id}"
  printf 'name: %s\n' "${TRIGGER_NAME}"
  printf 'description: PR security-gate for %s\n' "${REPO_NAME}"
  printf 'repositoryEventConfig:\n'
  printf '  repository: %s\n' "${REPOSITORY_RESOURCE}"
  printf '  repositoryType: GITHUB\n'
  printf '  pullRequest:\n'
  printf "    branch: '^main$'\n"
  printf 'includeBuildLogs: INCLUDE_BUILD_LOGS_WITH_STATUS\n'
  printf 'serviceAccount: projects/%s/serviceAccounts/%s\n' \
    "${PROJECT_ID}" "${BUILD_SA_EMAIL}"
  printf 'substitutions:\n'
  printf "  _SERVICE_NAME: '%s'\n" "${REPO_NAME}"
  printf "  _REGION: '%s'\n" "${REGION}"
  printf "  _RUNTIME_SA: '%s'\n" "${RUNTIME_SA_EMAIL}"
  printf "  _AI_MODEL: '%s'\n" "${AI_MODEL}"
  printf "  _AI_LOCATION: '%s'\n" "${AI_LOCATION}"
  printf "  _GITHUB_DEPLOY_KEY_SECRET: '%s'\n" "${GITHUB_DEPLOY_KEY_SECRET}"
  printf 'build:\n'
  sed 's/^/  /' cloudbuild-pr-check.yaml
} > "${trigger_config}"

gcloud builds triggers import \
  --source="${trigger_config}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

echo "Security gate updated. Push a new PR commit; do not retry the old build."
