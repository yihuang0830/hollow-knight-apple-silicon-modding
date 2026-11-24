#!/bin/bash
# hkmod.sh: one-stop installer for the Hollow Knight Modding API on macOS
# (Hollow Knight 1.5.12620 / Unity 6), running natively on Apple Silicon.
#
#   ./hkmod.sh doctor                  check that this Mac has everything needed
#   ./hkmod.sh install [MOD...]        backup + build/install the Modding API (+ optional mods)
#   ./hkmod.sh install-mod MOD...      install mods (and their dependencies) from the official ModLinks
#   ./hkmod.sh remove-mod MOD...       remove installed mods (moved to ~/HKMod/replaced/)
#   ./hkmod.sh list-mods [FILTER]      list mods available in ModLinks
#   ./hkmod.sh status                  show what is installed and which backups exist
#   ./hkmod.sh backup                  back up the save folder and the game's Managed folder
#   ./hkmod.sh restore game [DIR]      back to the vanilla game (removes API + mods; save untouched)
#   ./hkmod.sh restore save [DIR] [--yes]   put a backed-up save back (progress after it is lost!)
#   ./hkmod.sh restore all [DIR] [--yes]    both of the above
#   ./hkmod.sh launch [--rosetta]      start the game through Steam
#   ./hkmod.sh clean                   delete build files and download cache (backups are kept)
#
# Nothing is overwritten without a copy: install backs up first, and restores and remove-mod move
# files to ~/HKMod/pre-restore-*/ or ~/HKMod/replaced/. The save folder is only written by
# "restore save" and "restore all".
set -euo pipefail

HKMOD_VERSION="0.3.1"
STEAM_APPID=367520
EXPECTED_GAME_VERSION="1.5.12620"
# SHA-256 of the unmodified 1.5.12620 files that the Modding API replaces (used to recognise vanilla)
VANILLA_SHA_ASSEMBLY="7ea3415ccc5c1b7c7101d958043d564de19d4be2cd37283ced5d63770f2cfd78"
VANILLA_SHA_LOCALIZATION="a98c28d352cbcdd9d291fd998ece9a42fba6811e52a79e4ba118a9cc41a386cc"

# ---- what gets built (pinned for reproducibility; override with environment variables) ----
# Modding API: hk-modding/api PR #164 (Unity 6 port) plus the fixes from SFGrenade/api#6.
API_REPO="${HKMOD_API_REPO:-https://github.com/yihuang0830/api.git}"
API_REF="${HKMOD_API_REF:-13eee977fd9da125df5b51458a2f846b497e9d84}"
# Benchwarp 3.2.6.1 source; patched for 1.5.12620 with patches/benchwarp/*.patch
BENCHWARP_REPO="${HKMOD_BENCHWARP_REPO:-https://github.com/homothetyhk/HollowKnight.BenchwarpMod.git}"
BENCHWARP_REF="${HKMOD_BENCHWARP_REF:-1ac5a3cf2d54f534c1cef46c0534e63b22a3c880}"
MODLINKS_URL="${HKMOD_MODLINKS_URL:-https://raw.githubusercontent.com/hk-modding/modlinks/main/ModLinks.xml}"

