#!/usr/bin/env bash
# Group by view: C helper vs Python twin vs the real viewport.
#   bash tests/group_view.sh
# Checks: (1) bvk-ls group == _py_group_python byte for byte, (2) the viewport really draws group
# headers (the old bug: grouped output was thrown away and a flat list drawn), (3) the highlighted
# row stays visible and on the right file while walking the list at several screen heights,
# (4) with no group levels the screen is the plain flat list.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E="$ROOT/script/file/engine"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

# ---- sample folder ----------------------------------------------------------
D="$T/d"; mkdir -p "$D/sub1" "$D/sub2"
mk() { touch -d "$2 12:00" "$D/$1"; }
mk a.pdf 2025-03-14; mk b.PDF 2025-03-20; mk c.txt 2025-03-14; mk d.jpg 2024-12-01; mk e.pdf 2024-12-31
mk noext 2025-04-02; mk f.txt 2024-12-01; mk x.shortcut 2025-03-14; mk .bashrc 2025-04-02; mk g.tar.gz 2023-07-09
touch -d "2025-03-14 10:00" "$D/sub1"; touch -d "2024-12-01 10:00" "$D/sub2"
export TZ=UTC
find "$D" -mindepth 1 -maxdepth 1 | sort > "$T/paths.txt"

# ---- (1) C == Python --------------------------------------------------------
awk '/^_py_group_python\(\) \{/{f=1;next} f&&/^python3 - "\$@" <<.PYEOF.$/{g=1;next} g&&/^PYEOF$/{exit} g{print}' \
  "$E/bashbasicsbyvk_displayer.sh" > "$T/twin.py"
[ -s "$T/twin.py" ] && ok "python twin extracted" || bad "python twin not found in displayer.sh"
if command -v cc >/dev/null 2>&1; then
  ( cd "$E/bvk-ls" && mkdir -p "$T/b" && cc -O2 -std=c11 -Iinclude -D_FILE_OFFSET_BITS=64 -D_DEFAULT_SOURCE -o "$T/bvk-ls" src/*.c -pthread ) 2>"$T/cc.log" \
    && ok "bvk-ls builds" || { bad "bvk-ls does not build"; cat "$T/cc.log"; }
  for lv in year,month,date,ext ext,year month date,ext; do
    for hl in 0 3 99; do
      "$T/bvk-ls" group "$T/paths.txt" "$lv" "$hl" "$T/c" > "$T/c.out" 2>/dev/null
      python3 "$T/twin.py" "$T/paths.txt" "$lv" "$hl" "$T/p" > "$T/p.out"
      same=1; for f in items rows irow; do cmp -s "$T/c.$f" "$T/p.$f" || same=0; done
      cmp -s "$T/c.out" "$T/p.out" || same=0
      [ $same = 1 ] && ok "C == Python  levels=$lv hl=$hl" || bad "C != Python  levels=$lv hl=$hl"
    done
  done
  mkdir -p "$T/bin"; cp "$T/bvk-ls" "$T/bin/"; export PATH="$T/bin:$PATH"
else
  echo "  skip C checks (no cc)"
fi

# ---- (2)-(4) the real viewport ---------------------------------------------
cat > "$T/h.sh" <<'EOS'
show_hidden_files=true; sort_mode=az; display_suffix_set=""; imaginary_mode=false
source "$E/bashbasicsbyvk_displayer.sh"; source "$E/bashbasicsbyvk_viewport.sh"
_vp_probe_size() { _vp_rows_now=${ROWS:-24}; _vp_cols_now=${COLS:-70}; }
_term_rows() { echo "${ROWS:-24}"; }
_resolve_display_parts_v() { _rdp_bn="${1##*/}"; [ -d "$1" ] && _rdp_icon="📁" || _rdp_icon="📄"; }
myhdr() { echo "hdr"; }; myftr() { echo "ftr"; }
_vp_header_fn=myhdr; _vp_footer_fn=myftr; _vp_input_fn=true; _vp_hl_fn=_vp_is_hl_single
group_view_levels=($LEVELS)
mapfile -t items < <(find "$D" -mindepth 1 -maxdepth 1 | sort)
_hl_index=0; _vp_start=1; _vp_cache_reset; _vp_prime_rows
_strip() { sed 's/\x1b\[?2026[hl]//g; s/\x1b\[?7[lh]//g; s/\r\x1b\[2K//g; s/\x1b\[[0-9;]*m//g'; }
EOS
run() { E="$E" D="$D" ROWS="${ROWS:-60}" LEVELS="$1" bash -c "source '$T/h.sh'; $2"; }

out="$(run "year month date ext" '_vp_build_chrome; _vp_geometry; _vp_ensure_visible 1; _vp_emit | _strip')"
grep -q "YEAR: 2025" <<<"$out" && grep -q "MONTH: 2025-Mar" <<<"$out" && grep -q "EXT: .pdf" <<<"$out" \
  && ok "viewport draws group headers" || { bad "viewport shows NO group headers"; echo "$out" | head -20; }
[ "$(grep -c "YEAR: 2025" <<<"$out")" = 1 ] && ok "one YEAR header per year (hierarchical)" || bad "YEAR header repeated"
st="$(run "year month date ext" 'echo "$_gv_on $_vp_R ${#items[@]}"')"
[ "$st" = "true 37 12" ] && ok "row map: $st" || bad "row map wrong: $st"

walk='bad=0
for hl in 1 2 3 4 5 6 7 8 9 10 11 12 11 10 9 8 7 6 5 4 3 2 1 12 6; do
  _hl_index=$hl; _vp_build_chrome; _vp_geometry; _vp_ensure_visible "$hl"
  scr="$(_vp_emit | sed "s/\x1b\[?2026[hl]//g; s/\x1b\[?7[lh]//g; s/\r\x1b\[2K//g")"
  nm="${items[hl-1]##*/}"
  printf "%s\n" "$scr" | grep $'"'"'\x1b\[1;7m'"'"' | grep -q -- "$nm" || { bad=1; echo "hl=$hl ($nm) not visible"; }
done; echo walk=$bad'
for R in 8 10 12 20 40; do
  r="$(ROWS=$R run "year month date ext" "$walk" | tail -1)"
  [ "$r" = "walk=0" ] && ok "highlight always visible (screen height $R)" || bad "highlight lost at height $R"
done

flat="$(run "" '_vp_build_chrome; _vp_geometry; _vp_ensure_visible 1; _vp_emit | _strip')"
grep -q "── " <<<"$flat" && bad "flat mode shows group headers" || ok "no levels -> plain flat list"

[ $fail = 0 ] && echo "ALL GOOD" || { echo "FAILURES"; exit 1; }
