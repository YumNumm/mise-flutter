#!/usr/bin/env bash

flutter_storage_base_url() {
  echo "${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"
}

flutter_git_url() {
  echo "${FLUTTER_GIT_URL:-https://github.com/flutter/flutter.git}"
}

flutter_git_cache_path() {
  if [[ -n "${FLUTTER_GIT_CACHE_PATH:-}" ]]; then
    echo "${FLUTTER_GIT_CACHE_PATH}"
    return
  fi
  if [[ -z "${ASDF_PLUGIN_PATH:-}" ]]; then
    echo "ASDF_PLUGIN_PATH or FLUTTER_GIT_CACHE_PATH is required" >&2
    return 1
  fi
  echo "${ASDF_PLUGIN_PATH}/.git-cache"
}

ensure_git_cache() {
  local cache_path remote
  cache_path="$(flutter_git_cache_path)"
  remote="$(flutter_git_url)"

  if [[ ! -d "${cache_path}" ]]; then
    mkdir -p "$(dirname "${cache_path}")"
    git clone --bare --progress "${remote}" "${cache_path}"
    return
  fi

  git --git-dir="${cache_path}" fetch --progress --tags origin '+refs/heads/*:refs/heads/*'
}

flutter_releases_url() {
  local base
  base="$(flutter_storage_base_url)"
  case "$(uname -s)" in
  Linux) echo "${base}/flutter_infra_release/releases/releases_linux.json" ;;
  *) echo "${base}/flutter_infra_release/releases/releases_macos.json" ;;
  esac
}

is_release_channel() {
  [[ "$1" =~ ^(stable|beta|dev)$ ]]
}

is_git_channel() {
  [[ "$1" =~ ^(master|main)$ ]]
}

fetch_releases_json() {
  if [[ -n "${FLUTTER_RELEASES_JSON:-}" ]]; then
    printf '%s' "${FLUTTER_RELEASES_JSON}"
    return
  fi
  curl -fsSL "$(flutter_releases_url)"
}

version_name_for_hash() {
  local json="$1" hash="$2" channel="$3"
  echo "${json}" | "${JQ_BIN}" -r --arg HASH "${hash}" --arg C "${channel}" '
    limit(1;
      .releases[]
      | select(.hash == $HASH and .channel == $C)
      | ((.version | ltrimstr("v")) + "-" + .channel)
    )
  '
}

hash_for_version() {
  local json="$1" version="$2"
  echo "${json}" | "${JQ_BIN}" -r --arg VERSION "${version}" '
    limit(1;
      .releases[]
      | (.version | ltrimstr("v")) as $v
      | select(
          ($v + "-" + .channel) == $VERSION
          or $v == $VERSION
          or (.version + "-" + .channel) == $VERSION
        )
      | .hash
      )
  '
}

resolve_install_ref() {
  local version="$1"
  local json hash

  if is_git_channel "${version}"; then
    hash="$(git ls-remote --heads "$(flutter_git_url)" "refs/heads/${version}" | awk '{print $1}')"
    if [[ -z "${hash}" ]]; then
      echo "Cannot resolve git channel: ${version}" >&2
      return 1
    fi
    echo "${hash}"
    return
  fi

  json="$(fetch_releases_json)" || return 1

  if is_release_channel "${version}"; then
    hash="$(echo "${json}" | "${JQ_BIN}" -r --arg C "${version}" '.current_release[$C] // empty')"
    if [[ -z "${hash}" || "${hash}" == "null" ]]; then
      echo "Cannot resolve channel from JSON: ${version}" >&2
      return 1
    fi
    echo "${hash}"
    return
  fi

  hash="$(hash_for_version "${json}" "${version}")"
  if [[ -n "${hash}" && "${hash}" != "null" ]]; then
    echo "${hash}"
    return
  fi

  # Unknown: treat as git ref (commit/tag/branch name)
  echo "${version}"
}
