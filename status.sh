#!/bin/zsh

emulate -L zsh
set -uo pipefail

LABEL='com.local.claude-window-warmup'
USER_HOME=${HOME:-}
[[ -n $USER_HOME && -d $USER_HOME ]] || {
  print -u2 -r -- "error: HOME is missing or not a directory"
  exit 1
}

ROOT="$USER_HOME/Library/Application Support/ClaudeWindowWarmup"
LOG="$USER_HOME/Library/Logs/ClaudeWindowWarmup/warmup.log"

print -r -- "LaunchAgent:"
launchctl print "gui/$(id -u)/$LABEL" 2>&1 \
  | /usr/bin/grep -E 'state =|runs =|last exit code|run interval' \
  || print -r -- "  not loaded"

print -r -- ""
print -r -- "Installed files:"
[[ -x "$ROOT/run/warmup-check.sh" ]] && print -r -- "  wrapper: installed" || print -r -- "  wrapper: missing"
[[ -x "$ROOT/bin/limitping" ]] && print -r -- "  limitping: installed" || print -r -- "  limitping: missing"

print -r -- ""
print -r -- "Recent log:"
[[ -f $LOG ]] && /usr/bin/tail -n 12 "$LOG" || print -r -- "  no log yet"
