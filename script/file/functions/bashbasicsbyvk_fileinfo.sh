# bashbasicsbyvk_fileinfo.sh — the `i-` command: information about FILES (never folders).
#
#   i-1,3   i-1-5   i-a   i-a-2     (the same item lists as eb- z- up-)      i-  alone asks which files
#
#   Per file it shows:
#     path · binary bytes (the size written in base 2) · decimal bytes (the exact size) · human readable (1024- and 1000-based)
#     word count · characters with spaces (every character, line ends included) · characters without spaces (no space, tab or line end)
#     total lines (a last line without a line end counts) · file extension · date created · date modified
#   The info is PRINTED first; only then it asks: save it in Excel / copy it to the clipboard (_eb_finish, shared with eb-).
#   Date created is "not available" where the file system does not keep it (many Android / Linux file systems).
#   Text is read as UTF-8 (a byte that is not valid counts as one character); a binary file is counted the same way.
#
#   Needs: bashbasicsbyvk_staging_helpers.sh (_sp_files_only), bashbasicsbyvk_exactbytes.sh (_eb_unit _eb_commas _eb_finish).

# _fi_scan FILE...  -> TSV on stdout, one line per file:
#   path  bytes  binary  words  chars  chars_nospace  lines  ext  created  modified
_fi_scan() {
  python3 - "$@" <<'PYEOF'
import os, subprocess, sys, time

def stamp(t):
    return time.strftime("%Y-%m-%d %H:%M:%S %z", time.localtime(t))

def created(p, st):
    b = getattr(st, "st_birthtime", None)
    if b is None:
        try:
            out = subprocess.run(["stat", "-c", "%W", "--", p], capture_output=True, text=True, timeout=5).stdout.strip()
            b = int(out) if out.lstrip("-").isdigit() else 0
        except Exception:
            b = 0
    return stamp(b) if b and b > 0 else "not available"

for p in sys.argv[1:]:
    st = os.stat(p)
    words = chars = nosp = lines = 0
    try:
        with open(p, "r", encoding="utf-8", errors="replace", newline="") as f:
            for line in f:
                lines += 1
                words += len(line.split())
                chars += len(line)
                nosp += len("".join(line.split()))
    except OSError:
        pass
    ext = os.path.splitext(p)[1].lstrip(".")
    row = [p, st.st_size, bin(st.st_size), words, chars, nosp, lines, ext or "(none)", created(p, st), stamp(st.st_mtime)]
    print("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in row))
PYEOF
}

# _fi_build  -> _EB_TEXT (what is printed and copied), _EB_TSV (the Excel rows).  Reads the TSV of _fi_scan on stdin.
_fi_build() {
  local n=0 p b bin w c ns l ext cr mo name bi da total=0
  local _EB_C _EB_U
  _EB_TEXT=""; _EB_TSV=""
  while IFS=$'\t' read -r p b bin w c ns l ext cr mo; do
    [ -z "$p" ] && continue
    n=$(( n + 1 )); total=$(( total + b )); name="${p##*/}"
    _eb_unit "$b" 1024; bi="$_EB_U"; _eb_unit "$b" 1000; da="$_EB_U"
    _EB_TEXT+="$n) $name"$'\n'
    _EB_TEXT+="   Path                   $p"$'\n'
    _EB_TEXT+="   Binary bytes           $bin"$'\n'
    _eb_commas "$b"
    _EB_TEXT+="   Decimal bytes          $_EB_C B"$'\n'
    _EB_TEXT+="   Human readable         $bi  /  $da"$'\n'
    _eb_commas "$w"; _EB_TEXT+="   Word count             $_EB_C"$'\n'
    _eb_commas "$c"; _EB_TEXT+="   Characters (spaces)    $_EB_C"$'\n'
    _eb_commas "$ns"; _EB_TEXT+="   Characters (no spaces) $_EB_C"$'\n'
    _eb_commas "$l"; _EB_TEXT+="   Total lines            $_EB_C"$'\n'
    _EB_TEXT+="   Extension              $ext"$'\n'
    _EB_TEXT+="   Date created           $cr"$'\n'
    _EB_TEXT+="   Date modified          $mo"$'\n\n'
    _EB_TSV+="$n"$'\t'"$name"$'\t'"$p"$'\t'"$bin"$'\t'"$b"$'\t'"$bi / $da"$'\t'"$w"$'\t'"$c"$'\t'"$ns"$'\t'"$l"$'\t'"$ext"$'\t'"$cr"$'\t'"$mo"$'\n'
  done
  _EB_TEXT="${_EB_TEXT%$'\n\n'}"
  [ "$n" -gt 1 ] && { _eb_commas "$total"; _EB_TEXT+=$'\n\n'"Total ($n files)  $_EB_C B"; }
  return 0
}

# i-<items>
handle_info() {
  local raw="$1"
  _sp_files_only "${raw#i-}" "i-" "INFO" "info can't be used on" || return 0
  local _EB_TEXT _EB_TSV
  local rows; rows="$(_fi_scan "${sp_files[@]}")"
  _fi_build <<< "$rows"
  echo
  echo "ℹ️  File info"
  printf '%s\n' "$_EB_TEXT"
  echo
  local _EB_HEAD _EB_SHEET="file info" _EB_NUMS="5,7,8,9,10" _EB_BOLDLAST=0
  printf -v _EB_HEAD 'No.\tName\tPath\tBinary bytes\tDecimal bytes\tHuman readable\tWord count\tCharacters (with spaces)\tCharacters (no spaces)\tTotal lines\tExtension\tDate created\tDate modified'
  _eb_finish "File info" "ℹ️" "file_info" "i-"
  return 0
}
