# bashbasicsbyvk_extract.sh — the `xtr-` command: pull lines / words / characters / bytes OUT of FILES (never folders).
#
#   xtr-1,3   xtr-1-5   xtr-a   xtr-a-2     (the same item lists as eb- z- up-)      xtr-  alone asks which files
#
#   1. a folder in the pick is refused:  "docs, src are folders, which can't be extracted."
#   2. Extract what?   Lines · Words · Characters · Bytes
#   3. Lines / Words / Characters:  First n · Range · Last n · Random (how many) · Duplicate (all / a number) · Unique (all / a number)
#      Bytes:  First n · Last n · Random n  — then the unit (B, KB MB GB TB PB EB = 1000-based, KiB MiB GiB TiB PiB EiB = 1024-based)
#   4. The result is PRINTED (a preview when it is long), then: copy it · save it to a file · save it in Excel (not for bytes).
#
#   Meaning of the words used above:
#     Range      from..to, both counted, starting at 1.
#     Duplicate  a value that occurs MORE than once (listed once, with its count, in order of first appearance).
#     Unique     a value that occurs EXACTLY once.      "a number" = how many of them to list (the first n).
#     Random     n values picked at random (a Bytes "random n" is one block of n bytes starting at a random place).
#     Words      split on white space.   Characters = every UTF-8 character, white space included.
#   Several files: the same extraction runs on each file; a text result carries a "== name ==" line per file.
#
#   Needs: bashbasicsbyvk_staging_helpers.sh (_sp_files_only), bashbasicsbyvk_exactbytes.sh (_eb_commas _eb_save_sheet),
#          bashbasicsbyvk_choose.sh (_bvk_menu), bashbasicsbyvk_deps.sh (_dep_need), the copy command (clipboard).

# _xtr_ask_int VAR "Prompt: "   -> VAR = a whole number >= 1 ; rc 1 = backed out / not a number (message printed)
_xtr_ask_int() {
  local _v
  read -e -r -p "$2" _v || return 1
  [ "${_CM_ABORT:-0}" = 1 ] && return 1
  _v="${_v//[[:space:]]/}"; _v="${_v//,/}"
  if [[ ! "$_v" =~ ^[0-9]+$ ]] || [ "$_v" -lt 1 ]; then echo "🔴  Enter a whole number of 1 or more."; return 1; fi
  printf -v "$1" '%s' "$_v"
}

