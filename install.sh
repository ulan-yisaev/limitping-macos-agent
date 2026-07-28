#!/bin/zsh

emulate -L zsh
set -euo pipefail

REPO_DIR=${0:A:h}
ENABLE=0
LABEL='com.local.claude-window-warmup'

usage() {
  print -r -- "Usage: ./install.sh [--enable]"
  print -r -- ""
  print -r -- "Without --enable, installs and validates the files but leaves the"
  print -r -- "LaunchAgent disabled. --enable explicitly permits RunAtLoad, which"
  print -r -- "may send one minimal Claude request if no five-hour window is active."
}

die() {
  print -u2 -r -- "error: $*"
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --enable) ENABLE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $arg" ;;
  esac
done

[[ $(/usr/bin/uname -s) == Darwin ]] || die "this installer supports macOS only"
(( EUID != 0 )) || die "run as the target user, not with sudo"

USER_HOME=${HOME:-}
[[ -n $USER_HOME && -d $USER_HOME ]] || die "HOME is missing or not a directory"
USER_HOME=${USER_HOME:A}

GIT_BIN=$(whence -p git || true)
GO_BIN=$(whence -p go || true)
CLAUDE_BIN=$(whence -p claude || true)

[[ -x $GIT_BIN ]] || die "git is required"
if [[ ! -x $GO_BIN ]]; then
  if [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ]]; then
    die "Go is required to build the pinned source. Review and run: brew install go"
  fi
  die "Go 1.25.6 or newer is required; install it from an approved source"
fi
[[ -x $CLAUDE_BIN ]] || die "Claude Code was not found on PATH"

CLAUDE_BIN=${CLAUDE_BIN:A}
CLAUDE_BIN_DIR=${CLAUDE_BIN:h}
GOFMT_BIN="${GO_BIN:h}/gofmt"
[[ -x $GOFMT_BIN ]] || die "gofmt was not found next to the Go executable"

dependency_value() {
  /usr/bin/sed -n "s/^$1=//p" "$REPO_DIR/dependency.env" | /usr/bin/head -n 1
}

CCLIMITPING_REPOSITORY=$(dependency_value CCLIMITPING_REPOSITORY)
CCLIMITPING_COMMIT=$(dependency_value CCLIMITPING_COMMIT)
CCLIMITPING_VERSION=$(dependency_value CCLIMITPING_VERSION)
CCLIMITPING_LICENSE=$(dependency_value CCLIMITPING_LICENSE)

[[ $CCLIMITPING_COMMIT =~ '^[0-9a-f]{40}$' ]] \
  || die "dependency.env contains an invalid commit"

ROOT="$USER_HOME/Library/Application Support/ClaudeWindowWarmup"
LOG_DIR="$USER_HOME/Library/Logs/ClaudeWindowWarmup"
PLIST="$USER_HOME/Library/LaunchAgents/$LABEL.plist"
WARMUP_CHECK="$ROOT/run/warmup-check.sh"

TMP_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/limitping-macos-agent.XXXXXX")
trap '/bin/rm -rf -- "$TMP_ROOT"' EXIT INT TERM

print -r -- "Claude Code: $($CLAUDE_BIN --version)"
print -r -- "Go: $($GO_BIN version)"

typeset -a PROVIDER_OVERRIDE_VARS
PROVIDER_OVERRIDE_VARS=(
  ANTHROPIC_API_KEY
  ANTHROPIC_AUTH_TOKEN
  ANTHROPIC_BASE_URL
  ANTHROPIC_CUSTOM_HEADERS
  ANTHROPIC_AWS_API_KEY
  ANTHROPIC_BEDROCK_BASE_URL
  ANTHROPIC_VERTEX_BASE_URL
  ANTHROPIC_FOUNDRY_API_KEY
  ANTHROPIC_FOUNDRY_AUTH_TOKEN
  ANTHROPIC_FOUNDRY_BASE_URL
  AWS_BEARER_TOKEN_BEDROCK
  CLAUDE_CODE_USE_BEDROCK
  CLAUDE_CODE_USE_VERTEX
  CLAUDE_CODE_USE_FOUNDRY
  CLAUDE_CODE_USE_GATEWAY
  CLAUDE_CODE_USE_MANTLE
  CLAUDE_CODE_USE_ANTHROPIC_AWS
)

