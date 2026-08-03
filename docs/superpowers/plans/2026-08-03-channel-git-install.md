# Channel Git Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter SDK を共有 git mirror + clone でインストールし、stable/beta/dev/master/main を `mise ls-remote` / `mise upgrade` から使えるようにする。

**Architecture:** Bash + jq の asdf/mise プラグイン。releases JSON と `git ls-remote` で ref を解決し、`${ASDF_PLUGIN_PATH}/.git-cache` の bare mirror を `--reference --dissociate --progress` で clone する。チャネルは `list-aliases` で具体バージョン／commit に解決する。

**Tech Stack:** Bash, jq, git, curl

## Global Constraints

- 実装言語は Bash + jq（Dart/Go 等は使わない）
- ZIP 配布フォールバックは実装しない（git 一本化）
- `--dissociate` は必須（mirror 依存の shared clone は禁止）
- master/main の alias 先は full commit hash
- `FLUTTER_STORAGE_BASE_URL` / `FLUTTER_GIT_URL` / `FLUTTER_GIT_CACHE_PATH` をサポート
- `dynamic` 等の型制約は本リポジトリ（shell）では非該当
- 依存は `mise` 管理時 `mise exec --` 経由（本プラグイン本体の実行時はシステム git/curl/jq）

## File Map

| File | Responsibility |
| ------ | ---------------- |
| `bin/utils.sh` | URL・チャネル判定・JSON 取得・version→ref 解決・mirror パス |
| `bin/list-all` | チャネル名 + JSON versions を空白区切り出力 |
| `bin/list-aliases` | `channel concrete` 行を出力 |
| `bin/latest-stable` | 最新 stable を 1 行出力 |
| `bin/install` | mirror 確保 → 解決 → clone → checkout |
| `bin/jq-downloader` | 既存維持 |
| `tests/fixtures/releases_macos.json` | 縮小 JSON フィクスチャ |
| `tests/test_utils.sh` | utils の単体テスト |
| `tests/test_list.sh` | list-all / aliases / latest-stable のテスト |
| `README.md` | チャネル・環境変数の説明 |

---

### Task 1: utils 共通関数と単体テスト

**Files:**

- Create: `tests/fixtures/releases_macos.json`
- Create: `tests/test_utils.sh`
- Modify: `bin/utils.sh`
- Modify: `.gitignore`（`bin/jq` が未記載なら追加確認）

**Interfaces:**

- Produces:
  - `flutter_storage_base_url` → stdout string
  - `flutter_releases_url` → stdout URL
  - `flutter_git_url` → stdout URL
  - `flutter_git_cache_path` → stdout path（要 `ASDF_PLUGIN_PATH` または `FLUTTER_GIT_CACHE_PATH`）
  - `is_release_channel <name>` → exit 0 if stable|beta|dev
  - `is_git_channel <name>` → exit 0 if master|main
  - `fetch_releases_json` → stdout JSON（`FLUTTER_RELEASES_JSON` があればそれを優先、テスト用）
  - `version_name_for_hash <json> <hash>` → stdout `version-channel`（先頭の v 除去）
  - `hash_for_version <json> <version>` → stdout hash（`3.41.3` または `3.41.3-stable` 両対応）
  - `resolve_install_ref <version>` → stdout git ref（hash）。チャネル・version・未知 ref を解決

- [ ] **Step 1: フィクスチャ JSON を作成**

`tests/fixtures/releases_macos.json`:

```json
{
  "base_url": "https://storage.googleapis.com/flutter_infra_release/releases",
  "current_release": {
    "beta": "bbb111",
    "dev": "ddd111",
    "stable": "sss111"
  },
  "releases": [
    {
      "hash": "bbb111",
      "channel": "beta",
      "version": "3.47.0-0.3.pre",
      "dart_sdk_arch": "arm64",
      "archive": "beta/macos/flutter_macos_arm64_3.47.0-0.3.pre-beta.zip"
    },
    {
      "hash": "sss111",
      "channel": "stable",
      "version": "3.41.5",
      "dart_sdk_arch": "arm64",
      "archive": "stable/macos/flutter_macos_arm64_3.41.5-stable.zip"
    },
    {
      "hash": "ddd111",
      "channel": "dev",
      "version": "3.40.0-1.0.pre",
      "dart_sdk_arch": "arm64",
      "archive": "dev/macos/flutter_macos_arm64_3.40.0-1.0.pre-dev.zip"
    }
  ]
}
```

