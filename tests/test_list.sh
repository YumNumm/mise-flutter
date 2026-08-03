#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export FLUTTER_RELEASES_JSON
FLUTTER_RELEASES_JSON="$(cat "${root}/tests/fixtures/releases_macos.json")"
export ASDF_PLUGIN_PATH="${root}"
# Avoid real git ls-remote in CI-like unit test: stub via PATH wrapper if needed.
# For aliases master/main, allow network OR skip if GIT_TERMINAL_PROMPT=0 and stub.
# Prefer stubbing resolve by exporting a fake git in PATH for this test only when offline.

fail=0
out="$("${root}/bin/list-all")"
for ch in stable beta dev master main; do
  if [[ " ${out} " == *" ${ch} "* ]]; then
    echo "PASS list-all has ${ch}"
  else
    echo "FAIL list-all missing ${ch}"
    fail=1
  fi
done
if [[ " ${out} " == *" 3.41.5-stable "* ]]; then
  echo "PASS list-all has concrete version"
else
  echo "FAIL list-all missing 3.41.5-stable"
  fail=1
fi

latest="$("${root}/bin/latest-stable")"
if [[ "${latest}" == "3.41.5-stable" ]]; then
  echo "PASS latest-stable"
else
  echo "FAIL latest-stable: ${latest}"
  fail=1
fi

aliases="$("${root}/bin/list-aliases")"
echo "${aliases}" | grep -qx 'stable 3.41.5-stable' && echo "PASS alias stable" || { echo "FAIL alias stable"; fail=1; }
echo "${aliases}" | grep -qx 'beta 3.47.0-0.3.pre-beta' && echo "PASS alias beta" || { echo "FAIL alias beta"; fail=1; }
echo "${aliases}" | grep -qx 'dev 3.40.0-1.0.pre-dev' && echo "PASS alias dev" || { echo "FAIL alias dev"; fail=1; }
# master/main require git; assert lines exist and second field looks like 40-char hex
echo "${aliases}" | awk '/^master /{print $2}' | grep -Eq '^[0-9a-f]{40}$' && echo "PASS alias master" || { echo "FAIL alias master"; fail=1; }
echo "${aliases}" | awk '/^main /{print $2}' | grep -Eq '^[0-9a-f]{40}$' && echo "PASS alias main" || { echo "FAIL alias main"; fail=1; }

exit "$fail"