# ---- locations (override with environment variables) ----
GAME_APP="${HKMOD_GAME_APP:-$HOME/Library/Application Support/Steam/steamapps/common/Hollow Knight/hollow_knight.app}"
SAVE_DIR="${HKMOD_SAVE_DIR:-$HOME/Library/Application Support/unity.Team Cherry.Hollow Knight}"
HKMOD_HOME="${HKMOD_HOME:-$HOME/HKMod}"
case "$HKMOD_HOME" in /*) ;; *) HKMOD_HOME="$PWD/$HKMOD_HOME" ;; esac
strip_slash() { local p="$1"; while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done; printf '%s' "$p"; }
GAME_APP="$(strip_slash "$GAME_APP")"; SAVE_DIR="$(strip_slash "$SAVE_DIR")"; HKMOD_HOME="$(strip_slash "$HKMOD_HOME")"

MANAGED="$GAME_APP/Contents/Resources/Data/Managed"
MODS="$MANAGED/Mods"
BACKUPS="$HKMOD_HOME/backups"
BUILD="$HKMOD_HOME/build"
CACHE="$HKMOD_HOME/cache"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)-$$"

# Files that earlier modding attempts may have left in Managed/. They are never part of the
# game itself, so they are excluded when collecting the vanilla reference assemblies.
LEFTOVER_RE='^(Assembly-CSharp\.dll\.v|Assembly-CSharp\.xml|MMHOOK_.*|Mono\.Cecil.*|MonoMod\..*|README\.md|libunityscenerepacker\.dylib|mscorlib\.xml|System\.ValueTuple\.dll|TeamCherry\.Localization\.xml)$'

# Mods tested on 1.5.12620 (name|how). "patched" = built from source with a patch from patches/.
TESTED_MODS="Satchel|ok
Enemy HP Bar|ok
Benchwarp|patched"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
CURL_OPTS="-fsSL --proto =https --proto-redir =https --connect-timeout 20 --retry 3 --retry-delay 2"

# ---------------------------------------------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=; G=; Y=; R=; N=; fi
say()  { printf '%s\n' "${B}==>${N} $*"; }
ok()   { printf '%s\n' "  ${G}ok${N}  $*"; }
warn() { printf '%s\n' "  ${Y}!!${N}  $*" >&2; }
die()  { printf '%s\n' "${R}error:${N} $*" >&2; exit 1; }

# If the script stops while ON_FAIL is set (error, Ctrl-C), that message tells the user what state
# things are in and how to recover.
ON_FAIL=""
SWAP_TMP=""    # partial restore copy to delete if we stop before it was verified
SWAP_LIVE=""   # during the swap itself: the live path and where its old contents were moved
SWAP_ASIDE=""
on_exit() {
  local rc=$?
  if [ "$rc" != 0 ]; then
    if [ -n "$SWAP_TMP" ]; then rm -rf "$SWAP_TMP"; fi
    # stopped in the middle of a swap: put the old folder back so the game/save is never missing
    if [ -n "$SWAP_LIVE" ] && [ ! -e "$SWAP_LIVE" ] && [ -e "$SWAP_ASIDE" ]; then
      if mv "$SWAP_ASIDE" "$SWAP_LIVE"; then ON_FAIL="${ON_FAIL:+$ON_FAIL }(Rolled back: the previous files are back in place.)"; fi
    fi
    if [ -n "$ON_FAIL" ]; then printf '\n%s\n' "${R}Stopped before finishing.${N} $ON_FAIL" >&2; fi
  fi
  return 0
}
trap on_exit EXIT
trap 'exit 130' INT TERM

game_running()   { pgrep -f "$(basename "$GAME_APP")/Contents/MacOS" >/dev/null 2>&1; }
require_closed() { if game_running; then die "Hollow Knight is running. Quit the game first."; fi; }
require_game()   { [ -d "$MANAGED" ] || die "Hollow Knight not found at: $GAME_APP
       Install it from Steam, or set HKMOD_GAME_APP to the path of hollow_knight.app."; }
game_version()   { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || echo "unknown"; }
has()            { command -v "$1" >/dev/null 2>&1; }
sha256()         { shasum -a 256 "$1" | cut -d' ' -f1; }

# classify_managed <dir>: vanilla | modded | unknown | missing
classify_managed() {
  local d="$1"
  [ -f "$d/Assembly-CSharp.dll" ] || { echo missing; return 0; }
  if LC_ALL=C grep -a -q "ModHooks" "$d/Assembly-CSharp.dll"; then echo modded; return 0; fi
  if [ "$(sha256 "$d/Assembly-CSharp.dll")" = "$VANILLA_SHA_ASSEMBLY" ] && [ -f "$d/TeamCherry.Localization.dll" ] &&
     [ "$(sha256 "$d/TeamCherry.Localization.dll")" = "$VANILLA_SHA_LOCALIZATION" ]; then echo vanilla; return 0; fi
  # other game versions (only with HKMOD_FORCE=1): no API markers and a plausible file size
  if [ "${HKMOD_FORCE:-0}" = 1 ] && [ "$(wc -c < "$d/Assembly-CSharp.dll")" -gt 1000000 ] &&
     ! LC_ALL=C grep -a -q "MonoMod" "$d/TeamCherry.Localization.dll" 2>/dev/null; then echo vanilla; return 0; fi
  echo unknown
}
api_installed() { [ "$(classify_managed "$1")" = modded ]; }

check_game_version() {
  local v; v="$(game_version "$GAME_APP")"
  if [ "$v" != "$EXPECTED_GAME_VERSION" ]; then
    [ "${HKMOD_FORCE:-0}" = "1" ] && { warn "game version $v (expected $EXPECTED_GAME_VERSION); continuing because HKMOD_FORCE=1"; return 0; }
    die "game version is $v, but this tool is for $EXPECTED_GAME_VERSION.
       Set HKMOD_FORCE=1 to try anyway."
  fi
}

require_tools() {
  local t missing=""
  for t in "$@"; do has "$t" || missing="$missing $t"; done
  [ -z "$missing" ] || die "missing tools:$missing. Run ./hkmod.sh doctor for install instructions."
}

tree_hash() { (cd "$1" && find . -type f -exec shasum {} + 2>/dev/null | LC_ALL=C sort -k2); }
same_tree() { diff -q <(tree_hash "$1") <(tree_hash "$2") >/dev/null; }

# missing_game_files <backup Managed>: game assemblies (*.dll, *.dylib) present in the live Managed
# folder but missing from the backup (API files and leftovers are ignored). Empty = backup is complete.
missing_game_files() {
  local f n
  for f in "$MANAGED"/*.dll "$MANAGED"/*.dylib; do
    [ -f "$f" ] || continue
    n="$(basename "$f")"
    if [[ "$n" =~ $LEFTOVER_RE ]]; then continue; fi
    if [ ! -e "$1/$n" ]; then echo "$n"; fi
  done
  return 0
}

# a mod name from the command line or from ModLinks must be a plain folder name
valid_name() {
  case "$1" in
    ""|.|..|-*|*/*|*\"*) return 1 ;;
  esac
  [ "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" = disabled ] && return 1
  return 0
}
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# ---------------------------------------------------------------------------------------------
cmd_doctor() {
  local fail=0 v
  say "Checking this Mac"
  [ "$(uname -s)" = "Darwin" ] || { warn "this tool is for macOS"; fail=1; }
  case "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)" in
    Apple*) ok "Apple Silicon ($(sysctl -n machdep.cpu.brand_string)); the API runs natively, no Rosetta needed" ;;
    *)      ok "Intel Mac; should work too, but only Apple Silicon has been tested" ;;
  esac

  if [ -d "$MANAGED" ]; then
    v="$(game_version "$GAME_APP")"
    if [ "$v" = "$EXPECTED_GAME_VERSION" ]; then ok "Hollow Knight $v found"
    elif [ "${HKMOD_FORCE:-0}" = "1" ]; then warn "Hollow Knight $v found, but this tool targets $EXPECTED_GAME_VERSION (continuing: HKMOD_FORCE=1)"
    else warn "Hollow Knight $v found, but this tool targets $EXPECTED_GAME_VERSION"; fail=1; fi
    case "$(classify_managed "$MANAGED")" in
      modded)  ok "Modding API is installed" ;;
      vanilla) ok "game files are vanilla (no Modding API yet)" ;;
      *)       warn "game files are neither vanilla $EXPECTED_GAME_VERSION nor this Modding API. Run Steam > Hollow Knight > Properties > Installed Files > Verify integrity of game files"; fail=1 ;;
    esac
  else
    warn "Hollow Knight not found at: $GAME_APP (set HKMOD_GAME_APP if it is somewhere else)"; fail=1
  fi
  [ -d "/Applications/Steam.app" ] && ok "Steam installed" || warn "Steam.app not found in /Applications (the game must be started through Steam)"
  [ -d "$SAVE_DIR" ] && ok "save folder found" || warn "no save folder yet. Start the game once so there is something to back up"
  if game_running; then warn "Hollow Knight is running. Quit it before running install or restore"; fail=1; fi

  if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools"
  else warn "Xcode Command Line Tools missing. Install: xcode-select --install"; fail=1; fi
  for t in git curl unzip shasum xmllint lipo; do
    has "$t" && ok "$t" || { warn "$t missing (comes with the Xcode Command Line Tools)"; fail=1; }
  done
  if has dotnet && dotnet --list-sdks 2>/dev/null | grep -q .; then ok ".NET SDK $(dotnet --version 2>/dev/null)"
  else warn ".NET SDK missing. Install: brew install dotnet   (or https://dotnet.microsoft.com/download)"; fail=1; fi
  if has mono; then ok "mono $(mono --version 2>/dev/null | head -1 | sed 's/.*version \([^ ]*\).*/\1/')"
  else warn "mono missing (needed by the API build). Install: brew install mono"; fail=1; fi
  if ! has brew && { ! has dotnet || ! has mono; }; then
    warn "Homebrew is not installed. Get it from https://brew.sh, then run the brew commands above."
  fi

  if [ "$fail" != 0 ]; then say "${Y}Fix the items marked !! and run ./hkmod.sh doctor again.${N}"
  elif [ -n "${DOCTOR_QUIET:-}" ]; then say "${G}All good.${N}"
  else say "${G}All good.${N} Next: ./hkmod.sh install"; fi
  return "$fail"
}