- [ ] **Step 2: 失敗するテストを書く**

`tests/test_utils.sh`:

```bash
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
```

- [ ] **Step 3: テストを実行して失敗を確認**

Run: `bash tests/test_utils.sh`
Expected: FAIL（`flutter_storage_base_url: command not found` 等）

- [ ] **Step 4: `bin/utils.sh` を実装**

置き換え内容:

```bash
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
  local json="$1" hash="$2"
  echo "${json}" | "${JQ_BIN}" -r --arg HASH "${hash}" '
    .releases[]
    | select(.hash == $HASH)
    | ((.version | ltrimstr("v")) + "-" + .channel)
  ' | head -n 1
}

hash_for_version() {
  local json="$1" version="$2"
  echo "${json}" | "${JQ_BIN}" -r --arg VERSION "${version}" '
    .releases[]
    | (.version | ltrimstr("v")) as $v
    | select(
        ($v + "-" + .channel) == $VERSION
        or $v == $VERSION
        or (.version + "-" + .channel) == $VERSION
      )
    | .hash
  ' | head -n 1
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
```

- [ ] **Step 5: テストを再実行して成功を確認**

Run: `bash tests/test_utils.sh`
Expected: 全て PASS、exit 0

- [ ] **Step 6: Commit**

```bash
git add bin/utils.sh tests/fixtures/releases_macos.json tests/test_utils.sh
git commit -m "$(cat <<'EOF'
feat: add shared utils for JSON/git version resolution

EOF
)"
```

---

### Task 2: list-all / list-aliases / latest-stable

**Files:**

- Modify: `bin/list-all`
- Create: `bin/list-aliases`
- Create: `bin/latest-stable`
- Create: `tests/test_list.sh`

**Interfaces:**

- Consumes: `fetch_releases_json`, `version_name_for_hash`, `flutter_git_url`, `is_*` from utils; `download_jq_if_not_exists` from jq-downloader
- Produces:
  - `list-all` stdout: `stable beta dev master main <versions...>`（空白区切り・1行可）
  - `list-aliases` stdout: 各行 `alias target`
  - `latest-stable` stdout: 1 行の `version-channel`

- [ ] **Step 1: 失敗するテストを書く**

`tests/test_list.sh`:

```bash
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
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `bash tests/test_list.sh`
Expected: FAIL（チャネル欠落、`latest-stable` / `list-aliases` 不在）

- [ ] **Step 3: `bin/list-all` を実装**

```bash
#!/usr/bin/env bash
set -euo pipefail

currentDir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=jq-downloader
source "${currentDir}/jq-downloader"
# shellcheck source=utils.sh
source "${currentDir}/utils.sh"

list_all() {
  local json versions
  json="$(fetch_releases_json)"
  versions="$(echo "${json}" | "${JQ_BIN}" -r '
    [.releases[] | ((.version | ltrimstr("v")) + "-" + .channel)]
    | unique
    | reverse
    | join(" ")
  ')"
  echo "stable beta dev master main ${versions}"
}

download_jq_if_not_exists
list_all
```

- [ ] **Step 4: `bin/latest-stable` を実装**

```bash
#!/usr/bin/env bash
set -euo pipefail

currentDir="$(cd "$(dirname "$0")" && pwd)"
source "${currentDir}/jq-downloader"
source "${currentDir}/utils.sh"

latest_stable() {
  local json hash
  json="$(fetch_releases_json)"
  hash="$(echo "${json}" | "${JQ_BIN}" -r '.current_release.stable // empty')"
  if [[ -z "${hash}" ]]; then
    echo "Cannot resolve latest stable" >&2
    exit 1
  fi
  version_name_for_hash "${json}" "${hash}"
}

download_jq_if_not_exists
latest_stable
```

- [ ] **Step 5: `bin/list-aliases` を実装**

```bash
#!/usr/bin/env bash
set -euo pipefail

currentDir="$(cd "$(dirname "$0")" && pwd)"
source "${currentDir}/jq-downloader"
source "${currentDir}/utils.sh"

