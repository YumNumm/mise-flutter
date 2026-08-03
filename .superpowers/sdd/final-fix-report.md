## 2026-08-03 final whole-branch review fixes

### Fix details

- Fixed `bin/list-all` so release versions preserve the JSON release order after `reverse`, using adjacent deduplication instead of `unique | reverse`. This keeps the channel prefix `stable beta dev master main` unchanged and avoids lexicographic descending ordering.
- Changed `version_name_for_hash` to accept `version_name_for_hash <json> <hash> <channel>` and filter by both hash and channel, preventing shared release hashes from being labeled as the wrong channel.
- Updated `bin/list-aliases`, `bin/latest-stable`, and tests to pass the channel argument.
- Replaced touched `head -n 1` usage in `version_name_for_hash` and `hash_for_version` with jq `limit(1; ...)`.
- Updated the macOS release fixture to include a shared beta/dev hash and an adjacent stable arch duplicate, covering alias labeling and list dedup/order behavior.

### Test evidence

- RED check before implementation:
  - `bash tests/test_utils.sh; bash tests/test_list.sh`
  - Failed as expected for shared-hash `dev` labeling, `list-all` order, and `alias dev`.
- Final verification:
  - `bash tests/test_utils.sh`
  - `bash tests/test_list.sh`
  - `bash tests/test_install_resolve.sh`
  - `bash tests/test_install_dry_run.sh`
  - Result: all passed.
