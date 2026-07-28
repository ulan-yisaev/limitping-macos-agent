# Security model

## Protected outcomes

The automation is designed to avoid:

- requests while a MacBook lid is closed;
- intentionally waking or holding the Mac awake;
- API-key or cloud-provider billing;
- duplicate real requests after ambiguous verification;
- loading project instructions, tools, MCP servers, or browser integration;
- leaving a hung interactive Claude process behind;
- exposing credentials in logs.

## Trust boundary

The installer builds the pinned CCLimitPing commit from source. CCLimitPing and
Claude Code remain trusted dependencies. The usage endpoint consumed by
CCLimitPing is unofficial, so all missing or malformed scheduling data fails
closed.

The wrapper validates both environment routing variables and the structured
result of `claude auth status --json`. The known-variable list is defense in
depth and may need updates when Claude Code adds a provider. A provider not
reported accurately by the CLI could fall outside this model.

The wrapper never prints credential values or a complete environment. Child
output is stripped of terminal control characters, collapsed, and truncated
before logging.

## Scheduling and machine state

`StartInterval=300` does not create a power-management wake event. Intervals
missed during sleep are not replayed as a model-request burst. The next ordinary
check after wake reads current usage before deciding.

`AppleClamshellState=Yes` is an unconditional skip, including powered
clamshell mode. If the property is absent, the host is treated as a desktop or
unsupported device.

No claim is made that a shell process already running at the exact instant the
lid closes can be synchronously revoked. The lid is checked before any
authentication, status, or trigger command.

## Request boundary

The request is interactive and positional. It uses Haiku, safe mode, no tools,
strict empty MCP configuration, a minimal system prompt, and no browser
integration. `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` requests transcript
suppression.

The wrapper rejects known API-key, base-URL, Bedrock, Vertex, Foundry, gateway,
Mantle, and Anthropic-on-AWS overrides. It also rejects `apiKeyHelper` in the
two standard user settings files and any API key source reported by auth
status.

## Local data

The installation stores:

- a private CCLimitPing binary and configuration;
- timestamps for the last attempt, verified success, and successful trigger;
- a dedicated empty work directory;
- rotating operational logs.

It does not copy OAuth credentials, Keychain entries, Claude transcripts, or
global Claude settings. The uninstaller keeps logs so removal does not
unexpectedly destroy diagnostic data.

## Limitations

- Shell guards and static audits are defense in depth, not formal verification.
- The project cannot make the unofficial usage endpoint stable.
- Claude Code flags and authentication fields may evolve.
- Physical lid, sleep/wake, and login-cycle behavior should be tested on the
  target hardware.
- A real warm-up consumes usage and may have policy implications for managed
  accounts. Confirm that use is allowed for the account being automated.
