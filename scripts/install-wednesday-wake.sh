#!/bin/zsh

emulate -L zsh
set -euo pipefail

LABEL='com.local.claude-window-warmup.noon-wake'
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
REPO_DIR=${0:A:h:h}

die() {
  print -u2 -r -- "error: $*"
  exit 1
}

(( EUID == 0 )) || die "run this helper with administrator privileges"
[[ $(/usr/bin/uname -s) == Darwin ]] || die "this helper supports macOS only"

EXISTING=$(/usr/bin/pmset -g sched)
REPEATING=$(print -r -- "$EXISTING" | /usr/bin/awk '
  /^Repeating power events:/ { inside=1; next }
  /^Scheduled power events:/ { inside=0 }
  inside && NF { print }
')
if [[ -n $REPEATING ]]; then
  LINE_COUNT=$(print -r -- "$REPEATING" | /usr/bin/awk 'NF { n++ } END { print n+0 }')
  EXPECTED_COUNT=$(print -r -- "$REPEATING" \
    | /usr/bin/grep -Ec 'wake(poweron|orpoweron) at 0?6:55(AM)? Wednesday' || true)
  if (( LINE_COUNT != 1 || EXPECTED_COUNT != 1 )); then
    die "an unrelated repeating power event exists; refusing to overwrite it"
  fi
fi

/usr/bin/plutil -lint "$REPO_DIR/templates/noon-wake-launchdaemon.plist"
/bin/launchctl bootout system "$PLIST" 2>/dev/null || true

/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
/usr/bin/install -o root -g wheel -m 755 "$REPO_DIR/src/noon-wake-helper.sh" "$HELPER"
/usr/bin/install -o root -g wheel -m 644 "$REPO_DIR/templates/noon-wake-launchdaemon.plist" "$PLIST"

/usr/bin/pmset repeat wakeorpoweron W 06:55:00
/bin/launchctl bootstrap system "$PLIST"

print -r -- "Installed Wednesday wake schedule:"
print -r -- "  06:55 repeating wake/power-on"
print -r -- "  12:00 one-time wake scheduled each Wednesday morning"
print -r -- ""
/usr/bin/pmset -g sched
