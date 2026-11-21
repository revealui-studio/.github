#!/usr/bin/env bash
# Fail when profile/README.md carries a retired Studio price, a retired
# public name, an em dash (U+2014), or a link to a repo that moved to the
# revealui-studio org but is still addressed under RevealUIStudio.
set -euo pipefail

# U+2014 as UTF-8 bytes e2 80 94. Bash $'\u2014' expands to the six
# characters \u2014 under LC_ALL=C, and a search for that text misses
# a real em dash (the check would pass).
em_dash=$'\xe2\x80\x94'

self_test() {
  local tmp bytes status output locale name utf8
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  printf '\xe2\x80\x94\n' > "$tmp/em.md"
  bytes=$(od -An -tx1 "$tmp/em.md" | tr -d ' \n' | tr 'A-F' 'a-f')
  if [[ "$bytes" != "e280940a" ]]; then
    echo "self-test failed: em dash sample bytes are ${bytes}, expected e280940a" >&2
    return 1
  fi

  # C is the locale where $'\u2014' fails open. Also run a UTF-8 locale
  # when the machine has one, so byte matching still hits there.
  local -a locales=(C)
  utf8=$(locale -a 2>/dev/null | awk 'BEGIN{IGNORECASE=1} $0 ~ /^C\.(utf8|utf-8)$/ {print; exit}')
  if [[ -n "$utf8" ]]; then
    locales+=("$utf8")
  fi

  for locale in "${locales[@]}"; do
    set +e
    output=$(LC_ALL="$locale" bash "$0" "$tmp/em.md" 2>&1)
    status=$?
    set -e
    if [[ "$status" -ne 1 ]]; then
      echo "self-test failed: em dash sample under LC_ALL=${locale} exited ${status}, expected 1" >&2
      printf '%s\n' "$output" >&2
      return 1
    fi
  done

  for name in 'Stage B' 'Domain pack' 'Proof Sprint' 'RevFleet' \
    'https://github.com/RevealUIStudio/revvault' 'npx skills add RevealUIStudio/revskills'; do
    printf '%s\n' "$name" > "$tmp/name.md"
    set +e
    output=$(LC_ALL=C bash "$0" "$tmp/name.md" 2>&1)
    status=$?
    set -e
    if [[ "$status" -ne 1 ]]; then
      echo "self-test failed: ${name} exited ${status}, expected 1" >&2
      printf '%s\n' "$output" >&2
      return 1
    fi
  done

  printf 'Domain add-on: $297\n' > "$tmp/clean.md"
  LC_ALL=C bash "$0" "$tmp/clean.md"
  echo "self-test ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

file="${1:-profile/README.md}"

if [[ ! -f "$file" ]]; then
  echo "error: missing $file" >&2
  exit 1
fi

fail=0

if LC_ALL=C grep -nF -- "$em_dash" "$file"; then
  echo "error: em dash (U+2014) in $file" >&2
  fail=1
fi

# Retired list prices. Current ladder uses $3,997, $14,500, $1,997, $2,497, $297.
if LC_ALL=C grep -nE '\$1,500|\$3,500|\$7,500|\$1500|\$3500|\$7500' "$file"; then
  echo "error: retired price in $file" >&2
  fail=1
fi

if LC_ALL=C grep -nF -e 'Stage B' -e 'Domain pack' -e 'Proof Sprint' -e 'RevFleet' -- "$file"; then
  echo "error: retired public name in $file" >&2
  fail=1
fi

# Repos already transferred to the revealui-studio org. GitHub redirects the
# old paths today, but a redirect breaks if a repo with the old name is ever
# created under RevealUIStudio. Add revealui here once it moves.
moved='(revvault|revskills|revkit|revcon|revdev|revmind|status|agency|revealui-template-[a-z-]+)'
if LC_ALL=C grep -nE "RevealUIStudio/${moved}([^a-z-]|$)" "$file"; then
  echo "error: link to a moved repo under RevealUIStudio in $file (use revealui-studio/)" >&2
  fail=1
fi

exit "$fail"
