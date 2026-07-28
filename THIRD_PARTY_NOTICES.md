# Third-party notices

## CCLimitPing

This project uses [CCLimitPing](https://github.com/wavever/CCLimitPing) as its
usage-status and interactive PTY engine.

- Version: 0.8.0
- Pinned commit: `5fa254879ab39beb88720594e32dffa9b7991067`
- License: MIT

The CCLimitPing source and binary are not committed to this repository. The
installer clones the pinned source, runs its tests and vet checks, and builds a
private local binary. See CCLimitPing's repository for its copyright notice and
full license text.

## Reference projects

The design review also considered
[claude-autowake](https://github.com/1mshy/claude-autowake) and
[claude-usage-stager](https://github.com/HardHeadHackerHead/claude-usage-stager).
No source from claude-autowake was copied because the reviewed repository did
not include a license file. Claude Usage Stager is MIT-licensed; its operational
ideas informed testing and status ergonomics, but its source is not included.
