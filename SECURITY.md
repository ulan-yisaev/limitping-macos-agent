# Security policy

## Supported version

Security fixes are applied to the current `main` branch. This initial
publication does not provide binary releases or an automatic updater.

## Reporting

Use GitHub's private security-advisory flow. Do not open a public issue
containing:

- API keys, OAuth or Keychain data;
- complete `claude auth status` output;
- raw usage JSON;
- usernames, hostnames, device identifiers, or absolute home paths;
- unreviewed warm-up logs or Claude configuration.

## Scope

Relevant reports include:

- a path that can trigger Claude with the lid closed;
- bypass of the subscription/provider guard;
- a duplicate-request path inside the five-hour safety floor;
- credential values written to logs;
- unsafe process cleanup or installation path handling;
- dependency-pin or source-verification weaknesses.

The unofficial usage endpoint being unavailable is expected to fail closed and
is not itself a vulnerability.
