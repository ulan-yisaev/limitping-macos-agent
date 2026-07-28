#!/bin/zsh

emulate -L zsh
set -euo pipefail

REPO_DIR=${0:A:h:h}
TMP_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/limitping-dependency-tests.XXXXXX")
trap '/bin/rm -rf -- "$TMP_ROOT"' EXIT INT TERM

value() {
  /usr/bin/sed -n "s/^$1=//p" "$REPO_DIR/dependency.env" | /usr/bin/head -n 1
}

REPOSITORY=$(value CCLIMITPING_REPOSITORY)
COMMIT=$(value CCLIMITPING_COMMIT)

git clone --quiet --filter=blob:none "$REPOSITORY" "$TMP_ROOT/CCLimitPing"
git -C "$TMP_ROOT/CCLimitPing" checkout --quiet --detach "$COMMIT"
[[ $(git -C "$TMP_ROOT/CCLimitPing" rev-parse HEAD) == $COMMIT ]]

(
  cd "$TMP_ROOT/CCLimitPing"
  export GOTOOLCHAIN=local
  [[ -z $(gofmt -l .) ]]
  go test ./...
  go vet ./...
  go build -trimpath -o "$TMP_ROOT/limitping" ./cmd/limitping
)

/bin/mkdir -p "$TMP_ROOT/config/limitping"
/bin/cp "$REPO_DIR/templates/config.toml" "$TMP_ROOT/config/limitping/config.toml"
/bin/zsh "$REPO_DIR/tests/check-dryrun.sh" "$TMP_ROOT/limitping" "$TMP_ROOT/config"