list_aliases() {
  local json hash name

  json="$(fetch_releases_json)"
  for channel in stable beta dev; do
    hash="$(echo "${json}" | "${JQ_BIN}" -r --arg C "${channel}" '.current_release[$C] // empty')"
    if [[ -n "${hash}" && "${hash}" != "null" ]]; then
      name="$(version_name_for_hash "${json}" "${hash}")"
      echo "${channel} ${name}"
    fi
  done

  for channel in master main; do
    hash="$(git ls-remote --heads "$(flutter_git_url)" "refs/heads/${channel}" | awk '{print $1}')"
    if [[ -n "${hash}" ]]; then
      echo "${channel} ${hash}"
    fi
  done
}

download_jq_if_not_exists
list_aliases
```

- [ ] **Step 6: 実行権限を付与してテスト**

```bash
chmod +x bin/list-all bin/list-aliases bin/latest-stable
bash tests/test_list.sh
```

Expected: 全て PASS（master/main はネットワーク必要）

- [ ] **Step 7: Commit**

```bash
git add bin/list-all bin/list-aliases bin/latest-stable tests/test_list.sh
git commit -m "$(cat <<'EOF'
feat: expose channels via list-all, aliases, and latest-stable

EOF
)"
```

---

### Task 3: git mirror + install

**Files:**

- Modify: `bin/install`
- Create: `tests/test_install_resolve.sh`（フル Flutter clone は重いので、ref 解決と mirror パス／clone 引数のドライラン中心）

**Interfaces:**

- Consumes: `resolve_install_ref`, `flutter_git_url`, `flutter_git_cache_path`, `fetch_releases_json` 等
- Produces: `ensure_git_cache`（utils か install 内）、`install` が `ASDF_INSTALL_PATH` に Flutter SDK tree を配置

- [ ] **Step 1: `ensure_git_cache` を utils に追加し、小さいテストを追加**

`bin/utils.sh` に追加:

```bash
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
```

`tests/test_utils.sh` に追加（パスのみ）:

```bash
export FLUTTER_GIT_CACHE_PATH="/tmp/mise-flutter-test-cache"
assert_eq "cache path override" "/tmp/mise-flutter-test-cache" "$(flutter_git_cache_path)"
```

- [ ] **Step 2: install の ref 解決だけを検証するテスト**

`tests/test_install_resolve.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "${root}/bin/utils.sh"
export JQ_BIN="$(command -v jq)"
export FLUTTER_RELEASES_JSON
FLUTTER_RELEASES_JSON="$(cat "${root}/tests/fixtures/releases_macos.json")"
export ASDF_PLUGIN_PATH="${root}"

fail=0
ref="$(resolve_install_ref "beta")"
[[ "$ref" == "bbb111" ]] && echo "PASS beta→hash" || { echo "FAIL beta→hash $ref"; fail=1; }
ref="$(resolve_install_ref "3.41.5-stable")"
[[ "$ref" == "sss111" ]] && echo "PASS concrete→hash" || { echo "FAIL concrete $ref"; fail=1; }
exit "$fail"
```

Run: `bash tests/test_install_resolve.sh`
Expected: PASS

- [ ] **Step 3: `bin/install` を git 方式に書き換え**

```bash
#!/usr/bin/env bash
set -euo pipefail

currentDir="$(cd "$(dirname "$0")" && pwd)"
source "${currentDir}/jq-downloader"
source "${currentDir}/utils.sh"

cleanup_install_path() {
  if [[ -n "${ASDF_INSTALL_PATH:-}" && -d "${ASDF_INSTALL_PATH}" ]]; then
    rm -rf "${ASDF_INSTALL_PATH}"
  fi
}

install() {
  if [[ -z "${ASDF_INSTALL_VERSION:-}" || -z "${ASDF_INSTALL_PATH:-}" ]]; then
    echo "ASDF_INSTALL_VERSION and ASDF_INSTALL_PATH are required" >&2
    exit 1
  fi

  if [[ -z "${ASDF_PLUGIN_PATH:-}" ]]; then
    export ASDF_PLUGIN_PATH="$(cd "${currentDir}/.." && pwd)"
  fi

  local ref remote cache_path
  ref="$(resolve_install_ref "${ASDF_INSTALL_VERSION}")" || exit 1
  remote="$(flutter_git_url)"
  cache_path="$(flutter_git_cache_path)"

  echo "Installing Flutter ${ASDF_INSTALL_VERSION} (ref ${ref})" >&2

  ensure_git_cache

  trap cleanup_install_path ERR
  mkdir -p "$(dirname "${ASDF_INSTALL_PATH}")"
  rm -rf "${ASDF_INSTALL_PATH}"

  git clone \
    --reference "${cache_path}" \
    --dissociate \
    --progress \
    "${remote}" \
    "${ASDF_INSTALL_PATH}"

  git -C "${ASDF_INSTALL_PATH}" checkout --force "${ref}"
  trap - ERR

  echo "Flutter ${ASDF_INSTALL_VERSION} installed at ${ASDF_INSTALL_PATH}" >&2
}

