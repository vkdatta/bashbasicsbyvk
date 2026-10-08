# .ai  --  natural-language helper.   All commands use the ACTIVE -auth user.
#
#   .ai "delete all python files"        -> suggests a file command, e.g.  .s.ext py     (5 credits)
#   .ai -ledger 01102026 07102026        -> your credit ledger for the period            (free)
#   .ai -report 01102026 07102026 xlsx "top countries"
#                                        -> telemetry report, SUPER USER only            (free)
#
# The AI may only answer with commands from the allow-list below. The reply is re-checked here
# (never executed automatically). Dates are ddmmyyyy. Each normal query costs 5 credits, charged
# server-side only when a usable answer is returned.

_BVK_AI_URL="${BVK_AI_URL:-https://telemetry.bashbasics.workers.dev/ai}"

# Allow-list of commands the AI may suggest (ERE, whole line).  EXTEND THIS as commands are added.
_BVK_AI_ALLOWED=(
  '\.s\.(a|a\.f|a\.d|f|d|dup|dup\.all|empty)'
  '\.s\.(ext|sw|ew|contains|size|time)( [A-Za-z0-9._,<>=-]{1,60})'
  '\.us\.(a|a\.f|a\.d|f|d|dup|dup\.all|empty)'
  '\.us\.(ext|sw|ew|contains|size|time)( [A-Za-z0-9._,<>=-]{1,60})'
)
_bvk_ai_cmd_ok() {
  local c="$1" re
  [ "${#c}" -le 120 ] || return 1
  [[ "$c" != *$'\n'* ]] || return 1
  for re in "${_BVK_AI_ALLOWED[@]}"; do [[ "$c" =~ ^${re}$ ]] && return 0; done
  return 1
}
_bvk_ai_date_ok() {  # ddmmyyyy, real calendar date
  [[ "$1" =~ ^[0-9]{8}$ ]] && date -d "${1:4:4}-${1:2:2}-${1:0:2}" +%F >/dev/null 2>&1
}
_bvk_ai_iso() { echo "${1:4:4}-${1:2:2}-${1:0:2}"; }

