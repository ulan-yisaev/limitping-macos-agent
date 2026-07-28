#!/bin/zsh

emulate -L zsh
set -euo pipefail

ROOT=${0:A:h}
USER_HOME=${HOME:-}
[[ -n $USER_HOME && -d $USER_HOME ]] || {
  print -u2 -r -- "error: HOME is missing or not a directory"
  exit 1
}

INSTALLED="$USER_HOME/Library/Application Support/ClaudeWindowWarmup/uninstall.sh"
if [[ ! -x $INSTALLED ]]; then
  print -r -- "ClaudeWindowWarmup is not installed for this user."
  exit 0
fi

exec /bin/zsh "$INSTALLED"