# ---------------------------------------------------------------------------------------------
# A backup is written to backups/.partial-<ts> and only renamed to backups/<ts> once it is complete
# and verified, so an interrupted backup can never be picked by restore.
cmd_backup() {
  require_game; require_closed
  local dst="$BACKUPS/$TS" tmp="$BACKUPS/.partial-$TS" state
  mkdir -p "$tmp/app_misc"
  ON_FAIL="The backup was not completed (nothing was changed). You can delete $tmp."
  say "Backing up to $dst"
  if [ -d "$SAVE_DIR" ]; then
    ditto "$SAVE_DIR" "$tmp/save"
    same_tree "$SAVE_DIR" "$tmp/save" || die "save backup verification failed"
    ok "save folder ($(du -sh "$tmp/save" | cut -f1)) verified"
  else
    warn "no save folder yet at $SAVE_DIR (nothing to back up)"
  fi
  ditto "$MANAGED" "$tmp/Managed"
  same_tree "$MANAGED" "$tmp/Managed" || die "Managed backup verification failed"
  ok "game Managed folder ($(du -sh "$tmp/Managed" | cut -f1)) verified"
  cp -p "$GAME_APP/Contents/Info.plist" "$tmp/app_misc/Info.plist"
  state="$(classify_managed "$tmp/Managed")"
  printf 'state=%s\ngame_version=%s\ncreated=%s\ncomplete=1\n' "$state" "$(game_version "$GAME_APP")" "$TS" > "$tmp/BACKUP_INFO"
  mv "$tmp" "$dst"
  ON_FAIL=""
  ok "backup complete (game files: $state)"
  LAST_BACKUP="$dst"
}

backup_field() { sed -n "s/^$2=//p" "$1/BACKUP_INFO" 2>/dev/null || true; }
backups_newest_first() {
  local d
  [ -d "$BACKUPS" ] || return 0
  find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d -name '2*' | LC_ALL=C sort -r | while IFS= read -r d; do
    if [ "$(backup_field "$d" complete)" = 1 ]; then echo "$d"; fi
  done
  return 0
}
# newest complete backup whose game files are vanilla and match the installed game version
latest_vanilla_backup() {
  local d v; v="$(game_version "$GAME_APP")"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ "$(backup_field "$d" state)" = vanilla ] && [ "$(backup_field "$d" game_version)" = "$v" ]; then echo "$d"; return 0; fi
  done <<EOF
$(backups_newest_first)
EOF
  return 1
}
latest_backup_with_save() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d/save" ] && { echo "$d"; return 0; }
  done <<EOF
$(backups_newest_first)
EOF
  return 1
}

# ---------------------------------------------------------------------------------------------
# Restores never leave a half-written folder in place: the backup is copied next to the live
# folder, verified, and only then swapped in (the current folder is moved to pre-restore-<ts>/).
swap_in() { # swap_in <backup src> <live path> <aside path> <what was already done, for messages>
  local parent base new old
  parent="$(dirname "$2")"; base="$(basename "$2")"
  new="$parent/.$base.hkmod-new-$$"
  for old in "$parent/.$base.hkmod-new-"*; do if [ -e "$old" ]; then rm -rf "$old"; fi; done   # leftovers of interrupted restores
  SWAP_TMP="$new"
  ON_FAIL="${4:+$4 }This step changed nothing."
  ditto "$1" "$new"
  same_tree "$1" "$new" || die "verification of the copy failed"
  mkdir -p "$(dirname "$3")"
  SWAP_TMP=""; SWAP_LIVE="$2"; SWAP_ASIDE="$3"
  ON_FAIL="${4:+$4 }If $2 is missing, your previous files are in $3. To put them back: mv \"$3\" \"$2\""
  if [ -e "$2" ] || [ -L "$2" ]; then mv "$2" "$3"; fi
  mv "$new" "$2"
  SWAP_LIVE=""; SWAP_ASIDE=""
  ON_FAIL=""
}

