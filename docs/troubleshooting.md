# Troubleshooting

## The agent is not loaded

Run:

```bash
./status.sh
launchctl print-disabled "gui/$(id -u)"
```

The default installation is intentionally disabled. Run `./install.sh --enable`
when you are ready for `RunAtLoad` to make a request if one is due.

## Authentication error

Check:

```bash
claude auth status --text
```

Use the intended first-party subscription login. Remove API-key, custom
base-URL, or cloud-provider routing from the environment used by the job. Never
paste auth output or credential values into an issue.

## Status endpoint error

CCLimitPing's Claude usage endpoint is unofficial. The wrapper fails closed and
does not send a blind request. Check networking and try the read-only command:

```bash
XDG_CONFIG_HOME="$HOME/Library/Application Support/ClaudeWindowWarmup/config" \
  "$HOME/Library/Application Support/ClaudeWindowWarmup/bin/limitping" status --json
```

Review the JSON locally before sharing it.

## Recent successful trigger safety floor

This message means a prior PTY invocation returned success but verification may
have been stale. The wrapper conservatively refuses another real request for
five hours and one minute. Do not delete `last-trigger-at` merely to bypass the
guard.

## Lid state

Inspect the actual property:

```bash
/usr/sbin/ioreg -r -k AppleClamshellState
```

`Yes` always skips. The production plist never sets test overrides.

## Logs

```bash
tail -n 100 "$HOME/Library/Logs/ClaudeWindowWarmup/warmup.log"
```

Logs rotate at 2 MiB with five historical files. Review them for local metadata
before attaching any excerpt to a public report.
