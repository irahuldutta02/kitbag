#!/usr/bin/env bash
# Builds Kitbag and publishes a GitHub release that the in-app updater can find.
#
#   scripts/release.sh patch|minor|major|X.Y.Z  [--notes "text" | --notes-file FILE]
#                                               [--dry-run] [--no-publish] [--allow-dirty] [--yes]
#   Before pushing to GitHub it always asks for a yes (--yes skips the question, for automation).
#   Without --notes/--notes-file it asks: automatic (from the git commits) or modifiable (opens your editor).
#
# What it does, in order:
#   1. works out the new version and checks it is newer than the current one
#   2. writes it into App/Resources/Info.plist (version and build number)
#   3. runs scripts/build.sh and names the result release/Kitbag-<version>.dmg
#   4. writes release/Kitbag-<version>.dmg.sha256 (the updater refuses a download without a checksum)
#   5. commits the version change, tags v<version>
#   6. unless --no-publish: pushes the commit and tag, then creates the GitHub release with both files
#      (uses `gh` if installed, otherwise the GITHUB_TOKEN environment variable, otherwise it tells you
#      exactly what to click)
#
# --dry-run changes nothing: it only prints what would happen.
# Sign with the same certificate every time (scripts/setup-signing.sh), or macOS will ask each user
# for Accessibility / Screen Recording / Keychain access again after every update.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST=App/Resources/Info.plist
REPO=$(/usr/libexec/PlistBuddy -c 'Print :KitbagUpdateRepo' "$PLIST" 2>/dev/null || echo "irahuldutta02/kitbag")

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

BUMP="" NOTES="" NOTES_FILE="" DRY=0 PUBLISH=1 DIRTY=0 YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) NOTES="${2:?--notes needs text}"; shift 2 ;;
    --notes-file) NOTES_FILE="${2:?--notes-file needs a path}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-publish) PUBLISH=0; shift ;;
    --allow-dirty) DIRTY=1; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [[ -z "$BUMP" ]] || die "give one version"; BUMP="$1"; shift ;;
  esac
done
[[ -n "$BUMP" ]] || die "usage: scripts/release.sh patch|minor|major|X.Y.Z [options]"

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
IFS=. read -r MA MI PA <<<"$CURRENT"; MA=${MA:-0}; MI=${MI:-0}; PA=${PA:-0}
case "$BUMP" in
  patch) VERSION="$MA.$MI.$((PA + 1))" ;;
  minor) VERSION="$MA.$((MI + 1)).0" ;;
  major) VERSION="$((MA + 1)).0.0" ;;
  *) [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3 (got '$BUMP')"; VERSION="$BUMP" ;;
esac
# Newer than the current one?
newest=$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
[[ "$VERSION" != "$CURRENT" && "$newest" == "$VERSION" ]] || die "$VERSION is not newer than the current version $CURRENT"
TAG="v$VERSION"
DMG="release/Kitbag-$VERSION.dmg"
SUM="$DMG.sha256"

if [[ $DRY == 0 ]]; then
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
  if [[ $DIRTY == 0 && -n "$(git status --porcelain --untracked-files=no -- . ':!release')" ]]; then
    die "there are uncommitted changes. Commit them first (a release should be built from committed code), or pass --allow-dirty."
  fi
fi

# Release notes: given text, a file, or the commit subjects since the previous tag. With none of
# those given, and a terminal to ask on, you choose between the automatic notes and writing your own.
auto_notes() {
  local prev range notes
  prev=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
  range=${prev:+$prev..HEAD}
  notes=$(git log ${range:-} --no-merges --pretty='- %s' -n 30 2>/dev/null || true)
  [[ -n "$notes" ]] && echo "$notes" || echo "First release."
}
if [[ -n "$NOTES_FILE" ]]; then NOTES=$(cat "$NOTES_FILE")
elif [[ -z "$NOTES" ]]; then
  NOTES=$(auto_notes)
  if [[ -t 0 && -t 1 ]]; then
    echo "Release notes from the git commits:"; echo "$NOTES" | sed 's/^/  /'; echo
    echo "How should the release notes be written?"
    echo "  1) Automatic: use the commit messages above"
    echo "  2) Modifiable: edit them (or write your own)"
    while true; do
      read -r -p "Choose 1 or 2 [1]: " CHOICE
      case "${CHOICE:-1}" in
        1|a|A) break ;;
        2|m|M)
          TMP=$(mktemp -t kitbag-notes)
          printf '%s\n' "$NOTES" > "$TMP"
          echo "Opening ${VISUAL:-${EDITOR:-nano}}: edit the notes, save and close it."
          ${VISUAL:-${EDITOR:-nano}} "$TMP" || true
          EDITED=$(cat "$TMP"); rm -f "$TMP"
          if [[ -n "${EDITED//[[:space:]]/}" ]]; then NOTES="$EDITED"; else echo "The notes were empty, so the automatic ones are used."; fi
          break ;;
        *) echo "Please type 1 or 2." ;;
      esac
    done
  fi
