#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "${root}/bin/jq-downloader"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
real_jq="$(type -p jq)"
mkdir -p "${tmp}/mise/shims" "${tmp}/asdf/shims" "${tmp}/bin" "${tmp}/plugin bin"
# A safe stand-in for a shim: executing it must fail instead of recursing.
printf '#!/bin/sh\nexit 97\n' >"${tmp}/mise/shims/jq"
chmod +x "${tmp}/mise/shims/jq"
cp "${tmp}/mise/shims/jq" "${tmp}/asdf/shims/jq"
ln -s "${real_jq}" "${tmp}/bin/jq"
ln -s "${real_jq}" "${tmp}/plugin bin/jq"
currentDir="${tmp}/plugin bin"

check_jq() {
  local name="$1" search_path="$2" result
  JQ_BIN=""
  PATH="${search_path}" download_jq_if_not_exists
  if result="$("${JQ_BIN}" -nr '1 + 1')" && [[ "${result}" == 2 ]]; then
    echo "PASS ${name}"
  else
    echo "FAIL ${name}: selected ${JQ_BIN}"
    return 1
  fi
}

check_jq "skip mise shim" "${tmp}/mise/shims:${tmp}/bin"
check_jq "skip asdf shim" "${tmp}/asdf/shims:${tmp}/bin"
check_jq "reuse bundled jq with only shims" "${tmp}/mise/shims:${tmp}/asdf/shims"
check_jq "reuse bundled jq without PATH jq" "${tmp}/bin/missing"
check_jq "use ordinary PATH jq" "${tmp}/bin"