typeset -a override_hits
override_hits=()
for variable in $PROVIDER_OVERRIDE_VARS; do
  [[ -n ${(P)variable:-} ]] && override_hits+=("$variable")
done
(( ${#override_hits} == 0 )) \
  || die "non-subscription provider override active: ${(j:, :)override_hits}"

"$CLAUDE_BIN" auth status --json > "$TMP_ROOT/auth.json" \
  || die "claude auth status failed"

json_value() {
  /usr/bin/plutil -extract "$2" raw -o - -- "$1" 2>/dev/null || true
}

AUTH_LOGGED_IN=$(json_value "$TMP_ROOT/auth.json" loggedIn)
AUTH_METHOD=$(json_value "$TMP_ROOT/auth.json" authMethod)
AUTH_PROVIDER=$(json_value "$TMP_ROOT/auth.json" apiProvider)
AUTH_SUBSCRIPTION=$(json_value "$TMP_ROOT/auth.json" subscriptionType)
AUTH_KEY_SOURCE=$(json_value "$TMP_ROOT/auth.json" apiKeySource)

[[ $AUTH_LOGGED_IN == true ]] || die "Claude Code is not logged in"
[[ $AUTH_METHOD == claude.ai ]] || die "Claude Code is not using a claude.ai login"
[[ $AUTH_PROVIDER == firstParty ]] || die "Claude Code is not using the first-party provider"
[[ -n $AUTH_SUBSCRIPTION ]] || die "no Claude subscription is attached to this login"
[[ -z $AUTH_KEY_SOURCE ]] || die "Claude Code reports an API key source"

CLAUDE_HELP=$("$CLAUDE_BIN" --help)
for required_flag in \
  '--model' \
  '--safe-mode' \
  '--tools' \
  '--strict-mcp-config' \
  '--system-prompt' \
  '--no-chrome'
do
  [[ $CLAUDE_HELP == *"$required_flag"* ]] \
    || die "installed Claude Code does not support $required_flag"
done

print -r -- "Cloning CCLimitPing at pinned commit $CCLIMITPING_COMMIT"

"$GIT_BIN" clone --quiet --filter=blob:none "$CCLIMITPING_REPOSITORY" "$TMP_ROOT/CCLimitPing"
"$GIT_BIN" -C "$TMP_ROOT/CCLimitPing" checkout --quiet --detach "$CCLIMITPING_COMMIT"

ACTUAL_COMMIT=$("$GIT_BIN" -C "$TMP_ROOT/CCLimitPing" rev-parse HEAD)
[[ $ACTUAL_COMMIT == $CCLIMITPING_COMMIT ]] || die "checked-out dependency commit does not match the pin"

FORMAT_DIFF=$(cd "$TMP_ROOT/CCLimitPing" && "$GOFMT_BIN" -l .)
[[ -z $FORMAT_DIFF ]] || die "pinned CCLimitPing source is not gofmt-clean: $FORMAT_DIFF"

(
  cd "$TMP_ROOT/CCLimitPing"
  export GOTOOLCHAIN=local
  "$GO_BIN" test ./...
  "$GO_BIN" vet ./...
  "$GO_BIN" build -trimpath -o "$TMP_ROOT/limitping" ./cmd/limitping
)

sed_escape() {
  print -r -- "$1" | /usr/bin/sed 's/[\\&|]/\\&/g'
}

render_wrapper() {
  /usr/bin/sed \
    -e "s|@CWW_ROOT@|$(sed_escape "$ROOT")|g" \
    -e "s|@CWW_LOG_DIR@|$(sed_escape "$LOG_DIR")|g" \
    -e "s|@CWW_CLAUDE_BIN@|$(sed_escape "$CLAUDE_BIN")|g" \
    -e "s|@CWW_CLAUDE_PATH_DIR@|$(sed_escape "$CLAUDE_BIN_DIR")|g" \
    -e "s|@CWW_USER_HOME@|$(sed_escape "$USER_HOME")|g" \
    "$REPO_DIR/src/warmup-check.sh.in" > "$TMP_ROOT/warmup-check.sh"
}

render_uninstaller() {
  /usr/bin/sed \
    -e "s|@CWW_ROOT@|$(sed_escape "$ROOT")|g" \
    -e "s|@CWW_LOG_DIR@|$(sed_escape "$LOG_DIR")|g" \
    -e "s|@LAUNCH_AGENT_PLIST@|$(sed_escape "$PLIST")|g" \
    "$REPO_DIR/src/uninstall.sh.in" > "$TMP_ROOT/uninstall.sh"
}

render_plist() {
  /usr/bin/sed \
    -e "s|@WARMUP_CHECK@|$(sed_escape "$WARMUP_CHECK")|g" \
    -e "s|@LAUNCHD_STDOUT@|$(sed_escape "$LOG_DIR/launchd.stdout.log")|g" \
    -e "s|@LAUNCHD_STDERR@|$(sed_escape "$LOG_DIR/launchd.stderr.log")|g" \
    "$REPO_DIR/templates/launchagent.plist.in" > "$TMP_ROOT/$LABEL.plist"
}

render_wrapper
render_uninstaller
render_plist

/bin/zsh -n "$TMP_ROOT/warmup-check.sh" "$TMP_ROOT/uninstall.sh"
/usr/bin/plutil -lint "$TMP_ROOT/$LABEL.plist"
if /usr/bin/grep -Eq '@(CWW|WARMUP|LAUNCHD|LAUNCH_AGENT)_' \
  "$TMP_ROOT/warmup-check.sh" "$TMP_ROOT/uninstall.sh" "$TMP_ROOT/$LABEL.plist"; then
  die "an installation placeholder was not rendered"
fi

/bin/mkdir -p \
  "$ROOT/bin" \
  "$ROOT/config/limitping" \
  "$ROOT/run/workdir" \
  "$ROOT/run/lock" \
  "$LOG_DIR" \
  "${PLIST:h}"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true

/usr/bin/install -m 755 "$TMP_ROOT/limitping" "$ROOT/bin/limitping"
/usr/bin/install -m 755 "$TMP_ROOT/warmup-check.sh" "$WARMUP_CHECK"
/usr/bin/install -m 755 "$TMP_ROOT/uninstall.sh" "$ROOT/uninstall.sh"
/usr/bin/install -m 644 "$REPO_DIR/templates/config.toml" "$ROOT/config/limitping/config.toml"
/usr/bin/install -m 644 "$TMP_ROOT/$LABEL.plist" "$PLIST"
/usr/bin/touch "$LOG_DIR/warmup.log" "$LOG_DIR/launchd.stdout.log" "$LOG_DIR/launchd.stderr.log"

{
  print -r -- "repository=$CCLIMITPING_REPOSITORY"
  print -r -- "commit=$CCLIMITPING_COMMIT"
  print -r -- "version=$CCLIMITPING_VERSION"
  print -r -- "license=$CCLIMITPING_LICENSE"
  print -r -- "go_version=$($GO_BIN version)"
  print -r -- "built_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  print -r -- "build_command=go build -trimpath -o <private-bin>/limitping ./cmd/limitping"
} > "$ROOT/SOURCE_VERSION"

DRY_RUN=$(/usr/bin/env "XDG_CONFIG_HOME=$ROOT/config" "$ROOT/bin/limitping" ping claude --dry-run)
print -r -- "$DRY_RUN"
for forbidden in ' -p ' '--print' '--bare' '--effort' '--dangerously-skip-permissions'; do
  [[ $DRY_RUN != *"$forbidden"* ]] || die "unsafe flag in generated command: $forbidden"
done
for required in '--model haiku' '--safe-mode' '--tools ""' '--strict-mcp-config' '--no-chrome'; do
  [[ $DRY_RUN == *"$required"* ]] || die "required flag missing from generated command: $required"
done

if (( ENABLE )); then
  launchctl enable "gui/$(id -u)/$LABEL"
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  print -r -- "Installed and enabled $LABEL"
  print -r -- "RunAtLoad may send one minimal request when no five-hour window is active."
else
  launchctl disable "gui/$(id -u)/$LABEL"
  print -r -- "Installed but left disabled."
  print -r -- "Enable explicitly with: ./install.sh --enable"
fi

print -r -- "Installed binary: $ROOT/bin/limitping"
print -r -- "Log: $LOG_DIR/warmup.log"
