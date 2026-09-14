#!/usr/bin/env bash
# Usage: ./docs/onboard-new-repo.sh <repo-name> [region]
# This script changes GCP state. Review MANUAL_RUNBOOK.md before running it.
set -euo pipefail

readonly PROJECT_ID="${PROJECT_ID:-taicca-geminiapi}"
readonly GITHUB_CONNECTION="${GITHUB_CONNECTION:-github-fantasyjack99}"
readonly ARTIFACT_REPOSITORY="${ARTIFACT_REPOSITORY:-cicd-services}"
readonly AI_MODEL="${AI_MODEL:-gemini-flash-latest}"
readonly PUBLIC_ACCESS="${PUBLIC_ACCESS:-true}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  echo "Usage: $0 <repo-name> [region]" >&2
  echo "Optional env: PROJECT_ID GITHUB_CONNECTION ARTIFACT_REPOSITORY AI_MODEL" >&2
  echo "              PUBLIC_ACCESS BUILD_SA_EMAIL ASSUME_YES" >&2
  exit 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage
readonly REPO_NAME="$1"
readonly REGION="${2:-asia-east1}"

[[ "${REPO_NAME}" =~ ^[a-z][a-z0-9-]{1,48}[a-z0-9]$ ]] \
  || die "repo-name must be 3-50 lowercase letters, digits, or hyphens"