confirm() { # confirm <question>: true if --yes was given or the user types y
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  [ -t 0 ] || die "this would overwrite your save. Re-run with --yes to confirm."
  local a; printf '%s [y/N] ' "$1"; read -r a || true
  case "$a" in y|Y|yes|YES) return 0 ;; *) die "cancelled; nothing was changed" ;; esac
}

cmd_restore() {
  local mode="" dir="" game_src="" game_managed="" save_src="" aside cls bv a missing
  ASSUME_YES=0
  for a in "$@"; do
    case "$a" in
      --yes|-y) ASSUME_YES=1 ;;
      game|save|all) if [ -z "$mode" ]; then mode="$a"; else die "use only one of: game, save, all"; fi ;;
      *) dir="$a" ;;
    esac
  done
  case "$mode" in game|save|all) ;; *) die "usage: ./hkmod.sh restore game|save|all [BACKUP_DIR] [--yes]";; esac
  if [ -n "$dir" ]; then
    case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
    dir="${dir%/}"
    [ -d "$dir" ] || die "$dir does not exist"
  fi
  require_game; require_closed

  if [ "$mode" != save ]; then
    if [ -n "$dir" ]; then game_src="$dir"; else game_src="$(latest_vanilla_backup || true)"; fi
    [ -n "$game_src" ] || die "no vanilla backup for game version $(game_version "$GAME_APP").
       Use Steam > Hollow Knight > Properties > Installed Files > Verify integrity of game files instead."
    case "$game_src/" in */.partial-*) die "$game_src is part of an interrupted backup and can't be used";; esac
    if [ -f "$game_src/Assembly-CSharp.dll" ]; then game_managed="$game_src"     # the Managed copy itself
      [ "$(basename "$game_src")" = Managed ] && [ -f "$(dirname "$game_src")/BACKUP_INFO" ] && game_src="$(dirname "$game_src")"
    elif [ -d "$game_src/Managed" ]; then game_managed="$game_src/Managed"
    else die "$game_src is not a backup folder (it has no Managed/ folder and no Assembly-CSharp.dll)"; fi
    if [ -f "$game_src/BACKUP_INFO" ] && [ "$(backup_field "$game_src" complete)" != 1 ]; then die "$game_src is an incomplete backup"; fi
    cls="$(classify_managed "$game_managed")"
    [ "$cls" = vanilla ] || die "the game files in $game_src are not vanilla $EXPECTED_GAME_VERSION (they look $cls), so they can't be used to go back to vanilla.
       (Backups taken while the Modding API was installed can only be used for restore save.)
       Use Steam's \"Verify integrity of game files\" instead."
    missing="$(missing_game_files "$game_managed")"
    [ -z "$missing" ] || die "these game files are in the game folder but not in the backup $game_src:
$(printf '%s\n' "$missing" | head -10 | sed 's/^/         /')
       The backup is incomplete, or these files were added to the game folder by hand (move them away first)."
    bv="$(backup_field "$game_src" game_version)"
    if [ "$(game_version "$GAME_APP")" != "${bv:-$EXPECTED_GAME_VERSION}" ]; then
      die "the backup is for game version ${bv:-$EXPECTED_GAME_VERSION}, but the game is now $(game_version "$GAME_APP") (Steam updated it).
       Restoring would mix versions. Use Steam's \"Verify integrity of game files\" instead."
    fi
  fi
  if [ "$mode" != game ]; then
    if [ -n "$dir" ]; then save_src="$dir"; else save_src="$(latest_backup_with_save || true)"; fi
    [ -n "$save_src" ] && [ -d "$save_src/save" ] || die "no backup with a save folder found${dir:+ in $dir}"
    case "$save_src/" in */.partial-*) die "$save_src is part of an interrupted backup and can't be used";; esac
    if [ -f "$save_src/BACKUP_INFO" ] && [ "$(backup_field "$save_src" complete)" != 1 ]; then die "$save_src is an incomplete backup"; fi
    [ -L "$SAVE_DIR" ] && die "your save folder is a symbolic link (synced folder?). Restore it by hand from $save_src/save"
    confirm "Replace your current save with the one in $save_src? Progress made after that backup will be lost."
  fi

  aside="$HKMOD_HOME/pre-restore-$TS"
  say "Current files will be moved to $aside"
  if [ -n "$game_src" ]; then
    say "Restoring vanilla game files from $game_src"
    swap_in "$game_managed" "$MANAGED" "$aside/Managed"
    ok "game files restored and verified (vanilla game code; the Modding API is no longer active)"
    [ -d "$MODS" ] && warn "the backup also contained a Mods folder; it was restored as it was, but mods don't load without the Modding API"
  fi
  if [ -n "$save_src" ]; then
    say "Restoring save folder from $save_src"
    swap_in "$save_src/save" "$SAVE_DIR" "$aside/save" "${game_src:+The game files were already restored; your save was not changed yet.}"
    ok "save restored and verified"
    warn "if Steam reports a Cloud conflict on the next launch, choose the LOCAL files"
  fi
}