# _xtr_engine KIND MODE N N2 BASE FILE...   writes BASE.out (the result), BASE.tsv (Excel rows), prints the preview.
#   rc 0 ok · 1 error (message printed) · 3 nothing to extract
_xtr_engine() {
  python3 - "$@" <<'PYEOF'
import collections, itertools, os, random, sys
from decimal import Decimal, InvalidOperation

kind, mode, n_s, n2_s, base = sys.argv[1:6]
files = sys.argv[6:]
MULT = {"b": 1}
for i, u in enumerate(["kb", "mb", "gb", "tb", "pb", "eb"], 1):
    MULT[u] = 1000 ** i
for i, u in enumerate(["kib", "mib", "gib", "tib", "pib", "eib"], 1):
    MULT[u] = 1024 ** i
PREVIEW_ROWS, VAL_MAX, CELL_MAX = 40, 200, 32000

def vis(s):
    return s.replace("\t", "⇥").replace("\n", "↵").replace("\r", "⏎").replace(" ", "·") if kind == "chars" else s.replace("\t", "⇥").replace("\n", "↵").replace("\r", "⏎")

def units(p):
    if kind == "lines":
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                yield line.rstrip("\n")
    elif kind == "words":
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                yield from line.split()
    else:
        with open(p, "r", encoding="utf-8", errors="replace", newline="") as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                yield from chunk

def fmt(i):
    return f"{i:,}"

multi = len(files) > 1
total_rows = 0
tsv = open(base + ".tsv", "w", encoding="utf-8")
out = open(base + ".out", "wb")
try:
    if kind == "bytes":
        try:
            want = int(Decimal(n_s) * MULT[n2_s])
        except (InvalidOperation, KeyError):
            print("🔴  That is not a size."); sys.exit(1)
        if want < 1:
            print("🔴  That is less than one byte."); sys.exit(1)
        for p in files:
            size = os.path.getsize(p)
            take = min(want, size)
            if mode == "first":
                start = 0
            elif mode == "last":
                start = size - take
            else:
                start = random.randint(0, size - take) if size > take else 0
            with open(p, "rb") as f:
                f.seek(start)
                left = take
                head = b""
                while left > 0:
                    chunk = f.read(min(left, 1 << 20))
                    if not chunk:
                        break
                    if len(head) < 128:
                        head += chunk[:128 - len(head)]
                    out.write(chunk); left -= len(chunk)
            total_rows += take
            tsv.write("\t".join([os.path.basename(p), str(start + 1), str(take), f"bytes {start + 1:,} to {start + take:,}"]) + "\n")
            print(f"{os.path.basename(p)}: {take:,} bytes (from byte {start + 1:,} of {size:,})")
            for o in range(0, len(head), 16):
                row = head[o:o + 16]
                print("  %04x  %-47s  %s" % (o, " ".join("%02x" % b for b in row), "".join(chr(b) if 32 <= b < 127 else "." for b in row)))
            if take > len(head):
                print("  … (the copy / file has all of it)")
    else:
        sep = {"lines": "\n", "words": " ", "chars": ""}[kind]
        try:
            n = int(n_s) if n_s else None
            n2 = int(n2_s) if n2_s else None
        except ValueError:
            print("🔴  That is not a number."); sys.exit(1)
        for p in files:
            name = os.path.basename(p)
            it = enumerate(units(p), 1)
            counts = None
            if mode == "first":
                res = [(i, v, "") for i, v in itertools.islice(it, n)]
            elif mode == "range":
                if n2 < n:
                    print("🔴  The range ends before it starts."); sys.exit(1)
                res = [(i, v, "") for i, v in itertools.islice(it, n - 1, n2)]
            elif mode == "last":
                res = [(i, v, "") for i, v in collections.deque(it, maxlen=n)]
            elif mode == "random":
                pool = []
                for k, (i, v) in enumerate(it):
                    if k < n:
                        pool.append((i, v, ""))
                    else:
                        j = random.randint(0, k)
                        if j < n:
                            pool[j] = (i, v, "")
                random.shuffle(pool)
                res = pool
            else:
                seen = {}
                for i, v in it:
                    e = seen.get(v)
                    if e is None:
                        seen[v] = [i, 1]
                    else:
                        e[1] += 1
                want_dup = mode == "dup"
                res = [(e[0], v, e[1]) for v, e in seen.items() if (e[1] > 1) == want_dup]
                if n is not None:
                    res = res[:n]
            if multi:
                out.write(f"== {name} ==\n".encode())
            out.write((sep.join(v for _, v, _ in res) + ("\n" if kind == "lines" and res else "")).encode("utf-8", "replace"))
            if multi:
                out.write(b"\n")
            for i, v, c in res:
                tsv.write("\t".join([name, str(i), str(c), v.replace("\t", " ").replace("\n", " ").replace("\r", " ")[:CELL_MAX]]) + "\n")
            total_rows += len(res)
            print(f"{name}: {fmt(len(res))} result(s)")
            contiguous = kind == "chars" and mode in ("first", "range", "last")
            if contiguous:
                s = "".join(v for _, v, _ in res)
                print("  " + vis(s[:1000]) + (" …" if len(s) > 1000 else ""))
            else:
                for i, v, c in res[:PREVIEW_ROWS]:
                    v2 = vis(v)
                    if len(v2) > VAL_MAX:
                        v2 = v2[:VAL_MAX] + "…"
                    print(f"  {i:>8}  {v2}" + (f"   (x{c})" if c != "" else ""))
                if len(res) > PREVIEW_ROWS:
                    print(f"  … showing the first {PREVIEW_ROWS} of {fmt(len(res))}; the copy / file / Excel has all of them")
except OSError as e:
    print("🔴  " + str(e)); sys.exit(1)
finally:
    tsv.close(); out.close()
sys.exit(0 if total_rows else 3)
PYEOF
}

