#!/usr/bin/env bash
# Publish the current origin/main commit of this plugin to the Omarchy plugin marketplace
# (https://plugins.omarchy.org) by opening a "Plugin verification" issue on
# omacom/omarchy-plugin-marketplace with the action "Verify and publish a newer upstream commit".
#
# Usage: publish-marketplace.sh [--yes] [--sync-installed]
#   (no flags)        run every check and print the issue that would be opened
#   --yes             open the issue (or report an existing open one for the same commit)
#   --sync-installed  also copy the repo to ~/.config/omarchy/plugins/<id>/ after the checks
set -euo pipefail

MARKETPLACE_REPO="omacom/omarchy-plugin-marketplace"
CREATE=0
SYNC=0
for arg in "$@"; do
  case "$arg" in
    --yes) CREATE=1 ;;
    --sync-installed) SYNC=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$ROOT"

fail() { echo "Error: $*" >&2; exit 1; }

command -v gh >/dev/null || fail "gh (GitHub CLI) is required"
command -v jq >/dev/null || fail "jq is required"

PLUGIN_ID="$(jq -r .id manifest.json)"
PLUGIN_NAME="$(jq -r .name manifest.json)"
VERSION="$(jq -r .version manifest.json)"
REPO_URL="$(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')"
[[ "$REPO_URL" =~ ^https://github.com/[^/]+/[^/]+$ ]] || fail "origin is not a GitHub repository root: $REPO_URL"

echo "Plugin: $PLUGIN_NAME ($PLUGIN_ID) v$VERSION"
echo "Repository: $REPO_URL"

# 1. Working tree is clean, on main, and identical to origin/main.
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "check out main first"
[[ -z "$(git status --porcelain)" ]] || fail "working tree has uncommitted changes"
git fetch -q origin main
HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main)"
[[ "$HEAD_SHA" == "$REMOTE_SHA" ]] || fail "main ($HEAD_SHA) differs from origin/main ($REMOTE_SHA); push or pull first"

# 2. The changelog has a dated entry for the manifest version.
grep -qE "^## v${VERSION//./\\.} — [0-9]{4}-[0-9]{2}-[0-9]{2}" CHANGELOG.md \
  || fail "CHANGELOG.md has no dated '## v$VERSION — YYYY-MM-DD' entry (is it still 'in progress'?)"

# 3. Tests and manifest validation.
bash tests/model-test.sh >/dev/null || fail "tests/model-test.sh failed"
bash tests/run-bounded-test.sh >/dev/null || fail "tests/run-bounded-test.sh failed"
if command -v omarchy >/dev/null; then
  omarchy plugin validate "$ROOT" || fail "omarchy plugin validate failed"
else
  echo "Warning: omarchy is not installed; skipped 'omarchy plugin validate'." >&2
fi
echo "Checks passed for $HEAD_SHA"

# 4. Already listed at this commit? Already requested?
LISTED_SHA="$(gh api "repos/$MARKETPLACE_REPO/contents/registry.json" -H "Accept: application/vnd.github.raw" \
  | jq -r --arg repo "$REPO_URL" '.sources[] | select((.repo|ascii_downcase) == ($repo|ascii_downcase)) | .listingValidatedCommit')"
[[ -n "$LISTED_SHA" ]] || fail "$REPO_URL is not listed yet; a first listing uses the submission form, not this script (see SKILL.md)"
echo "Marketplace snapshot: $LISTED_SHA"
if [[ "$LISTED_SHA" == "$HEAD_SHA" ]]; then
  echo "The marketplace already lists this commit. Nothing to publish."
  exit 0
fi

# An open request for this plugin: report it when it already targets HEAD, otherwise update
# its target commit (the marketplace asks for edits, not duplicate issues).
OPEN_JSON="$(gh issue list --repo "$MARKETPLACE_REPO" --state open --search "$PLUGIN_ID in:body" \
  --json number,title,body,url --jq '[.[] | select(.title | startswith("[Verify]"))][0] // empty')"
OPEN_URL=""
[[ -n "$OPEN_JSON" ]] && OPEN_URL="$(jq -r '.url // empty' <<<"$OPEN_JSON")"
if [[ -n "$OPEN_URL" ]] && jq -e --arg sha "$HEAD_SHA" '.body | contains($sha)' <<<"$OPEN_JSON" >/dev/null; then
  echo "An open verification request for this commit already exists: $OPEN_URL"
  exit 0
fi

if (( SYNC )); then
  INSTALLED="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
  mkdir -p "$INSTALLED"
  rsync -a --exclude=.git --exclude=.ai "$ROOT/" "$INSTALLED/"
  echo "Synced installed copy: $INSTALLED"
fi

BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT
cat > "$BODY" <<EOF
### Verification action

Verify and publish a newer upstream commit

### Plugin ID

$PLUGIN_ID

### Repository URL

$REPO_URL

### Target commit

$HEAD_SHA

### Verification acknowledgment

- [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.

### Standard installation acknowledgment

- [ ] I confirm that this listed root plugin supports the standard Omarchy installation path and does not require manual setup.
EOF
TITLE="[Verify]: $PLUGIN_NAME — newer upstream commit (v$VERSION)"

if [[ -n "$OPEN_URL" ]]; then
  if (( ! CREATE )); then
    echo
    echo "Dry run. Would point the open request $OPEN_URL at $HEAD_SHA:"
    cat "$BODY"
    echo
    echo "Re-run with --yes to update it."
    exit 0
  fi
  gh issue edit "$OPEN_URL" --repo "$MARKETPLACE_REPO" --title "$TITLE" --body-file "$BODY" >/dev/null
  echo "Updated $OPEN_URL to target $HEAD_SHA (validation runs again)."
  echo "Listing: https://plugins.omarchy.org/plugin.html?id=$PLUGIN_ID"
  exit 0
fi

if (( ! CREATE )); then
  echo
  echo "Dry run. Would open on $MARKETPLACE_REPO:"
  echo "Title: $TITLE"
  cat "$BODY"
  echo
  echo "Re-run with --yes to open it."
  exit 0
fi

URL="$(gh issue create --repo "$MARKETPLACE_REPO" --title "$TITLE" --body-file "$BODY")"
echo "Opened: $URL"
echo "Listing: https://plugins.omarchy.org/plugin.html?id=$PLUGIN_ID"
