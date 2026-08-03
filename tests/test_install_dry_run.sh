#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_root="$(mktemp -d)"
git_bin_dir="${tmp_root}/bin"
git_log="${tmp_root}/git.log"
install_path="${tmp_root}/install/flutter"
cache_path="${tmp_root}/cache/flutter.git"
remote="https://example.test/flutter.git"
mkdir -p "${git_bin_dir}"

cat >"${git_bin_dir}/git" <<'FAKE_GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GIT_LOG}"
if [[ "$1" == "clone" && "$2" == "--bare" ]]; then
  mkdir -p "${@: -1}"
elif [[ "$1" == "clone" && "$2" == "--reference" ]]; then
  mkdir -p "${@: -1}"
elif [[ "$1" == "-C" && "$3" == "checkout" ]]; then
  exit 0
fi
FAKE_GIT
chmod +x "${git_bin_dir}/git"

export PATH="${git_bin_dir}:${PATH}"
export GIT_LOG="${git_log}"
export ASDF_PLUGIN_PATH="${root}"
export ASDF_INSTALL_VERSION="3.41.5-stable"
export ASDF_INSTALL_PATH="${install_path}"
export FLUTTER_GIT_CACHE_PATH="${cache_path}"
export FLUTTER_GIT_URL="${remote}"
export FLUTTER_RELEASES_JSON
FLUTTER_RELEASES_JSON="$(<"${root}/tests/fixtures/releases_macos.json")"

bash "${root}/bin/install"

command_log="$(<"${git_log}")"
fail=0
if [[ "${command_log}" == *"clone --bare --progress ${remote} ${cache_path}"* ]]; then
  echo "PASS install creates bare mirror"
else
  echo "FAIL install creates bare mirror"
  fail=1
fi
if [[ "${command_log}" == *"clone --reference ${cache_path} --dissociate --progress ${remote} ${install_path}"* ]]; then
  echo "PASS install uses reference dissociate progress"
else
  echo "FAIL install uses reference dissociate progress"
  fail=1
fi
if [[ "${command_log}" == *"-C ${install_path} checkout --force sss111"* ]]; then
  echo "PASS install checks out resolved ref"
else
  echo "FAIL install checks out resolved ref"
  fail=1
fi
exit "${fail}"
