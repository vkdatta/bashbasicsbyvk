# bashbasicsbyvk_timezone.sh — Settings → Timezone
# ════════════════════════════════════════════════════════════════════════════
#  Pick the timezone the whole app uses (link expiry times, file times, logs, exports, file names …).
#  Every zone in this machine's tz database is listed (~500); each row shows its abbreviation and its
#  CURRENT offset, so you can tell what "IST", "EST" or "UTC" means at a glance:
#
#     1) System default            follow the computer's clock
#     2) Africa/Abidjan            GMT   UTC+00:00
#     …  Asia/Kolkata              IST   UTC+05:30
#     …  America/New_York          EDT   UTC-04:00
#
#  Type  =text  to search (it works on this screen exactly like everywhere else in Settings, but here it
#  also looks at the abbreviation and offset, ignores "_" and is always a "contains" search):
#     =kolkata   =ist   =new york   =+05:30   =america/arg   =utc
#
#  The choice is saved in the config file as  app_timezone  and applied by _apply_timezone (see
#  bashbasicsbyvk_settings.sh), which exports TZ for this shell and everything it starts.
# ════════════════════════════════════════════════════════════════════════════

declare -ga _TZ_NAMES=() _TZ_INFO=()

# Fill _TZ_NAMES / _TZ_INFO.  python3 gives abbreviation + current offset in one pass (fast); without it
# the names still come from the tz database files, just without the extra column.
_tz_load() {
  _TZ_NAMES=(); _TZ_INFO=()
  local n a o
  if command -v python3 >/dev/null 2>&1; then
    while IFS='|' read -r n a o; do
      [ -n "$n" ] || continue
      _TZ_NAMES+=("$n"); _TZ_INFO+=("$(printf '%-5s UTC%s' "$a" "$o")")
    done < <(python3 -I - <<'PY' 2>/dev/null
import os, re, datetime
try:
    import zoneinfo
    names = sorted(zoneinfo.available_timezones())
    dirs = [d for d in zoneinfo.TZPATH if os.path.isdir(d)]
except Exception:
    raise SystemExit(1)
ok = re.compile(r'^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$')
now = datetime.datetime.now(datetime.timezone.utc)
for n in names:
    if not ok.match(n) or n.split('/')[0] in ('posix', 'right') or n in ('Factory', 'localtime'):
        continue
    if not any(os.path.isfile(os.path.join(d, n)) for d in dirs):
        continue          # only zones the system's own  date  can use too
    try:
        t = now.astimezone(zoneinfo.ZoneInfo(n))
        off = t.utcoffset(); m = int(off.total_seconds() // 60); s = '+' if m >= 0 else '-'; m = abs(m)
        print('%s|%s|%s%02d:%02d' % (n, t.tzname() or '', s, m // 60, m % 60))
    except Exception:
        pass
PY
)
  fi
  if [ "${#_TZ_NAMES[@]}" -eq 0 ]; then
    local d f
    for d in "${_TZ_DIRS[@]}"; do
      [ -n "$d" ] && [ -d "$d" ] || continue
      while IFS= read -r f; do
        f="${f#"$d"/}"
        case "$f" in posix/*|right/*|posixrules|localtime|Factory|*.*|*[!A-Za-z0-9_+/-]*) continue ;; esac
        [[ "$f" == [A-Z]* ]] || continue
        _TZ_NAMES+=("$f"); _TZ_INFO+=("")
      done < <(find "$d" -type f 2>/dev/null | LC_ALL=C sort)
      [ "${#_TZ_NAMES[@]}" -gt 0 ] && break
    done
  fi
}

_st_tz_build() {
  local i
  _st_reset
  _st_eq "" "${app_timezone:-}"
  _st_add r "System default" "$_o" "follow this computer's clock" "tz:"
  for i in "${!_TZ_NAMES[@]}"; do
    _st_eq "${_TZ_NAMES[$i]}" "${app_timezone:-}"
    _st_add r "${_TZ_NAMES[$i]}" "$_o" "${_TZ_INFO[$i]}" "tz:${_TZ_NAMES[$i]}"
  done
}

_st_tz_act() {
  local z="${_st_tag[$1]#tz:}"
  if [ -n "$z" ] && ! _tz_valid "$z"; then
    _st_wipe; _st_note "⚠️  '$z' is not available on this computer."; _st_back=1; return
  fi
  app_timezone="$z"
  save_settings
  _apply_timezone
  _items_presorted=false
  _st_wipe                                   # radio rows don't wipe the block themselves
  _st_note "✅ Timezone: $(_tz_label)   —   times everywhere in the app now use it."
  _st_back=1
}

timezone_settings() {
  _tz_load
  _st_note "Now: $(_tz_label)"
  _st_note "Type  =  then part of a name, abbreviation or offset to search   (=kolkata · =ist · =new york · =+05:30)"
  _st_filter_wide=1
  _st_run "Timezone" _st_tz_build _st_tz_act
  _st_filter_wide=0
}
