#!/bin/zsh
#
# Automated tests for warmup-check.sh using fake `claude` and `limitping`
# executables. Every sandbox path deliberately contains spaces.
#
# Usage: /bin/zsh run-tests.sh [/path/to/warmup-check.sh]

emulate -L zsh
set -uo pipefail

TESTS_DIR=${0:A:h}
FAKES_DIR="$TESTS_DIR/fakes"
WRAPPER=${1:-"$TESTS_DIR/../src/warmup-check.sh.in"}

if [[ ! -x $WRAPPER ]]; then
  print -u2 "wrapper not executable: $WRAPPER"
  exit 1
fi

TMPBASE=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cww-tests.XXXXXX")
# $TMPDIR usually ends in a slash; collapse the duplicate so paths recorded by
# the fakes compare equal to the ones the harness builds.
TMPBASE=${TMPBASE//\/\///}
SPACED="$TMPBASE/Claude Window Warmup Tests"
mkdir -p "$SPACED"

PASS=0
FAIL=0
CURRENT=""
typeset -a FAILURES
FAILURES=()

# --- harness ----------------------------------------------------------------

ok()   { PASS=$((PASS + 1)); print -r -- "    ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); FAILURES+=("$CURRENT: $1"); print -r -- "    FAIL $1"; }

start_case() {
  CURRENT="$1"
  print -r -- ""
  print -r -- "== $CURRENT"
  SBX="$SPACED/$CURRENT"
  ROOT="$SBX/Application Support/ClaudeWindowWarmup"
  LOGS="$SBX/Logs/Claude Window Warmup"
  FAKEBIN="$SBX/fake bin"
  FAKEHOME="$SBX/home dir"
  CALLS="$SBX/calls.log"
  LOG="$LOGS/warmup.log"
  mkdir -p "$ROOT/bin" "$ROOT/config/limitping" "$ROOT/run/workdir" "$ROOT/run/lock" \
           "$LOGS" "$FAKEBIN" "$FAKEHOME/.claude"
  cp "$FAKES_DIR/limitping" "$ROOT/bin/limitping"
  cp "$FAKES_DIR/claude" "$FAKEBIN/claude"
  chmod 755 "$ROOT/bin/limitping" "$FAKEBIN/claude"
  : > "$CALLS"
  auth_ok
  # Default: 5h window inactive, weekly low; verification sees it active.
  mk_status "$SBX/status.1.json" false 0 -600 5
  mk_status "$SBX/status.2.json" false 0 17400 5
}

# mk_status FILE ACTIVE USED_PCT RESET_OFFSET_SECS WEEKLY_PCT
# A negative offset puts resets_at in the past, which is what limitping reports
# for a window that has already rolled over (remaining_seconds is then 0).
mk_status() {
  local file="$1" active="$2" used="$3" offset="$4" weekly="$5"
  local now resets weekly_resets remaining
  now=$(/bin/date '+%s')
  remaining=$offset
  (( remaining < 0 )) && remaining=0
  resets=$(/bin/date -u -r $((now + offset)) '+%Y-%m-%dT%H:%M:%SZ')
  weekly_resets=$(/bin/date -u -r $((now + 300000)) '+%Y-%m-%dT%H:%M:%SZ')
  cat > "$file" <<JSON
[
  {
    "provider": "claude",
    "five_hour": {
      "used_percent": $used,
      "remaining_percent": $((100 - used)),
      "active": $active,
      "resets_at": "$resets",
      "remaining_seconds": $remaining,
      "window_seconds": 18000
    },
    "weekly": {
      "used_percent": $weekly,
      "remaining_percent": $((100 - weekly)),
      "active": true,
      "resets_at": "$weekly_resets",
      "remaining_seconds": 300000,
      "window_seconds": 604800
    },
    "limit_reached": false,
    "fetched_at": "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  }
]
JSON
}

auth_ok() {
  cat > "$SBX/auth.json" <<'JSON'
{
  "loggedIn": true,
  "authMethod": "claude.ai",
  "apiProvider": "firstParty",
  "subscriptionType": "team"
}
JSON
  print -r -- 0 > "$SBX/auth.rc"
}

# run [extra env assignments...] -> sets RC
run() {
  local -a env_args
  env_args=(
    "CLAUDE_WARMUP_TEST_MODE=1"
    "CLAUDE_WARMUP_TEST_ROOT=$ROOT"
    "CLAUDE_WARMUP_TEST_LOG_DIR=$LOGS"
    "CLAUDE_WARMUP_TEST_CLAUDE_BIN=$FAKEBIN/claude"
    "CLAUDE_WARMUP_TEST_PATH_DIR=$FAKEBIN"
    "CLAUDE_WARMUP_TEST_HOME=$FAKEHOME"
    "CLAUDE_WARMUP_TEST_LID_STATE=${LID:-open}"
    "CLAUDE_WARMUP_TEST_VERIFY_DELAY=0"
    "FAKE_CALLS=$CALLS"
    "FAKE_SANDBOX=$SBX"
    "HOME=$FAKEHOME"
    "$@"
  )
  /usr/bin/env -i \
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
    "TMPDIR=${TMPDIR:-/tmp}" \
    $env_args \
    /bin/zsh "$WRAPPER" > "$SBX/stdout.txt" 2> "$SBX/stderr.txt"
  RC=$?
  return 0
}

count_pings() {
  local n
  n=$(/usr/bin/grep -c '^limitping ping claude$' "$CALLS" 2>/dev/null) || n=0
  print -r -- "${n:-0}"
}
count_status() {
  local n
  n=$(/usr/bin/grep -c '^limitping status' "$CALLS" 2>/dev/null) || n=0
  print -r -- "${n:-0}"
}

expect_rc()  { [[ $RC == "$1" ]] && ok "exit $1" || bad "exit $RC, want $1"; }
expect_log() { /usr/bin/grep -qF -- "$1" "$LOG" 2>/dev/null && ok "log: $1" || bad "log missing: $1"; }
expect_nolog() { /usr/bin/grep -qF -- "$1" "$LOG" 2>/dev/null && bad "log should not contain: $1" || ok "log clean of: $1"; }
expect_pings() {
  local n; n=$(count_pings)
  [[ $n == "$1" ]] && ok "ping count $1" || bad "ping count $n, want $1"
}
expect_statuses() {
  local n; n=$(count_status)
  [[ $n == "$1" ]] && ok "status reads $1" || bad "status reads $n, want $1"
}
expect_file()   { [[ -f $1 ]] && ok "exists: ${1:t}" || bad "missing file: $1"; }
expect_nofile() { [[ -f $1 ]] && bad "should not exist: $1" || ok "absent: ${1:t}"; }
expect_stderr_empty() {
  if [[ -s $SBX/stderr.txt ]]; then
    bad "stderr not empty: $(head -c 200 "$SBX/stderr.txt")"
  else
    ok "stderr empty"
  fi
}

# --- 1. lid forced closed ---------------------------------------------------

start_case "01 lid closed"
LID=closed run
expect_rc 0
expect_log "Skipped: MacBook lid is closed"
expect_pings 0
expect_statuses 0
expect_stderr_empty

# --- 2. lid open, five-hour window already active ---------------------------

start_case "02 window already active"
mk_status "$SBX/status.1.json" true 41 12000 20
LID=open run
expect_rc 0
expect_statuses 1
expect_pings 0
expect_log "skipped: window active until"
expect_nofile "$ROOT/run/last-success"

# --- 2b. window anchored but zero utilization (regression) ------------------
# A minimal Haiku warm-up leaves used_percent at 0.0, so limitping reports
# active=false for a window that is genuinely running. Keying the skip decision
# off `active` would re-ping every five minutes.

start_case "02b anchored window with zero utilization"
mk_status "$SBX/status.1.json" false 0 17400 5
LID=open run
expect_rc 0
expect_statuses 1
expect_pings 0
expect_log "skipped: window active until"

# --- 3. inactive window -> exactly one ping, verified -----------------------

start_case "03 inactive window pings once"
LID=open run
expect_rc 0
expect_pings 1
expect_statuses 2
expect_log "trigger started"
expect_log "verification succeeded"
expect_log "used 0.0%"
expect_file "$ROOT/run/last-success"
expect_file "$ROOT/run/last-attempt"
expect_file "$ROOT/run/last-trigger-at"
/usr/bin/grep -qF "PING_CWD=$ROOT/run/workdir" "$CALLS" \
  && ok "ping ran in the dedicated workdir" || bad "ping did not run in workdir"
/usr/bin/grep -qF "PING_XDG=$ROOT/config" "$CALLS" \
  && ok "ping used the private XDG_CONFIG_HOME" || bad "ping used wrong XDG_CONFIG_HOME"
/usr/bin/grep -qF "PING_HISTFLAG=1" "$CALLS" \
  && ok "CLAUDE_CODE_SKIP_PROMPT_HISTORY=1 set" || bad "prompt-history flag not set"
/usr/bin/grep -q '^limitping ping$' "$CALLS" \
  && bad "unqualified 'limitping ping' was used" || ok "ping is provider-qualified"

# --- 4. weekly usage at/above threshold -------------------------------------

start_case "04 weekly threshold"
mk_status "$SBX/status.1.json" false 0 -600 99
LID=open run
expect_rc 0
expect_pings 0
expect_log "skipped: weekly threshold reached"

# Missing weekly data must never be interpreted as 0% usage.
start_case "04b missing weekly usage fails closed"
/usr/bin/plutil -remove '0.weekly.used_percent' "$SBX/status.1.json"
LID=open run
expect_rc 4
expect_pings 0
expect_log "weekly.used_percent missing or unparseable"

# A malformed reset timestamp must not be interpreted as an inactive window.
start_case "04c malformed reset time fails closed"
/usr/bin/plutil -replace '0.five_hour.resets_at' -string 'not-a-time' "$SBX/status.1.json"
LID=open run
expect_rc 4
expect_pings 0
expect_log "five_hour.resets_at is unparseable"

# --- 5. status command failure ----------------------------------------------

start_case "05 status failure"
print -r -- 1 > "$SBX/status.1.rc"
: > "$SBX/status.1.json"
LID=open run
expect_rc 4
expect_pings 0
expect_log "status endpoint error"
expect_nofile "$ROOT/run/last-attempt"
expect_nofile "$ROOT/run/last-success"
# A transient status failure must be retried on the next scheduled run. It did
# not send a request, so the failed-trigger cooldown must not apply.
LID=open run
expect_rc 4
expect_statuses 2
expect_nolog "cooldown"
expect_pings 0

# --- 6. ping failure then cooldown ------------------------------------------

start_case "06 ping failure and cooldown"
LID=open run "FAKE_PING_RC=1"
expect_rc 5
expect_pings 1
expect_log "trigger failed"
expect_nofile "$ROOT/run/last-success"
expect_nofile "$ROOT/run/last-trigger-at"
expect_file "$ROOT/run/last-attempt"
/bin/rm -f -- "$SBX/status.count"
LID=open run
expect_rc 0
expect_log "skipped: failed-trigger cooldown"
expect_pings 1

# --- 7. delayed verification self-heals -------------------------------------

start_case "07 delayed verification"
mk_status "$SBX/status.2.json" false 0 -600 5
LID=open run
expect_rc 0
expect_pings 1
expect_log "verification pending"
expect_nofile "$ROOT/run/last-success"
expect_file "$ROOT/run/last-trigger-at"

# The next scheduled check still sees stale/inactive data. It must not send a
# duplicate request and must not mislabel the successful trigger as a failure.
/bin/rm -f -- "$SBX/status.count"
LID=open run
expect_rc 0
expect_pings 1
expect_log "successful trigger awaiting or retaining verification"

# Once the endpoint catches up, the next scheduled check records success
# without issuing another model request.
mk_status "$SBX/status.1.json" false 0 17400 5
/bin/rm -f -- "$SBX/status.count"
LID=open run
expect_rc 0
expect_pings 1
expect_log "delayed verification reconciled"
expect_file "$ROOT/run/last-success"

# --- 7b. Wednesday reset alignment -----------------------------------------

start_case "07b Wednesday before first slot"
LID=open run \
  "CLAUDE_WARMUP_TEST_ALIGNMENT_ENABLED=1" \
  "CLAUDE_WARMUP_TEST_WEEKDAY=3" \
  "CLAUDE_WARMUP_TEST_SECONDS_SINCE_MIDNIGHT=23400"
expect_rc 0
expect_pings 0
expect_log "Wednesday alignment allows new windows only"

start_case "07c Wednesday first slot"
LID=open run \
  "CLAUDE_WARMUP_TEST_ALIGNMENT_ENABLED=1" \
  "CLAUDE_WARMUP_TEST_WEEKDAY=3" \
  "CLAUDE_WARMUP_TEST_SECONDS_SINCE_MIDNIGHT=25200"
expect_rc 0
expect_pings 1
expect_log "verification succeeded"

start_case "07d Wednesday closed lid on AC"
LID=closed run \
  "CLAUDE_WARMUP_TEST_ALIGNMENT_ENABLED=1" \
  "CLAUDE_WARMUP_TEST_ALLOW_CLOSED_LID_ON_AC=1" \
  "CLAUDE_WARMUP_TEST_WEEKDAY=3" \
  "CLAUDE_WARMUP_TEST_SECONDS_SINCE_MIDNIGHT=43500" \
  "CLAUDE_WARMUP_TEST_POWER_SOURCE=AC"
expect_rc 0
expect_pings 1
expect_log "closed; Wednesday alignment permits this AC-powered scheduled slot"

start_case "07e Wednesday closed lid on battery"
LID=closed run \
  "CLAUDE_WARMUP_TEST_ALIGNMENT_ENABLED=1" \
  "CLAUDE_WARMUP_TEST_ALLOW_CLOSED_LID_ON_AC=1" \
  "CLAUDE_WARMUP_TEST_WEEKDAY=3" \
  "CLAUDE_WARMUP_TEST_SECONDS_SINCE_MIDNIGHT=43500" \
  "CLAUDE_WARMUP_TEST_POWER_SOURCE=Battery"
expect_rc 0
expect_statuses 0
expect_pings 0
expect_log "requires AC power"

start_case "07f Wednesday after final slot"
LID=open run \
  "CLAUDE_WARMUP_TEST_ALIGNMENT_ENABLED=1" \
  "CLAUDE_WARMUP_TEST_WEEKDAY=3" \
  "CLAUDE_WARMUP_TEST_SECONDS_SINCE_MIDNIGHT=61500"
expect_rc 0
expect_pings 0
expect_log "Wednesday alignment allows new windows only"

start_case "07g other weekdays stay unrestricted"
LID=open run \
  "CLAUDE_WARMUP_TEST_ALIGNMENT_ENABLED=1" \
  "CLAUDE_WARMUP_TEST_WEEKDAY=2" \
  "CLAUDE_WARMUP_TEST_SECONDS_SINCE_MIDNIGHT=23400"
expect_rc 0
expect_pings 1
expect_log "verification succeeded"

# --- 8. concurrency ---------------------------------------------------------

start_case "08 concurrent executions"
# 8a: a live lock owner blocks a second checker
sleep 30 &
HOLDER=$!
mkdir -p "$ROOT/run/lock/warmup.lock"
print -r -- "$HOLDER" > "$ROOT/run/lock/warmup.lock/pid"
LID=open run
expect_rc 0
expect_log "Skipped: another check is running"
expect_pings 0
kill "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null
rm -rf "$ROOT/run/lock/warmup.lock"

# 8b: two real runs in parallel -> only one performs the trigger
start_case "08b parallel runs trigger once"
LID=open run "FAKE_PING_SLEEP=4" &
P1=$!
sleep 1
LID=open run
RC2=$RC
wait $P1
sleep 1
expect_pings 1
[[ $RC2 == 0 ]] && ok "second concurrent run exited 0" || bad "second run exit $RC2"
expect_log "Skipped: another check is running"

# 8c: a stale lock (dead owner) is reclaimed
start_case "08c stale lock reclaimed"
mkdir -p "$ROOT/run/lock/warmup.lock"
print -r -- 999999 > "$ROOT/run/lock/warmup.lock/pid"
LID=open run
expect_rc 0
expect_log "stale lock reclaimed"
expect_pings 1

# --- 9. paths with spaces ---------------------------------------------------

start_case "09 paths with spaces"
[[ $ROOT == *" "* && $LOGS == *" "* && $FAKEBIN == *" "* ]] \
  && ok "sandbox paths contain spaces" || bad "sandbox paths lack spaces"
LID=open run
expect_rc 0
expect_pings 1
expect_log "verification succeeded"
expect_stderr_empty

# --- 10. missing binary / expired authentication ----------------------------

start_case "10a missing claude binary"
rm -f "$FAKEBIN/claude"
LID=open run
expect_rc 3
expect_pings 0
expect_log "claude is missing or not executable"

start_case "10b missing limitping binary"
rm -f "$ROOT/bin/limitping"
LID=open run
expect_rc 3
expect_pings 0
expect_log "limitping is missing or not executable"

start_case "10c expired authentication"
cat > "$SBX/auth.json" <<'JSON'
{ "loggedIn": false }
JSON
LID=open run
expect_rc 3
expect_pings 0
expect_log "not logged in to Claude Code"

start_case "10d auth command fails"
print -r -- 1 > "$SBX/auth.rc"
: > "$SBX/auth.json"
LID=open run
expect_rc 3
expect_pings 0
expect_log "authentication error"

start_case "10e third-party provider reported by auth status"
cat > "$SBX/auth.json" <<'JSON'
{ "loggedIn": true, "authMethod": "third_party", "apiProvider": "bedrock" }
JSON
LID=open run
expect_rc 3
expect_pings 0
expect_log "not the first-party subscription"

# --- 11. API key present ----------------------------------------------------

start_case "11a ANTHROPIC_API_KEY set"
LID=open run "ANTHROPIC_API_KEY=dummy-api-key"
expect_rc 3
expect_pings 0
expect_log "non-subscription provider override active"
expect_log "ANTHROPIC_API_KEY"
expect_nolog "dummy-api-key"
/usr/bin/grep -q '^claude auth' "$CALLS" \
  && bad "claude was invoked despite an API key" || ok "claude never invoked"

start_case "11b apiKeySource reported by auth status"
cat > "$SBX/auth.json" <<'JSON'
{ "loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty",
  "apiKeySource": "ANTHROPIC_API_KEY", "subscriptionType": null }
JSON
LID=open run
expect_rc 3
expect_pings 0
expect_log "API key in use"

start_case "11c ANTHROPIC_BASE_URL set"
LID=open run "ANTHROPIC_BASE_URL=https://example.invalid"
expect_rc 3
expect_pings 0
expect_log "ANTHROPIC_BASE_URL"

start_case "11d CLAUDE_CODE_USE_BEDROCK set"
LID=open run "CLAUDE_CODE_USE_BEDROCK=1"
expect_rc 3
expect_pings 0
expect_log "CLAUDE_CODE_USE_BEDROCK"

start_case "11e apiKeyHelper configured in settings"
print -r -- '{"apiKeyHelper":"/bin/echo key"}' > "$FAKEHOME/.claude/settings.json"
LID=open run
expect_rc 3
expect_pings 0
expect_log "apiKeyHelper configured"

# --- 12. log rotation -------------------------------------------------------

start_case "12 log rotation"
integer i
for i in {1..7}; do
  mk_status "$SBX/status.1.json" true 10 9000 5   # cheap skip path
  /usr/bin/head -c 5000 /dev/zero | /usr/bin/tr '\0' 'x' >> "$LOG"
  LID=open run "CLAUDE_WARMUP_TEST_LOG_MAX_BYTES=4096"
done
expect_file "$LOG"
expect_file "$LOG.1"
expect_file "$LOG.5"
expect_nofile "$LOG.6"

# --- 13. lid override branches + real ioreg -------------------------------

start_case "13a lid override reports open"
LID=open run
expect_rc 0
expect_log "lid state: open"

start_case "13b lid state absent treated as desktop"
LID=absent run
expect_rc 0
expect_log "AppleClamshellState absent"
expect_pings 1

start_case "13c real ioreg lid state observed"
REAL=$(/usr/sbin/ioreg -r -k AppleClamshellState 2>/dev/null | /usr/bin/grep '"AppleClamshellState"' || true)
if [[ -n $REAL ]]; then
  ok "real ioreg reports:${REAL}"
else
  ok "real ioreg reports: AppleClamshellState absent (desktop)"
fi

# --- summary ----------------------------------------------------------------

print -r -- ""
print -r -- "================================"
print -r -- "passed: $PASS   failed: $FAIL"
if (( FAIL )); then
  print -r -- ""
  print -r -- "failures:"
  local f
  for f in $FAILURES; do print -r -- "  - $f"; done
  print -r -- ""
  print -r -- "sandbox kept at: $SPACED"
  exit 1
fi
rm -rf "$TMPBASE"
exit 0