download_jq_if_not_exists
install
```

- [ ] **Step 4: 手動スモーク（軽量）— mirror 作成と 1 バージョン**

注意: 初回は時間がかかる。可能なら浅い検証として、既存 mirror がある場合のみ実行。

```bash
export ASDF_PLUGIN_PATH="$(pwd)"
export ASDF_INSTALL_VERSION="3.41.5-stable"
export ASDF_INSTALL_PATH="/tmp/mise-flutter-smoke-stable"
export FLUTTER_GIT_CACHE_PATH="/tmp/mise-flutter-git-cache"
rm -rf "${ASDF_INSTALL_PATH}"
bin/install
test -x "${ASDF_INSTALL_PATH}/bin/flutter"
"${ASDF_INSTALL_PATH}/bin/flutter" --version
```

Expected: clone 進捗が表示され、`flutter --version` が成功する。

（時間が厳しければ Step 4 はレビュア判断でスキップ可。その場合でも Step 1–3 と utils テストは必須。）

- [ ] **Step 5: Commit**

```bash
git add bin/install bin/utils.sh tests/test_install_resolve.sh tests/test_utils.sh
git commit -m "$(cat <<'EOF'
feat: install Flutter via shared git mirror with progress

EOF
)"
```

---

### Task 4: README 更新と全体テスト

**Files:**

- Modify: `README.md`

- [ ] **Step 1: README を更新**

既存内容を維持しつつ、少なくとも次を追記:

```markdown
## Usage

```bash
# specific version
mise install flutter@3.41.5-stable

# channels (resolved to latest via releases JSON / git)
mise install flutter@stable
mise install flutter@beta
mise install flutter@master

mise ls-remote flutter
mise upgrade flutter
```

## Environment

| Variable | Default | Purpose |
| ---------- | --------- | --------- |
| `FLUTTER_STORAGE_BASE_URL` | `https://storage.googleapis.com` | releases JSON base |
| `FLUTTER_GIT_URL` | `https://github.com/flutter/flutter.git` | Flutter git remote |
| `FLUTTER_GIT_CACHE_PATH` | `$ASDF_PLUGIN_PATH/.git-cache` | shared bare mirror |

## Dependencies

- git
- curl
- jq（未導入時はプラグインが取得）

```

タイトルが asdf-flutter のままなら、mise-flutter 向けに冒頭を現状リポジトリ名に合わせて整理する（過度な書き換えはしない）。

- [ ] **Step 2: 全テスト実行**

```bash
bash tests/test_utils.sh
bash tests/test_list.sh
bash tests/test_install_resolve.sh
```

Expected: 全て exit 0

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: document channels, git install, and env vars

EOF
)"
```

---

## Spec Coverage Checklist

| Spec requirement | Task |
| ------------------ | ------ |
| git install + shared mirror + `--dissociate` + progress | Task 3 |
| stable/beta/dev/master/main installable | Task 1–3 |
| latest from JSON / git ls-remote | Task 1–2 |
| list-all includes channels | Task 2 |
| list-aliases for mise upgrade | Task 2 |
| latest-stable | Task 2 |
| Bash + jq | 全 Task |
| env vars | Task 1, 4 |
| README | Task 4 |
| ZIP 廃止 | Task 3（install 置換） |
| エラー時 cleanup | Task 3 (`trap cleanup`) |

## Self-Review Notes

- `resolve_install_ref` の未知文字列パスは git checkout に委ねる（存在しない ref は install で失敗）
- `list-aliases` の master/main はネットワーク依存；オフライン CI では失敗し得る。必要なら後続で stub を足す
- Windows は非対応（既存どおり Darwin/Linux）