_bvk_ai_render() {  # $1=response file  $2=question  $3=output dir
  python3 - "$1" "$2" "$3" <<'PY'
import sys, json, re, os, csv, datetime
resp_file, question, outdir = sys.argv[1:4]
try:
    d = json.load(open(resp_file))
except Exception:
    print("❌ Unexpected response from the server."); sys.exit(2)

if not d.get("ok"):
    err = d.get("error", "unknown")
    msgs = {
        "not_super_user":  "⛔ -report is for the super user only.",
        "invalid_credentials": "❌ Email or API key is incorrect.",
        "auth_required":   "❌ Email and API key required.",
        "rate_limited":    "⏳ Too many attempts, wait a minute.",
        "ai_unavailable":  "⚠️  " + d.get("message", "AI unavailable."),
        "unsafe_or_invalid_sql": "🛡️  Blocked: the AI produced a query that is not a plain read-only SELECT on active_users (" + str(d.get("reason","")) + "). Try rephrasing.",
        "sql_error":       "⚠️  The generated SQL failed: " + str(d.get("message","")),
        "insufficient_credits": "💳 " + str(d.get("message","Not enough credits.")),
        "ip_blocked":      "⛔ " + str(d.get("message","Blocked.")),
    }
    print(msgs.get(err, f"❌ {err}: {d.get('message','')}"))
    if d.get("sql"): print("   SQL:", d["sql"])
    sys.exit(3 if err in ("invalid_credentials", "auth_required") else 1)

if d.get("kind") == "none":
    print("ℹ️ ", d.get("message", "Not a usage-statistics question, no report was run.")); sys.exit(0)
cols, rows = d.get("columns", []), d.get("rows", [])
print("🧠 SQL:", d["sql"])
if not rows:
    print("ℹ️  No rows."); sys.exit(0)

q = question.lower()
fmt = "xlsx" if re.search(r"excel|xlsx|spreadsheet", q) else "csv" if "csv" in q else None
matrix = [[r.get(c) for c in cols] for r in rows]

if fmt:
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    base = os.path.join(outdir, f"bvk_ai_{stamp}")
    if fmt == "xlsx":
        try:
            from openpyxl import Workbook
            from openpyxl.styles import Font
            wb = Workbook(); ws = wb.active; ws.title = "result"
            ws.append(cols)
            for r in matrix: ws.append(r)
            for c in ws[1]: c.font = Font(bold=True)
            ws.freeze_panes = "A2"
            for i, c in enumerate(cols, 1):
                w = max([len(str(c))] + [len(str(r[i-1])) for r in matrix]) + 2
                ws.column_dimensions[ws.cell(1, i).column_letter].width = min(w, 40)
            wb.save(base + ".xlsx")
            print(f"📗 Saved {len(rows)} rows -> {base}.xlsx"); sys.exit(0)
        except ImportError:
            print("⚠️  openpyxl not installed (pip install openpyxl); saving CSV instead.")
    with open(base + ".csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(cols); w.writerows(matrix)
    print(f"📄 Saved {len(rows)} rows -> {base}.csv"); sys.exit(0)

# terminal table
shown = matrix[:50]
widths = [max(len(str(c)), *(len(str(r[i])) for r in shown)) for i, c in enumerate(cols)]
line = lambda r: "  ".join(str(v).ljust(widths[i]) for i, v in enumerate(r))
print(line(cols)); print("  ".join("-" * w for w in widths))
for r in shown: print(line(r))
if len(matrix) > 50: print(f"… {len(matrix)-50} more rows (add 'in excel' to get all)")
if d.get("truncated"): print("⚠️  Result capped at 1000 rows.")
PY
}


_bvk_ai_ledger_render() {  # $1=response file
  python3 - "$1" <<'PY'
import sys, json
try: d = json.load(open(sys.argv[1]))
except Exception: print("❌ Unexpected response from the server."); sys.exit(2)
if not d.get("ok"): print("❌", d.get("message") or d.get("error", "failed")); sys.exit(1)
rows = d.get("rows", [])
print(f"💳 Balance: {d.get('balance','?')} credits")
if not rows: print("ℹ️  No ledger entries in this period."); sys.exit(0)
cols = ["date", "type", "credits", "balance", "note"]
w = [max(len(c), *(len(str(r.get(c, ""))) for r in rows[:100])) for c in cols]
print("  ".join(c.ljust(w[i]) for i, c in enumerate(cols))); print("  ".join("-"*x for x in w))
for r in rows[:100]: print("  ".join(str(r.get(c, "")).ljust(w[i]) for i, c in enumerate(cols)))
if len(rows) > 100: print(f"… {len(rows)-100} more entries")
PY
}

_bvk_ai_ext_summary() {  # extension -> count for the current dir (lets the model pick real extensions)
  local dir="${path:-$PWD}"
  ls -1A "$dir" 2>/dev/null | head -2000 | awk -F. 'NF>1 && $1!="" {c[tolower($NF)]++} END{for(e in c) printf "%s:%d,", e, c[e]}' | head -c 600
}

handle_ai_cmd() {
  local q="${1#.ai}"
  q="${q#"${q%%[![:space:]]*}"}"; q="${q%"${q##*[![:space:]]}"}"
  command -v python3 >/dev/null 2>&1 || { echo "❌ python3 is required for .ai"; return 1; }

  local mode="query" from="" to="" fmt="" payload_args=()
  case "$q" in
    -ledger|-ledger\ *)
      mode=ledger; set -f; set -- ${q#-ledger}; set +f; from="$1"; to="$2"
      if ! { _bvk_ai_date_ok "$from" && _bvk_ai_date_ok "$to"; }; then
        echo '💡 Usage: .ai -ledger 01102026 07102026   (ddmmyyyy ddmmyyyy)'; return 0; fi
      q="" ;;
    -report|-report\ *)
      mode=report; set -f; set -- ${q#-report}; set +f; from="$1"; to="$2"; fmt="${3,,}"
      if ! { _bvk_ai_date_ok "$from" && _bvk_ai_date_ok "$to"; } || [ -z "$fmt" ]; then
        echo "💡 Usage: .ai -report 01102026 07102026 xlsx|csv|table 'your question'   (super user only)"; return 0; fi
      case "$fmt" in xlsx|csv|table) ;; *) echo "❌ fileformat must be xlsx, csv or table."; return 0 ;; esac
      q="${q#-report}"; q="${q#"${q%%[![:space:]]*}"}"; q="${q#* }"; q="${q#* }"; q="${q#* }"   # drop from to fmt
      case "$q" in \"*\") q="${q:1:${#q}-2}" ;; \'*\') q="${q:1:${#q}-2}" ;; esac
      [ -n "$q" ] || { echo "💡 Add a question: .ai -report 01102026 07102026 xlsx 'top countries'"; return 0; }
      # the renderer decides xlsx/csv from the question text; make the chosen format explicit
      case "$fmt" in xlsx) q="$q in excel" ;; csv) q="$q as csv" ;; esac ;;
    "")
      echo '💡 Usage: .ai "delete all python files"   |   .ai -ledger ddmmyyyy ddmmyyyy   |   .ai -report ddmmyyyy ddmmyyyy fmt "question"'
      return 0 ;;
    *) case "$q" in \"*\") q="${q:1:${#q}-2}" ;; \'*\') q="${q:1:${#q}-2}" ;; esac ;;
  esac
  [ "${#q}" -le 500 ] || { echo "❌ Query too long (max 500 chars)."; return 0; }

  _bb_get_credentials || return 1
  local body resp hdr rc
  body=$(mktemp) && resp=$(mktemp) && hdr=$(mktemp) || return 1
  chmod 600 "$body" "$resp" "$hdr" 2>/dev/null
  python3 - "$mode" "$q" "$from" "$to" "$fmt" "$(date +%F)" "$(_bvk_ai_ext_summary)" > "$body" <<'PY'
import json, sys
m, q, f, t, fmt, today, exts = sys.argv[1:8]
iso = lambda s: f"{s[4:8]}-{s[2:4]}-{s[0:2]}" if s else ""
print(json.dumps({"mode": m, "q": q, "from": iso(f), "to": iso(t), "format": fmt,
                  "today": today, "extensions": exts}))
PY

  echo "🤖 Thinking…"
  _bb_auth_cfg | curl -s --max-time 40 "${_BB_CURL_OPTS[@]}" -K - -D "$hdr" \
      -X POST "$_BVK_AI_URL" -H 'Content-Type: application/json' \
      --data-binary @"$body" -o "$resp" 2>/dev/null
  rc=$?
  if [ $rc -ne 0 ] || [ ! -s "$resp" ]; then
    echo "❌ Could not reach the server."; rm -f "$body" "$resp" "$hdr"; return 1
  fi

  case "$mode" in
    ledger) _bvk_ai_ledger_render "$resp" ;;
    report) _bvk_ai_render "$resp" "$q" "${path:-$PWD}" ;;
    query)
      python3 - "$resp" > "$body" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: print("ERR\tUnexpected response from the server."); sys.exit(0)