# ---------------------------------------------------------------------------------------------
fetch_repo() { # fetch_repo <url> <ref> <dir>
  case "$3" in "$HKMOD_HOME"/build/*) ;; *) die "internal error: refusing to use $3 as a build folder" ;; esac
  if [ -d "$3/.git" ]; then
    git -C "$3" remote set-url origin "$1"
    git -C "$3" fetch -q origin || die "git fetch failed for $1"
  else
    rm -rf "$3"; mkdir -p "$(dirname "$3")"
    git clone -q "$1" "$3" || die "git clone failed for $1"
  fi
  git -C "$3" -c advice.detachedHead=false checkout -q --force "$2" || die "commit $2 not found in $1"
  git -C "$3" clean -q -xfd
}

run_logged() { # run_logged <logfile> <cmd...>
  local log="$1"; shift
  if ! "$@" >>"$log" 2>&1; then
    tail -25 "$log" >&2
    die "command failed: $*  (full log: $log)"
  fi
}

cmd_install_api() {
  require_game; require_closed; check_game_version
  require_tools git dotnet mono lipo shasum
  local refs_src api="$BUILD/api" log="$BUILD/api-build.log" f n out pkg old_mods=""

  # 1. backup first; find a vanilla copy of the game's assemblies to build against
  case "$(classify_managed "$MANAGED")" in
    vanilla)
      cmd_backup; refs_src="$LAST_BACKUP/Managed" ;;
    modded)
      refs_src="$(latest_vanilla_backup || true)"
      [ -n "$refs_src" ] || die "the Modding API is already installed, and there is no vanilla backup to build from.
       Run Steam > Hollow Knight > Properties > Installed Files > Verify integrity of game files, then run install again."
      refs_src="$refs_src/Managed"
      cmd_backup ;;
    *)
      die "the game files are neither vanilla $EXPECTED_GAME_VERSION nor this Modding API (another mod loader, or a damaged install).
       Run Steam > Hollow Knight > Properties > Installed Files > Verify integrity of game files, then run install again." ;;
  esac

  # 2. get the API source
  say "Fetching Modding API source ($API_REPO @ ${API_REF:0:7})"
  fetch_repo "$API_REPO" "$API_REF" "$api"
  mkdir -p "$api/Vanilla"
  for f in "$refs_src"/*; do
    n="$(basename "$f")"
    [ -f "$f" ] || continue
    [[ "$n" =~ $LEFTOVER_RE ]] && continue
    cp -p "$f" "$api/Vanilla/"
  done
  [ "$(classify_managed "$api/Vanilla")" = vanilla ] || die "internal error: reference assemblies are not vanilla"
  ok "vanilla game assemblies copied ($(ls "$api/Vanilla" | wc -l | tr -d ' ') files)"

  # 3. build (same steps as the project's CI; -p:CopyDir= keeps the build from copying anywhere)
  say "Building the Modding API (takes a few minutes; log: $log)"
  : > "$log"
  ( cd "$api"
    run_logged "$log" dotnet build PrePatcher -o PrePatcher/Output -p:Configuration=Release
    run_logged "$log" dotnet build PostPatcher -o PostPatcher/Output -p:Configuration=Release
    run_logged "$log" dotnet build TeamCherry.Localization --runtime osx-x64 -p:Configuration=Release -p:CopyDir=
    run_logged "$log" dotnet build Assembly-CSharp --runtime osx-x64 -p:Configuration=Release -p:CopyDir=
  )
  out="$api/OutputFinal"
  api_installed "$out" || die "build finished but $out/Assembly-CSharp.dll is not a modded assembly (log: $log)"
  # the build copies only the x64 slice of the native scene repacker; merge in arm64 (CI does the same)
  pkg="$(ls -d "$api"/Assembly-CSharp/packages/unityscenerepacker/*/runtimes 2>/dev/null | head -1 || true)"
  [ -n "$pkg" ] || die "unityscenerepacker package not found (log: $log)"
  lipo -create -output "$out/libunityscenerepacker.dylib" \
    "$pkg/osx-x64/native/libunityscenerepacker.dylib" "$pkg/osx-arm64/native/libunityscenerepacker.dylib"
  ok "build succeeded"

  # 4. install
  require_closed
  say "Installing into the game"
  ON_FAIL="The game files may be half-installed. Your save is not affected. Run ./hkmod.sh install again, or ./hkmod.sh restore game to go back to vanilla."
  for f in "$out"/*; do
    n="$(basename "$f")"
    [ "$n" = README.md ] && continue
    cp -p "$f" "$MANAGED/$n"
    cmp -s "$f" "$MANAGED/$n" || die "copy verification failed for $n"
  done
  mkdir -p "$MODS"
  ON_FAIL=""
  ok "Modding API installed ($(ls "$out" | grep -vc README.md | tr -d ' ') files)"
  for f in "$MODS"/*/; do
    [ -d "$f" ] || continue; n="$(basename "$f")"; [ "$n" = Disabled ] && continue
    case "
${REQUESTED_MODS:-}
" in *"
$n
"*) continue ;; esac
    old_mods="$old_mods \"$n\""
  done
  [ -z "$old_mods" ] || warn "mods already in the Mods folder were kept:$old_mods. Old versions may not work on $EXPECTED_GAME_VERSION; reinstall them with install-mod or remove them with remove-mod."
  return 0
}

