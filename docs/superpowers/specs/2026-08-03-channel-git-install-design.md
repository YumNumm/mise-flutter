# mise-flutter: チャネル対応・git インストール設計

日付: 2026-08-03
ステータス: 承認済み（実装前）

## 背景

現行の asdf/mise Flutter プラグインは Google Storage の ZIP を取得する方式で、`stable` / `beta` / `dev` の一部は JSON 経由で動くが次が不足している。

- `master` / `main` は `releases_*.json` に存在せずインストールできない
- チャネル名が `list-all` に出ないため `mise ls-remote` / `mise upgrade` と相性が悪い
- ダウンロード進捗が弱い

FVM は全バージョンを git clone し、共有 bare mirror でオブジェクト重複を抑えている。本プラグインもそれに寄せる。

## ゴール

1. `stable` / `beta` / `dev` / `master` / `main` をインストールできる
2. 最新版は JSON（および master/main は `git ls-remote`）から都度解決する
3. `mise ls-remote flutter` でチャネルと具体バージョンが見える
4. `flutter = "beta"` 等でも `mise upgrade` が追従する
5. clone / fetch 時に進捗を表示する
6. 共有 git mirror でディスク重複を抑える
7. 実装言語は Bash + jq

## 非ゴール

- FVM 互換のプロジェクトローカル `.fvm` 管理
- fork（カスタム Flutter remote 以外の複数 fork 定義 UI）
- ZIP 配布へのフォールバック維持（git 一本化）

## アーキテクチャ

```
mise ls-remote  → bin/list-all
mise upgrade    → aliases 解決 → 具体 ref が変われば install
mise install    → bin/install
                     │
                     ├─ ensure shared bare mirror (.git-cache)
                     ├─ resolve version → git ref (hash / tag / branch)
                     ├─ git clone --reference <mirror> --progress
                     └─ checkout target ref
```

### バージョン解決

| 入力 | 解決方法 | インストール ref |
| ------ | ---------- | ------------------ |
| `stable` / `beta` / `dev` | `releases_*.json` の `current_release.<channel>` → 対応 release | その hash（または `version-channel`） |
| `master` / `main` | `git ls-remote` で tip commit | その commit |
| `3.41.3` / `3.41.3-stable` など | JSON の releases から version(+channel) 照合 | その hash |
| 不明な文字列 | git ref として扱う（commit / tag / branch） | 指定どおり |

OS ごとの JSON:

- macOS: `releases_macos.json`
- Linux: `releases_linux.json`

ベース URL は既存どおり `FLUTTER_STORAGE_BASE_URL`（デフォルト `https://storage.googleapis.com`）。

### mise update / ls-remote 連携

mise は「同じバージョン名」では upgrade しない。チャネルは **エイリアス → 具体 ref** に解決する。

- `bin/list-all`
  - 先頭にチャネル名を必ず含める: `stable beta dev master main`
  - 続けて JSON の全 `version-channel`（既存互換）
- `bin/list-aliases`
  - 実行時点の最新を出力（例）:
    - `stable 3.41.5-stable`
    - `beta 3.47.0-0.3.pre-beta`
    - `dev <version>-dev`
    - `master <full-commit>`
    - `main <full-commit>`
  - commit は full hash（短いと衝突・曖昧さの余地がある）
- `bin/latest-stable`
  - JSON の最新 stable を 1 行で返す（例: `3.41.5-stable`）

これで `mise.toml` に `flutter = "beta"` があっても、エイリアス先が変われば `mise upgrade` が新しい SDK を入れる。

`bin/install` は次の両方を受け付ける。

- mise がエイリアス解決した具体版（例: `3.47.0-0.3.pre-beta`）
- チャネル名そのもの（例: `beta` / `master`）— asdf 直接利用やエイリアス未対応時向けに、install 内でも同じ解決ロジックを通す

### 共有 git mirror

- パス: `${ASDF_PLUGIN_PATH}/.git-cache`
  - 上書き: `FLUTTER_GIT_CACHE_PATH`
- remote: `https://github.com/flutter/flutter.git`
  - 上書き: `FLUTTER_GIT_URL`
- 初回: `git clone --bare --progress`
- 以降: `git fetch --progress` で更新
- 各バージョン install:
  `git clone --reference <mirror> --dissociate --progress <url> <ASDF_INSTALL_PATH>`
  のあと、対象 ref を checkout
  - `--dissociate` は必須。mirror 削除後も各 install が単独で使える（ディスクは増えるが安全性優先）。
    オブジェクトは clone 時に mirror からローカルコピーされるため、フルネットワーク再取得より速い。
  - `--shared` や dissociate なしは mirror 寿命に依存するため採用しない。

※ FVM は local mirror から clone する方式。本設計は `--reference` + `--dissociate` で「速い初回コピー」と「install 独立性」を両立する。

### 進捗表示

- mirror の clone/fetch: `git ... --progress`
- バージョン clone: `git clone --progress`
- stderr を隠さない（mise/asdf がキャプチャしても進捗が出るよう、冗長すぎるログは出さない）

### 依存

- `git`（必須）
- `jq`（既存の `jq-downloader` で不足時に取得）
- `curl`（JSON / jq 取得）

## ファイル構成

```
bin/
  install          # mirror確保 → 解決 → clone → checkout
  list-all         # channels + JSON versions
  list-aliases     # channel → concrete ref
  latest-stable    # JSON current stable
  utils.sh         # OS, URL, JSON fetch, channel helpers
  jq-downloader    # 既存維持
```

README にチャネル利用例と環境変数を追記する。

## エラー処理

- JSON 取得失敗 / 該当 version なし → メッセージを出して exit 1
- git / ref 不存在 → メッセージを出して exit 1
- install 途中失敗 → `ASDF_INSTALL_PATH` の不完全内容を可能な範囲で削除
- mirror 破損時 → エラーを表示し、必要なら mirror 再構築を促す（自動削除は慎重に。明確に corrupt と分かる場合のみ再 clone）

## テスト観点

1. `list-all` に `stable` / `beta` / `master` が含まれる
2. `list-aliases` の stable/beta が JSON `current_release` と一致する
3. `latest-stable` が JSON 最新と一致する
4. `install` が `beta`（エイリアス解決後の具体版）で成功する
5. `install` が `master` 相当の commit で成功する
6. 2 つ目のバージョン install が mirror 再利用でネットワークより軽いこと（目視/時間）
7. clone 中に進捗が出ること

## 環境変数まとめ

| 変数 | デフォルト | 用途 |
| ------ | ------------ | ------ |
| `FLUTTER_STORAGE_BASE_URL` | `https://storage.googleapis.com` | releases JSON |
| `FLUTTER_GIT_URL` | `https://github.com/flutter/flutter.git` | SDK remote |
| `FLUTTER_GIT_CACHE_PATH` | `${ASDF_PLUGIN_PATH}/.git-cache` | 共有 bare mirror |

## 決定事項（ブレインストーム結果）

- インストール方式: FVM 準拠の git（共有 mirror 付き）— ZIP はやめる
- 言語: Bash + jq
- チャネルと upgrade: `list-aliases` で具体 ref に解決
- master: JSON ではなく `git ls-remote`
