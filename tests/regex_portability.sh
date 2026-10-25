#!/usr/bin/env bash
# Lints the shell scripts for regex features that work on Linux (glibc) but break on Android/Termux (bionic, BSD regcomp):
#   1. {n,m} repeat counts above 255 (RE_DUP_MAX=255 there)  -> "invalid repetition count(s)"
#   2. backslash classes (\s \w \d \b) inside [[ =~ ]]: bash eats the backslash, so they match a literal letter everywhere
# Usage: bash tests/regex_portability.sh [script-dir]   (exit 1 when something is found)
dir="${1:-$(dirname "$0")/../script}"
fail=0
while IFS= read -r hit; do echo "REPEAT>255: $hit"; fail=1; done < <(
  grep -rnE '=~|_RE=|rx=' "$dir" 2>/dev/null \
  | grep -E '\{([0-9]+,)?(25[6-9]|2[6-9][0-9]|[3-9][0-9]{2}|[0-9]{4,})\}|\{(25[6-9]|2[6-9][0-9]|[3-9][0-9]{2}|[0-9]{4,}),[0-9]*\}')
while IFS= read -r hit; do echo "BACKSLASH-CLASS in =~: $hit"; fail=1; done < <(
  grep -rnE '=~[^|&]*\\[sSwWdDbB]' "$dir" 2>/dev/null)
while IFS= read -r hit; do echo "EMPTY-ALTERNATIVE in =~ (Termux: empty (sub)expression; write (x)? instead of (x|)): $hit"; fail=1; done < <(
  grep -rnE '=~.*(\(\||\|\)|\|\|)' "$dir" 2>/dev/null | grep -vE '=~[^#]*\|\|[[:space:]]*(return|echo|\[|\{|continue|[a-z_]+ )' | grep -E '=~ *\^?[^ ]*(\(\||\|\))')
[ "$fail" = 0 ] && echo "regex portability: OK" || echo "regex portability: FAILED"
exit "$fail"
