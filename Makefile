.PHONY: audit dependency-test lint test verify

lint:
	/bin/zsh -n install.sh uninstall.sh status.sh src/warmup-check.sh.in src/uninstall.sh.in tests/*.sh scripts/*.sh
	/usr/bin/plutil -lint templates/launchagent.plist.in

test:
	/bin/zsh tests/check-templates.sh
	/bin/zsh tests/run-tests.sh

audit:
	/bin/zsh scripts/audit-source.sh

dependency-test:
	/bin/zsh scripts/test-dependency.sh

verify: lint test audit dependency-test
