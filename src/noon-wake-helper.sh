#!/bin/zsh

emulate -L zsh
set -euo pipefail

OWNER='com.local.claude-window-warmup.noon-wake'

# The repeating 06:55 Wednesday event wakes the Mac for this helper. Add the
# second wake as a one-time event because pmset supports only one repeating
# wake/power-on event.
[[ $(/bin/date '+%u') == 3 ]] || exit 0

NOW_HM=$(/bin/date '+%H%M')
(( 10#$NOW_HM < 1200 )) || exit 0

TARGET="$(/bin/date '+%m/%d/%y') 12:00:00"

# StartCalendarInterval should invoke this once, but avoid a duplicate if an
# administrator manually kickstarts the daemon.
if /usr/bin/pmset -g sched | /usr/bin/grep -Fq "$OWNER"; then
  exit 0
fi

/usr/bin/pmset schedule wakeorpoweron "$TARGET" "$OWNER"
/usr/bin/logger -t ClaudeWindowWarmup "scheduled Wednesday noon wake for $TARGET"