fi

log "Kitbag $CURRENT -> $VERSION (tag $TAG, repo $REPO)"
echo "Release notes:"; echo "$NOTES" | sed 's/^/  /'
if [[ $DRY == 1 ]]; then
  log "Dry run: nothing was changed. Would build $DMG, write $SUM, commit, tag, and $([[ $PUBLISH == 1 ]] && echo publish || echo 'stop before publishing')."
  exit 0
fi

log "Setting version $VERSION (build $((BUILD + 1)))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
undo_version() { git checkout -- "$PLIST" 2>/dev/null || true; }
trap 'undo_version; die "release failed; the version change was reverted"' ERR

log "Building"
scripts/build.sh
BUILT=$(ls -t release/*.dmg | head -1)
[[ -f "$BUILT" ]] || die "no disk image was produced"
rm -f "$DMG" "$SUM"
mv "$BUILT" "$DMG"
HASH=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "$HASH  $(basename "$DMG")" > "$SUM"
log "Checksum $HASH"

log "Committing and tagging $TAG"
git add "$PLIST"
git commit -m "release: v$VERSION"
git tag -a "$TAG" -m "Kitbag $VERSION"
trap - ERR

if [[ $PUBLISH == 0 ]]; then
  log "Stopped before publishing. Files are in release/. To publish: git push origin HEAD $TAG, then create the release for $TAG and attach $DMG and $SUM."
  exit 0
fi

if [[ $YES == 0 ]]; then
  if [[ -t 0 && -t 1 ]]; then
    echo
    echo "Ready to publish Kitbag $VERSION:"
    echo "  - push the commit and tag $TAG to $REPO"
    echo "  - create the GitHub release with $DMG and $SUM"
    echo "Release notes:"; echo "$NOTES" | sed 's/^/  /'
    read -r -p "Publish now? [y/N]: " OK
    [[ "$OK" =~ ^[Yy]([Ee][Ss])?$ ]] || {
      log "Not published. The build, commit and tag are kept locally. To publish later: git push origin HEAD $TAG, then create the release for $TAG and attach $DMG and $SUM."
      exit 0
    }
  else
    log "Not published: no terminal to ask for confirmation (pass --yes to publish without asking). Files are in release/."
    exit 0
  fi
fi

log "Pushing"
git push origin HEAD "$TAG"

log "Creating the GitHub release"
if command -v gh >/dev/null 2>&1; then
  gh release create "$TAG" "$DMG" "$SUM" --repo "$REPO" --title "Kitbag $VERSION" --notes "$NOTES"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  api() { curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }
  BODY=$(python3 -c 'import json,sys; print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[2],"body":sys.argv[3]}))' "$TAG" "Kitbag $VERSION" "$NOTES")
  ID=$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  for f in "$DMG" "$SUM"; do
    api -X POST -H "Content-Type: application/octet-stream" --data-binary @"$f" \
      "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=$(basename "$f")" >/dev/null
  done
else
  echo "Neither 'gh' nor GITHUB_TOKEN is available, so finish this on GitHub:"
  echo "  1. open https://github.com/$REPO/releases/new?tag=$TAG"
  echo "  2. title: Kitbag $VERSION, paste the notes above"
  echo "  3. attach $DMG and $SUM"
  echo "  4. press Publish release"
  exit 0
fi
log "Published: https://github.com/$REPO/releases/tag/$TAG"