# ---------------------------------------------------------------------------------------------
modlinks() {
  set -e
  local f="$CACHE/ModLinks.xml"
  mkdir -p "$CACHE"
  if [ ! -s "$f" ] || [ -n "$(find "$f" -mmin +360 2>/dev/null)" ]; then
    # shellcheck disable=SC2086
    if curl $CURL_OPTS --max-time 120 -o "$f.tmp" -- "$MODLINKS_URL" && xmllint --noout "$f.tmp" 2>/dev/null; then
      mv "$f.tmp" "$f"
    else
      rm -f "$f.tmp"
      [ -s "$f" ] || die "could not download a valid ModLinks list from $MODLINKS_URL"
      warn "could not refresh ModLinks; using the cached copy"
    fi
  fi
  echo "$f"
}

# XPath helpers (ModLinks uses a default namespace, so match on local-name())
mx() { xmllint --xpath "$2" "$1" 2>/dev/null || true; }
manifest_xp() { printf '//*[local-name()="Manifest"][*[local-name()="Name"]="%s"]' "$1"; }
el() { printf '*[local-name()="%s"]' "$1"; }
mod_exists() { local n; n="$(mx "$1" "count($(manifest_xp "$2"))")"; [ "${n:-0}" -ge 1 ] 2>/dev/null; }
mod_field()  { mx "$1" "normalize-space($(manifest_xp "$2")/$(el "$3"))"; }
# download link: <Link>, or the Mac entry of per-platform <Links>
mod_link() {
  local u; u="$(mx "$1" "normalize-space($(manifest_xp "$2")/$(el Link))")"
  [ -n "$u" ] || u="$(mx "$1" "normalize-space($(manifest_xp "$2")/$(el Links)/$(el Mac))")"
  printf '%s' "$u"
}
mod_sha() {
  local s; s="$(mx "$1" "string($(manifest_xp "$2")/$(el Link)/@SHA256)")"
  [ -n "$s" ] || s="$(mx "$1" "string($(manifest_xp "$2")/$(el Links)/$(el Mac)/@SHA256)")"
  printf '%s' "$s" | tr 'A-F' 'a-f'
}
mod_deps() {
  local xp i n
  xp="$(manifest_xp "$2")/$(el Dependencies)/$(el Dependency)"
  n="$(mx "$1" "count($xp)")"; n="${n:-0}"
  i=1; while [ "$i" -le "$n" ]; do mx "$1" "normalize-space(($xp)[$i])"; echo; i=$((i+1)); done
}
all_names() { mx "$1" '//*[local-name()="Manifest"]/*[local-name()="Name"]/text()' | tr -s '\n'; }
tested_how() { printf '%s\n' "$TESTED_MODS" | awk -F'|' -v n="$1" '$1 == n { print $2 }'; }

RESOLVED=""
VISITING=""
resolve() { # resolve <modlinks> <name>: dependencies first
  local d exact close
  valid_name "$2" || die "invalid mod name: \"$2\""
  case "
$RESOLVED
" in *"
$2
"*) return 0;; esac
  case "
$VISITING
" in *"
$2
"*) die "dependency cycle in ModLinks involving \"$2\"";; esac
  VISITING="$VISITING
$2"
  if ! mod_exists "$1" "$2"; then
    exact="$(all_names "$1" | grep -i -x -F -- "$2" | head -1 || true)"
    [ -n "$exact" ] && die "unknown mod: \"$2\". Did you mean \"$exact\"? (names are case-sensitive)"
    close="$(all_names "$1" | grep -i -F -- "$(printf '%s' "$2" | cut -c1-5)" | head -8 || true)"
    [ -n "$close" ] && { warn "\"$2\" is not in ModLinks. Similar names:"; printf '%s\n' "$close" | sed 's/^/        /' >&2; }
    die "unknown mod: \"$2\" (see ./hkmod.sh list-mods)"
  fi
  while IFS= read -r d; do [ -n "$d" ] && resolve "$1" "$d"; done <<EOF
$(mod_deps "$1" "$2")
EOF
  RESOLVED="$RESOLVED
$2"
}

move_aside() { # move an existing mod folder to ~/HKMod/replaced/<ts>/
  valid_name "$1" || die "invalid mod name: \"$1\""
  if [ -e "$MODS/$1" ]; then mkdir -p "$HKMOD_HOME/replaced/$TS"; mv "$MODS/$1" "$HKMOD_HOME/replaced/$TS/"; fi
}

download_mod() { # download_mod <modlinks> <name>: prints the verified local file
  set -e
  local url sha file got
  url="$(mod_link "$1" "$2")"; sha="$(mod_sha "$1" "$2")"
  case "$url" in https://*) ;; *) die "no usable https download link for $2 in ModLinks (got: \"$url\")" ;; esac
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$' || die "ModLinks has no valid SHA-256 checksum for $2; install it by hand if you trust it"
  mkdir -p "$CACHE/downloads"
  file="$CACHE/downloads/$sha"
  if [ ! -s "$file" ]; then
    # shellcheck disable=SC2086
    curl $CURL_OPTS --max-time 600 -o "$file.tmp" -- "$url" || { rm -f "$file.tmp"; die "download failed: $url"; }
    mv "$file.tmp" "$file"
  fi
  got="$(sha256 "$file")"
  [ "$got" = "$sha" ] || { rm -f "$file"; die "SHA-256 mismatch for $2 (expected $sha, got $got)"; }
  printf '%s' "$file"
}

install_download() { # install_download <name> <file> <url-basename>
  local tmp
  tmp="$(mktemp -d "$CACHE/extract.XXXXXX")"
  case "$3" in
    *.zip|*.ZIP) unzip -q "$2" -d "$tmp" || { rm -rf "$tmp"; die "could not unzip $2"; } ;;
    *)           cp "$2" "$tmp/$3" ;;
  esac
  chmod 755 "$tmp"
  require_closed
  move_aside "$1"
  mv "$tmp" "$MODS/$1"
}