# xtr-<items>
handle_xtr() {
  local raw="$1" what mode sub n="" n2="" unit="" kindname dlabel=""
  _sp_files_only "${raw#xtr-}" "xtr-" "EXTRACT" "can't be extracted" || return 0

  _bvk_menu what -t "Extract" -i "✂️" -q "Extract what?" \
    "1:Lines" "2:Words" "3:Characters" "4:Bytes" || return 0
  [ "${_CM_ABORT:-0}" = 1 ] && return 0
  case "$what" in 1) kindname=lines ;; 2) kindname=words ;; 3) kindname=chars ;; 4) kindname=bytes ;; *) _bvk_invalid; return 0 ;; esac
  local noun="$kindname"; [ "$kindname" = chars ] && noun="characters"

  if [ "$kindname" = bytes ]; then
    _bvk_menu mode -t "Extract bytes" -i "✂️" -q "Which bytes?" "1:First n bytes" "2:Last n bytes" "3:Random n bytes" || return 0
    [ "${_CM_ABORT:-0}" = 1 ] && return 0
    case "$mode" in 1) mode=first ;; 2) mode=last ;; 3) mode=random ;; *) _bvk_invalid; return 0 ;; esac
    read -e -r -p "How many (a number, e.g. 10 or 1.5): " n || return 0
    [ "${_CM_ABORT:-0}" = 1 ] && return 0
    n="${n//[[:space:]]/}"
    if [[ ! "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$n" =~ ^0+(\.0+)?$ ]]; then echo "🔴  Enter a number above 0."; return 0; fi
    _bvk_menu unit -t "Size unit" -i "📏" -q "In which unit is $n?" \
      "b:Bytes (B)" "kb:KB — 1,000 bytes" "mb:MB — 1,000,000 bytes" "gb:GB — 10^9 bytes" "tb:TB — 10^12 bytes" "pb:PB — 10^15 bytes" "eb:EB — 10^18 bytes" \
      "kib:KiB — 1,024 bytes" "mib:MiB — 1,048,576 bytes" "gib:GiB — 2^30 bytes" "tib:TiB — 2^40 bytes" "pib:PiB — 2^50 bytes" "eib:EiB — 2^60 bytes" || return 0
    [ "${_CM_ABORT:-0}" = 1 ] && return 0
    n2="$unit"
  else
    _bvk_menu mode -t "Extract $noun" -i "✂️" -q "Which $noun?" \
      "1:First n $noun" "2:Range" "3:Last n $noun" "4:Random $noun" "5:Duplicate $noun" "6:Unique $noun" || return 0
    [ "${_CM_ABORT:-0}" = 1 ] && return 0
    case "$mode" in
      1) mode=first;  _xtr_ask_int n "How many $noun: " || return 0 ;;
      2) mode=range;  _xtr_ask_int n "Range from (first one is 1): " || return 0
                      _xtr_ask_int n2 "Range to (included): " || return 0 ;;
      3) mode=last;   _xtr_ask_int n "How many $noun: " || return 0 ;;
      4) mode=random; _xtr_ask_int n "How many random $noun: " || return 0 ;;
      5|6) if [ "$mode" = 5 ]; then mode=dup; dlabel="duplicate"; else mode=uniq; dlabel="unique"; fi
         _bvk_menu sub -t "How many?" -i "🔢" -q "How many $dlabel $noun do you want?" "1:All" "2:A specific number" || return 0
         [ "${_CM_ABORT:-0}" = 1 ] && return 0
         case "$sub" in 1) n="" ;; 2) _xtr_ask_int n "How many: " || return 0 ;; *) _bvk_invalid; return 0 ;; esac ;;
      *) _bvk_invalid; return 0 ;;
    esac
  fi

  local base rc; base="$(mktemp)" || return 0
  echo
  echo "✂️  Extracted"
  _xtr_engine "$kindname" "$mode" "$n" "$n2" "$base" "${sp_files[@]}"
  rc=$?
  if [ "$rc" = 3 ]; then echo "🔴  Nothing to extract (0 results)."; rm -f "$base" "$base.out" "$base.tsv"; return 0; fi
  if [ "$rc" != 0 ]; then rm -f "$base" "$base.out" "$base.tsv"; return 0; fi
  echo

  local ans stamp ext=txt
  [ "$kindname" = bytes ] && ext=bin
  if [ "$kindname" = bytes ]; then
    _bvk_menu ans -t "Extracted" -i "✂️" -q "What do you want to do with the result?" "c:Copy it to the clipboard" "f:Save it to a file"
  else
    _bvk_menu ans -t "Extracted" -i "✂️" -q "What do you want to do with the result?" "c:Copy it to the clipboard" "f:Save it to a file" "x:Save it in Excel"
  fi
  if [ $? -eq 0 ] && [ "${_CM_ABORT:-0}" != 1 ]; then
    printf -v stamp '%(%Y%m%d_%H%M%S)T' -1
    case "${ans,,}" in
      c) if [ "$(wc -c < "$base.out")" -gt 10485760 ]; then echo "🔴  Too big for the clipboard (over 10 MB) — save it to a file instead."
         else bashbasicsbyvk_copy < "$base.out" && echo "💫 Copied to clipboard"; fi ;;
      f) cp -- "$base.out" "${path%/}/extract_$stamp.$ext" && echo "💾 Saved -> ${path%/}/extract_$stamp.$ext" ;;
      x) _dep_need -c "xtr- Excel file (without it a CSV is saved instead)" openpyxl || true
         local _EB_TSV _EB_HEAD _EB_SHEET="extract" _EB_NUMS="2,3" _EB_BOLDLAST=0
         _EB_TSV="$(cat "$base.tsv")"$'\n'
         printf -v _EB_HEAD 'File\tPosition\tCount\tValue'
         _eb_save_sheet "${path%/}/extract_$stamp" ;;
      *) _bvk_invalid ;;
    esac
  fi
  rm -f "$base" "$base.out" "$base.tsv"
  return 0
}
