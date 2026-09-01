#!/bin/zsh

emulate -L zsh
set -euo pipefail

REPO_DIR=${0:A:h:h}
TMP_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/limitping-template-tests.XXXXXX")
trap '/bin/rm -rf -- "$TMP_ROOT"' EXIT INT TERM

ROOT="$TMP_ROOT/Home With Spaces/Library/Application Support/ClaudeWindowWarmup"
LOG_DIR="$TMP_ROOT/Home With Spaces/Library/Logs/ClaudeWindowWarmup"
CLAUDE_BIN="$TMP_ROOT/Home With Spaces/bin/claude"
PLIST="$TMP_ROOT/com.local.claude-window-warmup.plist"

escape() {
  print -r -- "$1" | /usr/bin/sed 's/[\\&|]/\\&/g'
}

/usr/bin/sed \
  -e "s|@CWW_ROOT@|$(escape "$ROOT")|g" \
  -e "s|@CWW_LOG_DIR@|$(escape "$LOG_DIR")|g" \
  -e "s|@CWW_CLAUDE_BIN@|$(escape "$CLAUDE_BIN")|g" \
  -e "s|@CWW_CLAUDE_PATH_DIR@|$(escape "${CLAUDE_BIN:h}")|g" \
  -e "s|@CWW_USER_HOME@|$(escape "$TMP_ROOT/Home With Spaces")|g" \
  -e "s|@CWW_ALIGNMENT_ENABLED@|0|g" \
  -e "s|@CWW_ALIGNMENT_ALLOW_CLOSED_LID_ON_AC@|0|g" \
  "$REPO_DIR/src/warmup-check.sh.in" > "$TMP_ROOT/warmup-check.sh"

/usr/bin/sed \
  -e "s|@WARMUP_CHECK@|$(escape "$ROOT/run/warmup-check.sh")|g" \
  -e "s|@LAUNCHD_STDOUT@|$(escape "$LOG_DIR/launchd.stdout.log")|g" \
  -e "s|@LAUNCHD_STDERR@|$(escape "$LOG_DIR/launchd.stderr.log")|g" \
  "$REPO_DIR/templates/launchagent.plist.in" > "$PLIST"

/bin/zsh -n "$TMP_ROOT/warmup-check.sh"
/usr/bin/plutil -lint "$PLIST"
/usr/bin/plutil -lint "$REPO_DIR/templates/noon-wake-launchdaemon.plist"
! /usr/bin/grep -Eq '@(CWW|WARMUP|LAUNCHD)_' "$TMP_ROOT/warmup-check.sh" "$PLIST"
/usr/bin/grep -qF "$ROOT/run/warmup-check.sh" "$PLIST"
/usr/bin/grep -qF "CWW_ROOT='$ROOT'" "$TMP_ROOT/warmup-check.sh"

print -r -- "template rendering passed"