install_benchwarp() {
  local src="$BUILD/benchwarp" refs="$BUILD/refs" log="$BUILD/benchwarp-build.log" p dll
  require_tools git dotnet
  say "Building Benchwarp from source with the $EXPECTED_GAME_VERSION patch"
  fetch_repo "$BENCHWARP_REPO" "$BENCHWARP_REF" "$src"
  for p in "$SCRIPT_DIR"/patches/benchwarp/*.patch; do
    git -C "$src" apply "$p" || die "patch did not apply: $p"
  done
  # compile against a copy of the (now modded) game assemblies, so the build never writes into the game
  rm -rf "$refs"; mkdir -p "$refs"; cp -p "$MANAGED"/*.dll "$refs/"
  printf '<Project><PropertyGroup><HollowKnightRefs>%s</HollowKnightRefs></PropertyGroup></Project>\n' "$(xml_escape "$refs")" > "$src/Benchwarp/LocalOverrides.targets"
  : > "$log"
  run_logged "$log" dotnet build "$src/Benchwarp.sln" -c Release
  dll="$src/Benchwarp/bin/Release/Benchwarp.dll"
  [ -f "$dll" ] || die "Benchwarp.dll was not produced (log: $log)"
  require_closed
  move_aside Benchwarp
  mkdir -p "$MODS/Benchwarp"
  cp -p "$dll" "$MODS/Benchwarp/"
  [ -f "$src/Benchwarp/bin/Release/Benchwarp.pdb" ] && cp -p "$src/Benchwarp/bin/Release/Benchwarp.pdb" "$MODS/Benchwarp/"
  [ -f "$src/README.md" ] && cp -p "$src/README.md" "$MODS/Benchwarp/"
  return 0
}

cmd_install_mod() {
  [ "$#" -gt 0 ] || die "usage: ./hkmod.sh install-mod \"Mod Name\" ...   (see ./hkmod.sh list-mods)"
  require_game; require_closed; require_tools curl unzip shasum xmllint
  api_installed "$MANAGED" || die "install the Modding API first: ./hkmod.sh install"
  local ml name how ver files="" file
  ml="$(modlinks)"
  RESOLVED=""; VISITING=""
  for name in "$@"; do resolve "$ml" "$name"; done

  # download and verify everything first, so a bad link stops the run before anything is installed
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ "$(tested_how "$name")" = patched ] && continue
    say "Downloading $name $(mod_field "$ml" "$name" Version)"
    file="$(download_mod "$ml" "$name")"
    files="$files
$name|$file|$(basename "$(mod_link "$ml" "$name")")"
  done <<EOF
$RESOLVED
EOF

  mkdir -p "$MODS"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    how="$(tested_how "$name")"; ver="$(mod_field "$ml" "$name" Version)"
    if [ "$how" = patched ]; then
      install_benchwarp
      ok "$name (built from source for $EXPECTED_GAME_VERSION)"
    else
      file="$(printf '%s\n' "$files" | awk -F'|' -v n="$name" '$1 == n { print $2 }')"
      install_download "$name" "$file" "$(printf '%s\n' "$files" | awk -F'|' -v n="$name" '$1 == n { print $3 }')"
      if [ "$how" = ok ]; then ok "$name $ver (tested on $EXPECTED_GAME_VERSION)"
      else ok "$name $ver"; warn "$name has not been tested on $EXPECTED_GAME_VERSION. If the game misbehaves, check ModLog.txt and remove it with: ./hkmod.sh remove-mod \"$name\""; fi
    fi
  done <<EOF
$RESOLVED
EOF
}

installed_exact() { # exact-case match against the folder names (APFS is case-insensitive)
  local d
  for d in "$MODS"/*/; do [ -d "$d" ] || continue; [ "$(basename "$d")" = "$1" ] && return 0; done
  return 1
}
cmd_remove_mod() {
  [ "$#" -gt 0 ] || die "usage: ./hkmod.sh remove-mod \"Mod Name\" ..."
  require_game; require_closed
  local name d
  for name in "$@"; do
    valid_name "$name" || die "invalid mod name: \"$name\""
    if ! installed_exact "$name"; then
      d="$(for d in "$MODS"/*/; do [ -d "$d" ] && basename "$d"; done | grep -i -x -F -- "$name" | head -1 || true)"
      die "$name is not installed${d:+ (did you mean \"$d\"?)}; nothing was removed"
    fi
  done
  for name in "$@"; do
    move_aside "$name"; ok "removed $name (moved to $HKMOD_HOME/replaced/$TS/)"
  done
}

cmd_list_mods() {
  require_tools curl xmllint
  local ml name; ml="$(modlinks)"
  if [ -n "${1:-}" ] && ! all_names "$ml" | grep -qiF -- "$1"; then say "no mods match \"$1\""; return 0; fi
  all_names "$ml" | LC_ALL=C sort -f | while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -n "${1:-}" ]; then printf '%s\n' "$name" | grep -qiF -- "$1" || continue; fi
    case "$(tested_how "$name")" in
      ok)      printf '  %s  %s\n' "${G}[tested] ${N}" "$name" ;;
      patched) printf '  %s  %s\n' "${G}[patched]${N}" "$name" ;;
      *)       printf '  %s  %s\n' "         " "$name" ;;
    esac
  done
}

