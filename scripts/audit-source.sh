#!/bin/zsh

emulate -L zsh
set -euo pipefail

REPO_DIR=${0:A:h:h}
cd "$REPO_DIR"

typeset -a files
if [[ -d .git ]]; then
  files=(${(f)"$(git ls-files)"})
else
  files=(${(f)"$(/usr/bin/find . -type f ! -path './.git/*' | /usr/bin/sed 's|^\./||')"})
fi

(( ${#files} > 0 )) || {
  print -u2 -r -- "audit: no source files found"
  exit 1
}

FAIL=0

check_pattern() {
  local label="$1" pattern="$2"
  local hits
  hits=$(/usr/bin/grep -nEI "$pattern" $files 2>/dev/null || true)
  if [[ -n $hits ]]; then
    print -u2 -r -- "audit: $label"
    print -u2 -r -- "$hits"
    FAIL=1
  fi
}

check_pattern "absolute macOS home path found" '/Users/[A-Za-z0-9._-]+'
check_pattern "private-key marker found" 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
check_pattern "GitHub token-like value found" 'gh[opusr]_[A-Za-z0-9]{20,}'
check_pattern "Anthropic key-like value found" 'sk-ant-[A-Za-z0-9_-]{10,}'
check_pattern "generic bearer token found" 'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'

large=$(/usr/bin/find . -type f ! -path './.git/*' -size +1M -print)
if [[ -n $large ]]; then
  print -u2 -r -- "audit: unexpectedly large files found"
  print -u2 -r -- "$large"
  FAIL=1
fi

for forbidden in '*.log' '*.jsonl' '*.pem' '*.key' '.env' '.DS_Store'; do
  hits=$(/usr/bin/find . -type f -name "$forbidden" ! -path './.git/*' -print)
  if [[ -n $hits ]]; then
    print -u2 -r -- "audit: forbidden artifact found ($forbidden)"
    print -u2 -r -- "$hits"
    FAIL=1
  fi
done

(( FAIL == 0 )) || exit 1
print -r -- "source privacy and secret audit passed (${#files} files)"