[[ "${REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]] || die "invalid GCP region"
[[ "${PUBLIC_ACCESS}" == "true" || "${PUBLIC_ACCESS}" == "false" ]] \
  || die "PUBLIC_ACCESS must be true or false"
[[ "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "invalid project ID"
[[ "${GITHUB_CONNECTION}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid connection name"
[[ "${ARTIFACT_REPOSITORY}" =~ ^[a-z][a-z0-9._-]{1,61}[a-z0-9]$ ]] \
  || die "invalid Artifact Registry repository name"
[[ "${AI_MODEL}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid Vertex AI model ID"

for command_name in gcloud git; do
  command -v "${command_name}" >/dev/null 2>&1 \
    || die "${command_name} is required"
done

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "${repo_root}"

active_account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n 1)
[[ -n "${active_account}" ]] || die "no active gcloud account; run gcloud auth login first"

readonly RUNTIME_SA_NAME="sa-${REPO_NAME}"
readonly RUNTIME_SA_EMAIL="${RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
readonly REPOSITORY_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/connections/${GITHUB_CONNECTION}/repositories/${REPO_NAME}"

for api in \
  aiplatform.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  iam.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com; do
  enabled=$(gcloud services list --enabled --project="${PROJECT_ID}" \
    --filter="config.name=${api}" --format='value(config.name)')
  [[ "${enabled}" == "${api}" ]] || die "required API is not enabled: ${api}"
done

default_build_sa_resource=$(gcloud builds get-default-service-account \
  --project="${PROJECT_ID}" --region="${REGION}" \
  --format='value(serviceAccountEmail)')
default_build_sa_email=${default_build_sa_resource##*/}
readonly BUILD_SA_EMAIL="${BUILD_SA_EMAIL:-${default_build_sa_email}}"
[[ -n "${BUILD_SA_EMAIL}" ]] || die "cannot resolve the Cloud Build default service account"
[[ "${BUILD_SA_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] \
  || die "invalid build service account email"

gcloud builds connections describe "${GITHUB_CONNECTION}" \
  --project="${PROJECT_ID}" --region="${REGION}" >/dev/null \
  || die "Cloud Build connection not found: ${GITHUB_CONNECTION} (${REGION})"
gcloud builds repositories describe "${REPO_NAME}" \
  --connection="${GITHUB_CONNECTION}" \
  --project="${PROJECT_ID}" --region="${REGION}" >/dev/null \
  || die "linked repository not found under connection: ${REPO_NAME}"
gcloud iam service-accounts describe "${BUILD_SA_EMAIL}" \
  --project="${PROJECT_ID}" >/dev/null \
  || die "build service account does not exist: ${BUILD_SA_EMAIL}"

for trigger_name in "${REPO_NAME}-security-gate" "${REPO_NAME}-deploy"; do
  if gcloud builds triggers describe "${trigger_name}" \
    --project="${PROJECT_ID}" --region="${REGION}" >/dev/null 2>&1; then
    die "trigger already exists: ${trigger_name}; review it manually instead of overwriting"
  fi
done

echo "Plan:"
echo "  project:             ${PROJECT_ID}"
echo "  repository:          ${REPOSITORY_RESOURCE}"
echo "  build identity:      ${BUILD_SA_EMAIL}"
echo "  runtime identity:    ${RUNTIME_SA_EMAIL}"
echo "  artifact repository: ${ARTIFACT_REPOSITORY} (${REGION})"
echo "  public access:       ${PUBLIC_ACCESS}"
echo "  AI model:            ${AI_MODEL}"

if [[ "${ASSUME_YES:-false}" != "true" ]]; then
  read -r -p "Type ${REPO_NAME} to apply these GCP changes: " confirmation
  [[ "${confirmation}" == "${REPO_NAME}" ]] || die "cancelled"
fi

if ! gcloud artifacts repositories describe "${ARTIFACT_REPOSITORY}" \
  --project="${PROJECT_ID}" --location="${REGION}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${ARTIFACT_REPOSITORY}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --repository-format=docker \
    --description='Images built by collaborator CI/CD pipelines'
  echo "Created Artifact Registry repository: ${ARTIFACT_REPOSITORY}"
else
  echo "Artifact Registry repository already exists: ${ARTIFACT_REPOSITORY}"
fi

if ! gcloud iam service-accounts describe "${RUNTIME_SA_EMAIL}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${RUNTIME_SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Runtime SA for ${REPO_NAME}"
  echo "Created runtime service account: ${RUNTIME_SA_EMAIL}"
else
  echo "Runtime service account already exists: ${RUNTIME_SA_EMAIL}"
fi

for role in \
  roles/aiplatform.user \
  roles/artifactregistry.writer \
  roles/logging.logWriter \
  roles/run.admin; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${BUILD_SA_EMAIL}" \
    --role="${role}" \
    --condition=None >/dev/null
  echo "Ensured build SA role: ${role}"
done

gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --member="serviceAccount:${BUILD_SA_EMAIL}" \
  --role=roles/iam.serviceAccountUser \
  --condition=None >/dev/null
echo "Allowed build SA to use only this runtime service account"

common_substitutions="_SERVICE_NAME=${REPO_NAME},_REGION=${REGION},_RUNTIME_SA=${RUNTIME_SA_EMAIL},_AI_MODEL=${AI_MODEL}"

# Inline config plus protected-main bootstrap prevents a PR from replacing its gate.
gcloud builds triggers create github \
  --name="${REPO_NAME}-security-gate" \
  --description="PR security-gate for ${REPO_NAME}" \
  --repository="${REPOSITORY_RESOURCE}" \
  --pull-request-pattern='^main$' \
  --comment-control=COMMENTS_DISABLED \
  --inline-config=cloudbuild-pr-check.yaml \
  --include-logs-with-status \
  --service-account="projects/${PROJECT_ID}/serviceAccounts/${BUILD_SA_EMAIL}" \
  --substitutions="${common_substitutions}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

gcloud builds triggers create github \
  --name="${REPO_NAME}-deploy" \
  --description="Deploy main for ${REPO_NAME}" \
  --repository="${REPOSITORY_RESOURCE}" \
  --branch-pattern='^main$' \
  --build-config=cloudbuild-deploy.yaml \
  --include-logs-with-status \
  --service-account="projects/${PROJECT_ID}/serviceAccounts/${BUILD_SA_EMAIL}" \
  --substitutions="${common_substitutions},_AR_REPOSITORY=${ARTIFACT_REPOSITORY},_PUBLIC_ACCESS=${PUBLIC_ACCESS}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}"

echo "Onboarding complete. Expected triggers:"
echo "  ${REPO_NAME}-security-gate (pull requests to main)"
echo "  ${REPO_NAME}-deploy (pushes to main)"
echo "Next: open a test PR, then use its exact GitHub check name in branch protection."
