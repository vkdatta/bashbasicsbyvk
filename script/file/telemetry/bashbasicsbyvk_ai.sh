# .ai "question"  -- super user only. Asks the telemetry worker (Cloudflare Workers AI)
# to turn a plain-English question into a read-only SQLite query on active_users,
# runs it server-side, and returns the rows. Excel/CSV wrapping is done here.
#
#   .ai "active users from 01102026 to 05102026 in excel"
#   .ai "top 5 countries last week"            -> table in the terminal
#   .ai "daily total in october as csv"
#
# Uses the same credentials as the file API (FILEAPI_BASHBASICS_EMAIL / _KEY).
# The worker only accepts them if the email is the configured super user.

_BVK_AI_URL="${BVK_AI_URL:-https://telemetry.bashbasics.workers.dev/ai}"

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
        "not_super_user":  "⛔ These credentials are not the super user.",
        "invalid_credentials": "❌ Email or API key is incorrect.",
        "auth_required":   "❌ Email and API key required.",
        "rate_limited":    "⏳ Too many attempts, wait a minute.",
        "ai_unavailable":  "⚠️  " + d.get("message", "AI unavailable."),
        "unsafe_or_invalid_sql": "🛡️  Blocked: the AI produced a query that is not a plain read-only SELECT on active_users (" + str(d.get("reason","")) + "). Try rephrasing.",
        "sql_error":       "⚠️  The generated SQL failed: " + str(d.get("message","")),
    }
    print(msgs.get(err, f"❌ {err}: {d.get('message','')}"))
    if d.get("sql"): print("   SQL:", d["sql"])
    sys.exit(3 if err in ("invalid_credentials", "auth_required") else 1)

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

handle_ai_cmd() {
  local q="${1#.ai}"
  q="${q#"${q%%[![:space:]]*}"}"                       # trim leading space
  q="${q%"${q##*[![:space:]]}"}"                       # trim trailing space
  case "$q" in \"*\") q="${q:1:${#q}-2}" ;; \'*\') q="${q:1:${#q}-2}" ;; esac
  if [ -z "$q" ]; then
    echo '💡 Usage: .ai "active users from 01102026 to 05102026 in excel"'
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || { echo "❌ python3 is required for .ai"; return 1; }
  _bb_get_credentials || return 1

  local body resp rc
  body=$(mktemp) && resp=$(mktemp) || return 1
  chmod 600 "$body" "$resp" 2>/dev/null
  python3 -c 'import json,sys;print(json.dumps({"q":sys.argv[1]}))' "$q" > "$body"

  echo "🤖 Thinking…"
  _bb_auth_cfg | curl -s --max-time 40 "${_BB_CURL_OPTS[@]}" -K - \
      -X POST "$_BVK_AI_URL" -H 'Content-Type: application/json' \
      --data-binary @"$body" -o "$resp" 2>/dev/null
  rc=$?
  if [ $rc -ne 0 ] || [ ! -s "$resp" ]; then
    echo "❌ Could not reach the telemetry worker."
    rm -f "$body" "$resp"; return 1
  fi

  _bvk_ai_render "$resp" "$q" "${path:-$PWD}"
  rc=$?
  # wrong credentials -> forget them so the next .ai re-prompts
  [ $rc -eq 3 ] && unset FILEAPI_BASHBASICS_EMAIL FILEAPI_BASHBASICS_KEY
  rm -f "$body" "$resp"
  echo; read -rsn1 -p "↵ press any key to return" _ </dev/tty 2>/dev/null; echo
  return 0
}
