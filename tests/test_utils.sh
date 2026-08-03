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
assert_eq "stable name" "3.41.5-stable" "$(version_name_for_hash "$FLUTTER_RELEASES_JSON" "sss111" "stable")"
assert_eq "beta name with shared hash" "3.47.0-0.3.pre-beta" "$(version_name_for_hash "$FLUTTER_RELEASES_JSON" "shared111" "beta")"
assert_eq "dev name with shared hash" "3.40.0-1.0.pre-dev" "$(version_name_for_hash "$FLUTTER_RELEASES_JSON" "shared111" "dev")"
assert_eq "hash for 3.41.5-stable" "sss111" "$(hash_for_version "$FLUTTER_RELEASES_JSON" "3.41.5-stable")"
assert_eq "hash for 3.41.5" "sss111" "$(hash_for_version "$FLUTTER_RELEASES_JSON" "3.41.5")"
assert_eq "resolve stable" "sss111" "$(resolve_install_ref "stable")"
assert_eq "resolve beta version" "shared111" "$(resolve_install_ref "3.47.0-0.3.pre-beta")"
export FLUTTER_GIT_CACHE_PATH="/tmp/mise-flutter-test-cache"
assert_eq "cache path override" "/tmp/mise-flutter-test-cache" "$(flutter_git_cache_path)"

git_test_root="$(mktemp -d)"
git_bin_dir="${git_test_root}/bin"
git_log="${git_test_root}/git.log"
mkdir -p "${git_bin_dir}"
cat >"${git_bin_dir}/git" <<'FAKE_GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GIT_LOG}"
if [[ "$1" == "clone" && "$2" == "--bare" ]]; then
  mkdir -p "${@: -1}"
fi
FAKE_GIT
chmod +x "${git_bin_dir}/git"
export GIT_LOG="${git_log}"
export FLUTTER_GIT_URL="https://example.test/flutter.git"
export FLUTTER_GIT_CACHE_PATH="${git_test_root}/cache/flutter.git"
PATH="${git_bin_dir}:${PATH}" ensure_git_cache
assert_eq "ensure_git_cache clones bare mirror" "clone --bare --progress https://example.test/flutter.git ${git_test_root}/cache/flutter.git" "$(<"${git_log}")"
PATH="${git_bin_dir}:${PATH}" ensure_git_cache
last_git_log_line=""
while IFS= read -r line; do
  last_git_log_line="${line}"
done <"${git_log}"
assert_eq "ensure_git_cache fetches existing mirror" "--git-dir=${git_test_root}/cache/flutter.git fetch --progress --tags origin +refs/heads/*:refs/heads/*" "${last_git_log_line}"

if is_release_channel stable; then echo "PASS is_release_channel"; else echo "FAIL is_release_channel"; fail=1; fi
if is_git_channel master; then echo "PASS is_git_channel"; else echo "FAIL is_git_channel"; fail=1; fi

exit "$fail"
