# Contributing

Contributions are welcome for focused macOS reliability, safety, documentation,
and test improvements.

Before opening a pull request:

```bash
make lint
make test
make audit
make dependency-test
```

Do not include real authentication output, usage responses, logs, home paths,
account metadata, session identifiers, or compiled binaries in commits or
issues. Use synthetic fixtures.

Changes to the CCLimitPing pin should include:

- the exact reviewed commit and release;
- license confirmation;
- upstream tests and vet results;
- dry-run proof that the interactive command contains the required flags and no
  print, bare, effort, or dangerous-permission flags.

Provider-specific changes should not silently alter behavior for Codex or other
CCLimitPing providers.
