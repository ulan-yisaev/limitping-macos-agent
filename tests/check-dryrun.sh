#!/bin/zsh

emulate -L zsh
set -uo pipefail

TESTS_DIR=${0:A:h}
LIMITPING=${1:-"$HOME/Library/Application Support/ClaudeWindowWarmup/bin/limitping"}
CONFIG_HOME=${2:-"$HOME/Library/Application Support/ClaudeWindowWarmup/config"}

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); print -r -- "    ok   $1" }
bad() { FAIL=$((FAIL + 1)); print -r -- "    FAIL $1" }

[[ -x $LIMITPING ]] || {
  print -u2 -r -- "limitping is not executable: $LIMITPING"
  exit 1
}

OUT=$(XDG_CONFIG_HOME="$CONFIG_HOME" "$LIMITPING" ping claude --dry-run 2>&1)
print -r -- "dry-run output:"
print -r -- "  $OUT"
print -r -- ""

has()   { [[ $OUT == *"$1"* ]] && ok "contains: $1" || bad "missing: $1" }
hasnt() { [[ $OUT == *"$1"* ]] && bad "must not contain: $1" || ok "absent: $1" }

has '--model haiku'
has '--safe-mode'
has '--tools ""'
has '--strict-mcp-config'
has '--system-prompt "Reply only with OK."'
has '--no-chrome'

hasnt ' -p '
hasnt '--print'
hasnt '--bare'
hasnt '--effort'
hasnt '--no-session-persistence'
hasnt '--max-turns'
hasnt '--output-format'
hasnt '--input-format'
hasnt '--json-schema'
hasnt '--dangerously-skip-permissions'
hasnt '--allow-dangerously-skip-permissions'
hasnt '--disable-slash-commands'
hasnt '--fallback-model'
hasnt '--max-budget-usd'
hasnt '--permission-prompt-tool'

[[ $OUT == *'--no-chrome .' ]] \
  && ok "prompt is a positional argument (interactive session)" \
  || bad "prompt is not the trailing positional argument"

ALLOUT=$(XDG_CONFIG_HOME="$CONFIG_HOME" "$LIMITPING" ping --dry-run 2>&1)
if [[ $ALLOUT == *codex* || $ALLOUT == *spark* ]]; then
  bad "unqualified ping would reach another provider: $ALLOUT"
else
  ok "unqualified ping resolves to claude only"
fi
[[ $(print -r -- "$ALLOUT" | /usr/bin/grep -c 'would run') == 1 ]] \
  && ok "exactly one provider enabled" \
  || bad "more than one provider enabled: $ALLOUT"

print -r -- ""
print -r -- "passed: $PASS   failed: $FAIL"
(( FAIL == 0 ))
