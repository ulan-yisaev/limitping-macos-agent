# Alternatives and design boundary

This comparison records the design review as of July 2026. Projects evolve;
check their current documentation before choosing.

## CCLimitPing

[CCLimitPing](https://github.com/wavever/CCLimitPing) already solves the hard
provider-level parts: reading Claude usage, detecting reset times, and driving
the interactive Claude Code terminal UI through a PTY. It supports more than
Claude and includes scheduler functionality.

This project intentionally depends on CCLimitPing instead of copying its Go
source. The separate layer exists to enforce one conservative macOS policy:

- do not wake the computer;
- do not invoke Claude with a closed MacBook lid;
- reject non-subscription routing;
- isolate configuration and the work directory;
- verify results and bound retries;
- make installation, logs, state, and removal predictable.

During integration testing, a minimal request produced a future
`five_hour.resets_at` while rounded utilization remained `0.0%`. CCLimitPing's
derived `active` value could therefore be false for an anchored window. The
wrapper uses a valid future reset timestamp as the primary window signal and
maintains a post-trigger duplicate-request floor. An upstream provider-specific
regression fix would still be valuable.

## claude-autowake

[claude-autowake](https://github.com/1mshy/claude-autowake) is a compact local
fixed-time solution. Its documented use of `pmset` and `caffeinate` is useful
when waking or holding the computer awake is desired. Those capabilities are
outside this project's permission boundary.

The reviewed repository did not include a license file, so no source was copied
or adapted.

## claude-warmup

[claude-warmup](https://github.com/vdsmon/claude-warmup) schedules remotely
through GitHub Actions. That is a reasonable fit for users who want cloud-based
scheduling and accept storing a credential in GitHub Secrets. This project
keeps execution and the signed-in subscription flow local.

## cwarm

[cwarm](https://github.com/wonderbyte/cwarm) emphasizes cron timing and
multi-account rotation. This project instead follows the actual reported window
state, applies an unconditional weekly threshold, and supports one local Claude
Code identity.

## Claude Usage Stager

[Claude Usage Stager](https://github.com/HardHeadHackerHead/claude-usage-stager)
offers broader cross-platform scheduler generation. This project reuses the
general virtues of dry runs, status commands, and fake-based tests while
choosing a narrower macOS LaunchAgent and lid-state policy.

## Choosing

Use this project when all of these are important:

- local subscription-backed Claude Code;
- no intentional waking;
- closed-lid suppression;
- fail-closed billing and provider checks;
- state-driven scheduling rather than fixed calendar times.

Choose an alternative when remote execution, forced wakes, multiple accounts,
non-macOS support, or multi-provider warming is the primary requirement.
