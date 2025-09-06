#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Self-hosted GitHub Actions runner entrypoint (newline-safe)
# -----------------------------------------------------------------------------
# Required env vars:
#   GITHUB_TOKEN       -> PAT or GitHub App token with rights to register runners
#   GITHUB_REPOSITORY  -> "owner/repo"   (repo-level runner)
#      OR
#   GITHUB_ORG         -> "my-org"       (org-level runner)
#
# Optional:
#   GITHUB_URL         -> defaults to https://github.com
#   RUNNER_NAME        -> defaults to container hostname
#   RUNNER_WORKDIR     -> defaults to _work
#   RUNNER_LABELS      -> defaults to "self-hosted,linux,x64"
# -----------------------------------------------------------------------------

# --- Sanitize function (strip CR, LF, leading/trailing spaces) ---
sanitize() {
  echo -n "$1" | tr -d '\r\n' | xargs
}

# --- Clean all inputs ---
GITHUB_URL=$(sanitize "${GITHUB_URL:-https://github.com}")
GITHUB_TOKEN=$(sanitize "${GITHUB_TOKEN:-}")
GITHUB_REPOSITORY=$(sanitize "${GITHUB_REPOSITORY:-}")
GITHUB_ORG=$(sanitize "${GITHUB_ORG:-}")
RUNNER_NAME=$(sanitize "${RUNNER_NAME:-$(hostname)}")
RUNNER_WORKDIR=$(sanitize "${RUNNER_WORKDIR:-_work}")
RUNNER_LABELS=$(sanitize "${RUNNER_LABELS:-self-hosted,linux,x64}")

API_URL="https://api.github.com"

# --- Validate ---
if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN must be provided"
  exit 2
fi
if [ -z "$GITHUB_REPOSITORY" ] && [ -z "$GITHUB_ORG" ]; then
  echo "ERROR: Set GITHUB_REPOSITORY (owner/repo) or GITHUB_ORG"
  exit 2
fi

# --- Pick repo or org endpoints ---
if [ -n "$GITHUB_REPOSITORY" ]; then
  ENDPOINT_REG="${API_URL}/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token"
  ENDPOINT_REMOVE="${API_URL}/repos/${GITHUB_REPOSITORY}/actions/runners/remove-token"
  TARGET_URL="${GITHUB_URL}/${GITHUB_REPOSITORY}"
else
  ENDPOINT_REG="${API_URL}/orgs/${GITHUB_ORG}/actions/runners/registration-token"
  ENDPOINT_REMOVE="${API_URL}/orgs/${GITHUB_ORG}/actions/runners/remove-token"
  TARGET_URL="${GITHUB_URL}/${GITHUB_ORG}"
fi

# --- Helper to request registration token ---
create_reg_token() {
  curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "$ENDPOINT_REG" | jq -r .token
}

# --- Helper to request removal token ---
create_remove_token() {
  curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "$ENDPOINT_REMOVE" | jq -r .token
}

# --- Cleanup on exit ---
cleanup() {
  echo "Cleanup: attempting to deregister runner..."
  REMOVE_TOKEN=$(create_remove_token || true)
  if [ -n "$REMOVE_TOKEN" ] && [ "$REMOVE_TOKEN" != "null" ]; then
    ./config.sh remove --token "$REMOVE_TOKEN" || true
    echo "Runner deregistered."
  else
    echo "No remove token. Cleaning local runner state."
    rm -f .runner .credentials || true
  fi
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Register runner ---
echo "Requesting registration token..."
REG_TOKEN=$(create_reg_token)
if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" = "null" ]; then
  echo "ERROR: Failed to get registration token from GitHub"
  exit 3
fi

echo "Configuring runner: $RUNNER_NAME"
./config.sh --unattended \
  --url "$TARGET_URL" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --work "$RUNNER_WORKDIR" \
  --labels "$RUNNER_LABELS" \
  --replace

# --- Run the runner (blocks until stopped) ---
exec ./run.sh