cmd_status() {
  local d n
  say "Game"
  echo "  location: $GAME_APP"
  if [ -d "$MANAGED" ]; then
    echo "  version:  $(game_version "$GAME_APP")"
    case "$(classify_managed "$MANAGED")" in
      modded)  echo "  Modding API: installed" ;;
      vanilla) echo "  Modding API: not installed (vanilla)" ;;
      *)       echo "  Modding API: not installed; game files are not the known vanilla files" ;;
    esac
    if [ -d "$MODS" ]; then
      echo "  mods:"
      n=0; for d in "$MODS"/*/; do [ -d "$d" ] || continue; d="$(basename "${d%/}")"; [ "$d" = Disabled ] && continue; echo "    - $d"; n=$((n+1)); done
      [ "$n" = 0 ] && echo "    (none)"
    fi
  else
    echo "  not found"
  fi
  [ -f "$SAVE_DIR/ModLog.txt" ] && echo "  mod log:  $SAVE_DIR/ModLog.txt"
  say "Backups ($BACKUPS)"
  n=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    echo "  $(basename "$d")  game files: $(backup_field "$d" state), version $(backup_field "$d" game_version)$([ -d "$d/save" ] && echo ', save included')"; n=$((n+1))
  done <<EOF
$(backups_newest_first)
EOF
  [ "$n" = 0 ] && echo "  (none yet)"
  n="$(count_matching "$BACKUPS" '.partial-*')"
  [ "$n" = 0 ] || echo "  $n interrupted backup(s) (backups/.partial-*): unusable, removed by ./hkmod.sh clean"
  n="$(count_matching "$HKMOD_HOME" 'pre-restore-*')"
  [ "$n" = 0 ] || echo "  $n pre-restore folder(s): files moved aside by restores (delete by hand when no longer needed)"
  [ -d "$HKMOD_HOME/replaced" ] && echo "  replaced/: mods moved aside by remove-mod and reinstalls (delete by hand when no longer needed)"
  n="$(stale_swaps | wc -l | tr -d ' ')"
  [ "$n" = 0 ] || echo "  $n leftover temporary copies from interrupted restores; removed by ./hkmod.sh clean"
  [ -d "$HKMOD_HOME" ] && echo "  disk used by $HKMOD_HOME: $(du -sh "$HKMOD_HOME" 2>/dev/null | cut -f1)"
  return 0
}

count_matching() { # count_matching <dir> <glob>
  if [ -d "$1" ]; then find "$1" -mindepth 1 -maxdepth 1 -name "$2" | wc -l | tr -d ' '; else echo 0; fi
}
stale_swaps() { # temporary copies left next to the game/save folder by a killed restore
  local d
  for d in "$(dirname "$MANAGED")"/.Managed.hkmod-new-* "$(dirname "$SAVE_DIR")/.$(basename "$SAVE_DIR").hkmod-new-"*; do
    if [ -e "$d" ]; then echo "$d"; fi
  done
  return 0
}
cmd_clean() {
  local d
  require_closed
  for d in "$BUILD" "$CACHE"; do
    if [ -d "$d" ]; then rm -rf "$d"; ok "deleted $d"; fi
  done
  if [ -d "$BACKUPS" ]; then
    while IFS= read -r d; do
      if [ -n "$d" ]; then rm -rf "$d"; ok "deleted interrupted backup $(basename "$d")"; fi
    done <<EOF
$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -name '.partial-*')
EOF
  fi
  while IFS= read -r d; do
    if [ -n "$d" ]; then rm -rf "$d"; ok "deleted leftover temporary copy $d"; fi
  done <<EOF
$(stale_swaps)
EOF
  ok "backups kept in $BACKUPS"
}

cmd_launch() {
  if [ "${1:-}" = "--rosetta" ]; then
    require_game
    pgrep -x steam_osx >/dev/null 2>&1 || warn "Steam does not seem to be running; start Steam first"
    say "Starting under Rosetta"
    SteamAppId=$STEAM_APPID SteamGameId=$STEAM_APPID arch -x86_64 "$GAME_APP/Contents/MacOS/Hollow Knight" >/dev/null 2>&1 &
  else
    say "Starting through Steam"
    open "steam://rungameid/$STEAM_APPID"
  fi
}

cmd_install() {
  local a q="" ml
  DOCTOR_QUIET=1 cmd_doctor || die "fix the problems above first"
  if [ "$#" -gt 0 ]; then   # check mod names before spending minutes on the build
    require_tools curl xmllint
    ml="$(modlinks)"; RESOLVED=""; VISITING=""
    for a in "$@"; do resolve "$ml" "$a"; q="$q \"$a\""; done
    REQUESTED_MODS="$RESOLVED"
  fi
  cmd_install_api
  if [ "$#" -gt 0 ]; then
    ON_FAIL="The Modding API is installed; only the mod step failed. Fix the problem above and run: ./hkmod.sh install-mod$q"
    cmd_install_mod "$@"
    ON_FAIL=""
  fi
  echo
  say "${G}Done.${N} Start the game from Steam (or ./hkmod.sh launch)."
  echo "  The main menu should list \"Modding API\" and your mods in the top-left corner."
  echo "  Add mods:        ./hkmod.sh install-mod \"Mod Name\"   (browse: ./hkmod.sh list-mods)"
  echo "  Back to vanilla: ./hkmod.sh restore game          (your save is not touched)"
}

usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; echo; echo "hkmod $HKMOD_VERSION"; }

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in
  doctor)        cmd_doctor ;;
  install)       cmd_install "$@" ;;
  install-mod)   cmd_install_mod "$@" ;;
  remove-mod)    cmd_remove_mod "$@" ;;
  list-mods)     cmd_list_mods "$@" ;;
  status)        cmd_status ;;
  backup)        cmd_backup ;;
  restore)       cmd_restore "$@" ;;
  launch)        cmd_launch "$@" ;;
  clean)         cmd_clean ;;
  -h|--help|help|"") usage ;;
  -v|--version)  echo "hkmod $HKMOD_VERSION" ;;
  *) usage; die "unknown command: $cmd" ;;
esac
