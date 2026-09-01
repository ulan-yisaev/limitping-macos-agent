#!/bin/zsh

emulate -L zsh
set -euo pipefail

LABEL='com.local.claude-window-warmup.noon-wake'
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

(( EUID == 0 )) || {
  print -u2 -r -- "error: run this helper with administrator privileges"
  exit 1
}

/bin/launchctl bootout system "$PLIST" 2>/dev/null || true

SCHEDULE=$(/usr/bin/pmset -g sched)
REPEATING=$(print -r -- "$SCHEDULE" | /usr/bin/awk '
  /^Repeating power events:/ { inside=1; next }
  /^Scheduled power events:/ { inside=0 }
  inside && NF { print }
')
if [[ -n $REPEATING ]]; then
  LINE_COUNT=$(print -r -- "$REPEATING" | /usr/bin/awk 'NF { n++ } END { print n+0 }')
  EXPECTED_COUNT=$(print -r -- "$REPEATING" \
    | /usr/bin/grep -Ec 'wake(poweron|orpoweron) at 0?6:55(AM)? Wednesday' || true)
  if (( LINE_COUNT == 1 && EXPECTED_COUNT == 1 )); then
    /usr/bin/pmset repeat cancel
  else
    print -u2 -r -- "warning: repeating schedule changed; leaving it untouched"
  fi
fi

# Remove only this helper's outstanding one-time wake events. Never use
# `cancelall`, which could delete events owned by unrelated applications.
typeset -a OWN_EVENTS
OWN_EVENTS=(${(f)"$(print -r -- "$SCHEDULE" | /usr/bin/awk -v owner="$LABEL" '
  index($0, owner) {
    for (i=1; i<=NF; i++) if ($i == "at") print $(i+1), $(i+2)
  }
')"})
typeset event event_date event_time cancel_date
for event in $OWN_EVENTS; do
  event_date=${event%% *}
  event_time=${event#* }
  cancel_date=$(/bin/date -j -f '%m/%d/%Y' "$event_date" '+%m/%d/%y' 2>/dev/null) || continue
  /usr/bin/pmset schedule cancel wakeorpoweron "$cancel_date $event_time" "$LABEL" \
    2>/dev/null || true
done

/bin/rm -f -- "$HELPER" "$PLIST"
print -r -- "Removed the Wednesday wake helper."
