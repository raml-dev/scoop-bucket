# Copyright 2026-present raml-dev
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

log() {
  printf '[scoop-bucket] %s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "missing required environment variable: ${name}"
  fi
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

REPO_ROOT="$(repo_root)"
WORK_DIR="${RUNNER_TEMP:-/tmp}/scoop-bucket-work"
RELEASE_JSON_PATH="${WORK_DIR}/release.json"
SHA256SUMS_PATH="${WORK_DIR}/SHA256SUMS"

manifest_path() {
  printf '%s\n' "${REPO_ROOT}/bucket/${MANIFEST_NAME}.json"
}

release_api_headers() {
  if [[ -n "${SOURCE_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    printf '%s\n' \
      "-H" "Authorization: Bearer ${SOURCE_GITHUB_TOKEN:-${GITHUB_TOKEN}}" \
      "-H" "Accept: application/vnd.github+json"
  else
    printf '%s\n' "-H" "Accept: application/vnd.github+json"
  fi
}

fetch_release_json() {
  local -a curl_args

  mapfile -t curl_args < <(release_api_headers)
  if curl -fsSL "${curl_args[@]}" "${PACKAGE_RELEASE_API_URL}" > "${RELEASE_JSON_PATH}"; then
    return
  fi

  curl -fsSL -H "Accept: application/vnd.github+json" "${PACKAGE_RELEASE_API_URL}" > "${RELEASE_JSON_PATH}"
}

validate_release() {
  jq -e '.prerelease == false' "${RELEASE_JSON_PATH}" >/dev/null || die "refusing to ingest a prerelease"
  jq -e '.draft == false' "${RELEASE_JSON_PATH}" >/dev/null || die "refusing to ingest a draft release"
}

validate_dispatch() {
  [[ -n "${MANIFEST_NAME}" ]] || die "missing manifest name"
  [[ -n "${SCOOP_SOURCE_REPOSITORY}" ]] || die "missing source repository"
  case "${PACKAGE_RELEASE_API_URL}" in
    */repos/"${SCOOP_SOURCE_REPOSITORY}"/releases/*) ;;
    *)
      die "dispatch source repository mismatch for release API URL: expected ${SCOOP_SOURCE_REPOSITORY}"
      ;;
  esac
}

release_asset_browser_url() {
  local asset_name="$1"
  jq -r --arg asset_name "${asset_name}" '
    .assets[]
    | select(.name == $asset_name)
    | .browser_download_url
  ' "${RELEASE_JSON_PATH}"
}

download_public_url() {
  local url="$1"
  local output_path="$2"
  curl -fsSL "${url}" > "${output_path}"
}

download_sha256sums() {
  local url

  url="$(release_asset_browser_url "SHA256SUMS")"
  [[ -n "${url}" && "${url}" != "null" ]] || die "release asset not found: SHA256SUMS"
  download_public_url "${url}" "${SHA256SUMS_PATH}"
}

sha256_for_asset() {
  local asset_name="$1"
  awk -v asset_name="${asset_name}" '$2 == asset_name { print $1 }' "${SHA256SUMS_PATH}"
}

render_manifest() {
  local amd64_sha arm64_sha manifest_file

  amd64_sha="$(sha256_for_asset "${MANIFEST_NAME}-windows-amd64.exe")"
  arm64_sha="$(sha256_for_asset "${MANIFEST_NAME}-windows-arm64.exe")"
  [[ -n "${amd64_sha}" ]] || die "missing SHA256SUMS entry for ${MANIFEST_NAME}-windows-amd64.exe"
  [[ -n "${arm64_sha}" ]] || die "missing SHA256SUMS entry for ${MANIFEST_NAME}-windows-arm64.exe"

  manifest_file="$(manifest_path)"
  mkdir -p "$(dirname "${manifest_file}")"

  cat > "${manifest_file}" <<EOF
{
  "version": "${PACKAGE_RELEASE_VERSION}",
  "description": "${PACKAGE_APP_DESCRIPTION}",
  "homepage": "https://github.com/${SCOOP_SOURCE_REPOSITORY}",
  "license": "${PACKAGE_APP_LICENSE}",
  "architecture": {
    "64bit": {
      "url": "https://github.com/${SCOOP_SOURCE_REPOSITORY}/releases/download/${PACKAGE_RELEASE_VERSION}/${MANIFEST_NAME}-windows-amd64.exe",
      "hash": "${amd64_sha}",
      "shortcuts": [
        [
          "${MANIFEST_NAME}-windows-amd64.exe",
          "${PACKAGE_APP_NAME}"
        ]
      ]
    },
    "arm64": {
      "url": "https://github.com/${SCOOP_SOURCE_REPOSITORY}/releases/download/${PACKAGE_RELEASE_VERSION}/${MANIFEST_NAME}-windows-arm64.exe",
      "hash": "${arm64_sha}",
      "shortcuts": [
        [
          "${MANIFEST_NAME}-windows-arm64.exe",
          "${PACKAGE_APP_NAME}"
        ]
      ]
    }
  }
}
EOF
}

main() {
  require_env "MANIFEST_NAME"
  require_env "SCOOP_SOURCE_REPOSITORY"
  require_env "PACKAGE_RELEASE_VERSION"
  require_env "PACKAGE_RELEASE_API_URL"
  require_env "PACKAGE_APP_NAME"
  require_env "PACKAGE_APP_DESCRIPTION"
  require_env "PACKAGE_APP_LICENSE"


  mkdir -p "${WORK_DIR}"

  log "validating dispatch..."
  validate_dispatch
  log "fetching release..."
  fetch_release_json
  log "validating release..."
  validate_release
  log "downloading checksums..."
  download_sha256sums
  log "rendering manifest..."
  render_manifest
}

main "$@"
