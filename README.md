# limitping-macos-agent

A hardened, sleep-aware macOS LaunchAgent for
[CCLimitPing](https://github.com/wavever/CCLimitPing). It starts an inactive
Claude Code five-hour subscription window with one minimal interactive Haiku
request—without waking the Mac, running with the MacBook lid closed, or silently
falling back to API billing.

This project does not claim to invent Claude window warming and does not replace
CCLimitPing. CCLimitPing remains the usage-status and PTY trigger engine. This
repository packages the macOS machine-state, billing-safety, verification,
locking, timeout, and operational layers around it.

## Important limitations

- This does **not** increase Claude quota. It only changes when a five-hour
  window starts.
- A warm-up is a real model request and consumes a small amount of usage.
- CCLimitPing reads an unofficial usage endpoint. The endpoint may change.
- The wrapper fails closed when usage, authentication, or provider state cannot
  be validated.
- It does not schedule wakes and does not use `pmset` or `caffeinate`.
- It skips powered clamshell mode, even when the Mac remains awake on an
  external display.

## Why a separate project?

Several good projects already cover parts of this problem:

| Project | Primary scope | Why this package exists separately |
| --- | --- | --- |
| [CCLimitPing](https://github.com/wavever/CCLimitPing) | Usage detection and interactive PTY pings for several providers | It is the engine used here. This repository adds a focused macOS safety and deployment policy rather than forking its Go source. |
| [claude-autowake](https://github.com/1mshy/claude-autowake) | Fixed-time local scheduling | Its wake-oriented `pmset`/`caffeinate` design does not match the requirement to leave a sleeping Mac asleep. |
| [claude-warmup](https://github.com/vdsmon/claude-warmup) | Remote scheduled warming with GitHub Actions | This project intentionally stays local and uses the signed-in Claude Code CLI instead of placing a long-lived OAuth credential in CI. |
| [cwarm](https://github.com/wonderbyte/cwarm) | Cron schedules and multi-account rotation | This project is single-account, state-driven, weekly-cap-aware, and centered on machine and billing guards. |
| [Claude Usage Stager](https://github.com/HardHeadHackerHead/claude-usage-stager) | Cross-platform staging and scheduler generation | This project chooses a narrower macOS-only policy with lid detection and an isolated, source-built CCLimitPing dependency. |

These are requirements tradeoffs, not claims that the alternatives are
inferior. See [the detailed comparison](docs/alternatives.md).

## Safety model

Every five minutes, the LaunchAgent runs a lightweight wrapper that:

1. takes a non-blocking PID lock;
2. reads `AppleClamshellState` and exits when the lid is closed;
3. confirms the pinned binaries and a first-party `claude.ai` subscription;
4. rejects API keys, custom base URLs, Bedrock, Vertex, Foundry, and other known
   provider overrides;
5. reads only Claude usage through `limitping status --json`;
6. skips when the current window is active or weekly usage is at least 99%;
7. sends exactly `limitping ping claude`, with a 90-second outer timeout;
8. polls for a plausible future reset time before recording success.

After any successful PTY trigger, a local five-hour-and-one-minute safety floor
blocks another request even if the unofficial usage endpoint is stale during
verification.

The generated interactive command is:

```text
claude --model haiku --safe-mode --tools "" --strict-mcp-config --system-prompt "Reply only with OK." --no-chrome .
```

It deliberately contains no `-p`, `--print`, `--bare`, `--effort`, tool access,
MCP configuration, browser integration, or project customization.

See [the full security model](docs/security-model.md).

## Requirements

- macOS on Apple silicon or Intel;
- Claude Code installed and logged in to the intended subscription account;
- Git;
- Go 1.25.6 or newer, used to build the pinned CCLimitPing source;
- no active API-key or alternative-provider override for the scheduled job.

The installer never installs Go, never downloads an unverified prebuilt binary,
and never uses `curl | sh`.

## Install

Clone and inspect the repository first:

```bash
git clone https://github.com/ulan-yisaev/limitping-macos-agent.git
cd limitping-macos-agent
make lint
make test
make audit
```

Install the files without enabling the scheduler:

```bash
./install.sh
```

This clones CCLimitPing, checks out the commit in `dependency.env`, runs
`gofmt`, `go test`, and `go vet`, builds it with `-trimpath`, renders absolute
paths, validates the plist, and checks the exact dry-run command.

Enable only when you are ready for `RunAtLoad` to perform a real minimal request
if the five-hour window is inactive:

```bash
./install.sh --enable
```

## Operation

```bash
# concise LaunchAgent state and recent logs
./status.sh

# manual check; may send a request if every guard says a new window is due
/bin/zsh "$HOME/Library/Application Support/ClaudeWindowWarmup/run/warmup-check.sh"

# disable
launchctl bootout "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.local.claude-window-warmup.plist"
launchctl disable "gui/$(id -u)/com.local.claude-window-warmup"

# re-enable
launchctl enable "gui/$(id -u)/com.local.claude-window-warmup"
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.local.claude-window-warmup.plist"

# uninstall; logs are kept
./uninstall.sh
```

The primary log is:

```text
~/Library/Logs/ClaudeWindowWarmup/warmup.log
```

Do not paste raw logs into public issues without reviewing them.

## Testing

```bash
make lint
make test
make audit
make dependency-test
```

The wrapper suite uses fake Claude and CCLimitPing executables and covers lid
state, active and zero-utilization windows, weekly limits, malformed usage,
authentication and billing guards, trigger and verification failures, the
five-hour duplicate-request floor, concurrency, timeouts, path spaces, and log
rotation.

Tests do not perform real model requests. Physical lid, sleep/wake, login-cycle,
and subscription-surface checks remain manual hardware/account tests.

## License

The macOS wrapper and packaging in this repository are MIT-licensed. CCLimitPing
is a separate MIT-licensed dependency built locally from pinned source. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
