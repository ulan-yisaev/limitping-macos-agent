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
LAUNCH_STATE=$(launchctl print "gui/$(id -u)/$LABEL" 2>&1) || LAUNCH_STATE=""
if [[ -z $LAUNCH_STATE ]]; then
  print -r -- "  loaded: no"
else
  JOB_STATE=$(print -r -- "$LAUNCH_STATE" | /usr/bin/sed -n 's/^[[:space:]]*state = //p' | /usr/bin/head -n 1)
  RUNS=$(print -r -- "$LAUNCH_STATE" | /usr/bin/sed -n 's/^[[:space:]]*runs = //p' | /usr/bin/head -n 1)
  LAST_EXIT=$(print -r -- "$LAUNCH_STATE" | /usr/bin/sed -n 's/^[[:space:]]*last exit code = //p' | /usr/bin/head -n 1)
  INTERVAL=$(print -r -- "$LAUNCH_STATE" | /usr/bin/sed -n 's/^[[:space:]]*run interval = //p' | /usr/bin/head -n 1)
  print -r -- "  loaded: yes"
  if [[ $JOB_STATE == "not running" ]]; then
    print -r -- "  state: idle (normal between scheduled checks)"
  else
    print -r -- "  state: ${JOB_STATE:-unknown}"
  fi
  print -r -- "  runs this login: ${RUNS:-unknown}"
  print -r -- "  last exit: ${LAST_EXIT:-unknown}"
  print -r -- "  interval: ${INTERVAL:-unknown}"
fi

print -r -- ""
print -r -- "Installed files:"
[[ -x "$ROOT/run/warmup-check.sh" ]] && print -r -- "  wrapper: installed" || print -r -- "  wrapper: missing"
[[ -x "$ROOT/bin/limitping" ]] && print -r -- "  limitping: installed" || print -r -- "  limitping: missing"

print -r -- ""
print -r -- "Recent log:"
[[ -f $LOG ]] && /usr/bin/tail -n 12 "$LOG" || print -r -- "  no log yet"