if not d.get("ok"): print("ERR\t" + str(d.get("message") or d.get("error", "failed")).replace("\n", " ")); sys.exit(0)
if d.get("kind") == "command": print("CMD\t" + str(d.get("command", "")).replace("\n", " ") + "\t" + str(d.get("explanation", "")).replace("\n", " "))
else: print("NONE\t" + str(d.get("message", "I can only help with file selection commands.")).replace("\n", " "))
PY
      local kind cmd note
      IFS=$'\t' read -r kind cmd note < "$body"
      case "$kind" in
        CMD)
          if _bvk_ai_cmd_ok "$cmd"; then
            echo "💡 Try:  $cmd"; [ -n "$note" ] && echo "   $note"
          else
            echo "🛡️  The AI suggested something outside the allowed command list, so it was dropped. Try rephrasing."
          fi ;;
        NONE) echo "ℹ️  ${cmd}" ;;
        *)    echo "❌ ${cmd}" ;;
      esac ;;
  esac
  local ded bal
  ded=$(grep -i '^X-Credits-Deducted:' "$hdr" | tr -d '\r' | cut -d' ' -f2-)
  bal=$(grep -i '^X-Credits-Balance:'  "$hdr" | tr -d '\r' | cut -d' ' -f2-)
  [ -n "$ded" ] && [ "$ded" != 0 ] && echo "💳 -$ded credits${bal:+ · balance $bal}"
  rm -f "$body" "$resp" "$hdr"
  echo; read -rsn1 -p "↵ press any key to return" _ </dev/tty 2>/dev/null; echo
  return 0
}
