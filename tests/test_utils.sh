#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/utils.sh
source "${root}/bin/utils.sh"
export JQ_BIN="$(command -v jq)"
export ASDF_PLUGIN_PATH="${root}"
export FLUTTER_RELEASES_JSON
FLUTTER_RELEASES_JSON="$(cat "${root}/tests/fixtures/releases_macos.json")"

fail=0
assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL $name: expected='$expected' actual='$actual'"
    fail=1
  else
    echo "PASS $name"
  fi
}

assert_eq "storage default" "https://storage.googleapis.com" "$(flutter_storage_base_url)"
assert_eq "stable name" "3.41.5-stable" "$(version_name_for_hash "$FLUTTER_RELEASES_JSON" "sss111")"
assert_eq "hash for 3.41.5-stable" "sss111" "$(hash_for_version "$FLUTTER_RELEASES_JSON" "3.41.5-stable")"
assert_eq "hash for 3.41.5" "sss111" "$(hash_for_version "$FLUTTER_RELEASES_JSON" "3.41.5")"
assert_eq "resolve stable" "sss111" "$(resolve_install_ref "stable")"
assert_eq "resolve beta version" "bbb111" "$(resolve_install_ref "3.47.0-0.3.pre-beta")"

if is_release_channel stable; then echo "PASS is_release_channel"; else echo "FAIL is_release_channel"; fail=1; fi
if is_git_channel master; then echo "PASS is_git_channel"; else echo "FAIL is_git_channel"; fail=1; fi

exit "$fail"
