---
name: publish-marketplace
description: Publish a new OmaXerahs version to the Omarchy plugin marketplace (plugins.omarchy.org). Use when asked to release, publish, or update the marketplace listing.
---

# Publish OmaXerahs to the Omarchy marketplace

OmaXerahs is listed at https://plugins.omarchy.org/plugin.html?id=io.github.sharex.omaxerahs. The listing comes from `registry.json` in [omacom/omarchy-plugin-marketplace](https://github.com/omacom/omarchy-plugin-marketplace) and records one exact commit of this repository (`listingValidatedCommit`). Omarchy itself installs and updates plugins from the current `main` (`omarchy plugin add|update`), so pushing to `main` reaches users; the marketplace update makes the listing show that commit as verified instead of "Update unverified".

## Steps

1. Prepare the release on `main`:
   - Bump `version` in `manifest.json` when the plugin changed.
   - Date the changelog entry: `## vX.Y.Z — YYYY-MM-DD (summary)`. The script refuses an entry still marked "in progress".
   - Run `bash tests/model-test.sh`, `bash tests/run-bounded-test.sh` and `omarchy plugin validate "$PWD"`.
   - Commit and push. Make every change before requesting publication: any later commit on `main` shows as "Update unverified" again.
2. Dry run, then publish:

   ```bash
   .ai/skills/publish-marketplace/scripts/publish-marketplace.sh
   .ai/skills/publish-marketplace/scripts/publish-marketplace.sh --yes
   ```

   The script checks that `main` is clean and pushed, the changelog is dated, the tests and manifest validation pass, and the marketplace does not already list `HEAD`. With `--yes` it opens a **Plugin verification** issue with the action *Verify and publish a newer upstream commit* and the full `HEAD` SHA. If an open `[Verify]` request for this plugin already exists for an older commit, it edits that issue to the new SHA instead of opening a duplicate (editing re-runs validation). Add `--sync-installed` to also copy the repository to `~/.config/omarchy/plugins/io.github.sharex.omaxerahs/`.

   Opening or editing the issue posts publicly on the marketplace repository. Confirm with the plugin owner before running `--yes`.
3. Follow the issue. The marketplace bot posts compatibility validation and an **Automated Security Baseline** result (`passed`, `review-required`, or `needs-fixes`). A marketplace maintainer then applies `approved-and-verified`, which promotes the commit. Until then the old snapshot stays listed. Fix `needs-fixes` findings in a new commit and re-run the script, which updates the same issue.

## Rules

- Leave the *standard installation* box unchecked. OmaXerahs needs XerahS and the `omaxerahs` CLI installed first, so the listing keeps its manual-setup note.
- Keep the plugin ID `io.github.sharex.omaxerahs`; marketplace IDs are permanent.
- Spawn helpers only through `run-bounded`. The marketplace review rejected an earlier version for an unbounded `StdioCollector`.
- Do not add `git fetch`, `git clone` or `git pull` to any script in this repository, including tooling. The security baseline flags a remote Git source followed by executing repository code as `remote-git-execution-unpinned` and asks for manual review (it did for 48ef682). Read remote commit IDs with `git ls-remote` instead.
- A first listing of a new plugin uses the submission flow in the marketplace `SUBMISSION.md`, not this script.
