#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/utils.sh
source "${root}/bin/utils.sh"
export JQ_BIN="$(command -v jq)"
export FLUTTER_RELEASES_JSON
FLUTTER_RELEASES_JSON="$(cat "${root}/tests/fixtures/releases_macos.json")"
export ASDF_PLUGIN_PATH="${root}"

fail=0
ref="$(resolve_install_ref "beta")"
[[ "$ref" == "bbb111" ]] && echo "PASS beta->hash" || { echo "FAIL beta->hash $ref"; fail=1; }
ref="$(resolve_install_ref "3.41.5-stable")"
[[ "$ref" == "sss111" ]] && echo "PASS concrete->hash" || { echo "FAIL concrete $ref"; fail=1; }
exit "$fail"
