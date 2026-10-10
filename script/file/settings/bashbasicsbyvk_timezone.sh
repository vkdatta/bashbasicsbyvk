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
#  No tz database on the computer?  The app says which package it would download and why, and asks y/N.
#  On N (or if the install fails) it offers a manual list of fixed UTC offsets instead (no downloads).
#
#  Type  =text  to search (it works on this screen exactly like everywhere else in Settings, but here it
#  also looks at the abbreviation and offset, ignores "_" and is always a "contains" search):
#     =kolkata   =ist   =new york   =+05:30   =america/arg   =utc
#
#  The choice is saved in the config file as  app_timezone  and applied by _apply_timezone (see
#  bashbasicsbyvk_settings.sh), which exports TZ for this shell and everything it starts.
# ════════════════════════════════════════════════════════════════════════════

declare -ga _TZ_NAMES=() _TZ_INFO=()
_TZ_MANUAL_ONLY=0


# Fill _TZ_NAMES / _TZ_INFO.  python3 gives abbreviation + current offset in one pass (fast); without it
# the names still come from the tz database files, just without the extra column.
# ── is a tz database installed?  If not: offer to install it, else fall back to fixed offsets ──────────
_tz_db_present() {
  local d
  for d in "${_TZ_DIRS[@]}"; do
    [ -n "$d" ] && [ -f "$d/Asia/Kolkata" ] && return 0
  done
  [ -f /system/usr/share/zoneinfo/tzdata ] && return 0        # Android keeps one blob
  return 1
}

# _tz_pkg_cmd → _TZ_PKG_NAME + _TZ_PKG_CMD (array) for this computer's package manager; 1 = none known
_tz_pkg_cmd() {
  local sudo=()
  _TZ_PKG_CMD=(); _TZ_PKG_NAME="tzdata"
  if [ "$(id -u 2>/dev/null)" != 0 ] && [[ "${PREFIX:-}" != *com.termux* ]] && command -v sudo >/dev/null 2>&1; then sudo=(sudo); fi
  if [[ "${PREFIX:-}" == *com.termux* ]] && command -v pkg >/dev/null 2>&1; then _TZ_PKG_CMD=(pkg install -y tzdata)
  elif command -v apt-get >/dev/null 2>&1; then _TZ_PKG_CMD=("${sudo[@]}" apt-get install -y tzdata)
  elif command -v apk >/dev/null 2>&1;     then _TZ_PKG_CMD=("${sudo[@]}" apk add tzdata)
  elif command -v dnf >/dev/null 2>&1;     then _TZ_PKG_CMD=("${sudo[@]}" dnf install -y tzdata)
  elif command -v yum >/dev/null 2>&1;     then _TZ_PKG_CMD=("${sudo[@]}" yum install -y tzdata)
  elif command -v pacman >/dev/null 2>&1;  then _TZ_PKG_CMD=("${sudo[@]}" pacman -S --noconfirm tzdata)
  elif command -v zypper >/dev/null 2>&1;  then _TZ_PKG_CMD=("${sudo[@]}" zypper install -y timezone); _TZ_PKG_NAME="timezone"
  else return 1; fi
}

# Ask first, say exactly what will be downloaded and why. Returns 0 only when the database is present afterwards.
_tz_bootstrap() {
  local ans
  if ! _tz_pkg_cmd; then
    echo "  ⚠️  This computer has no timezone database and no supported package manager was found."
    return 1
  fi
  echo "  📦 This computer has no timezone database (the tz data that knows every country's offset and daylight saving)."
  echo "     Package to download : $_TZ_PKG_NAME"
  echo "     Why                 : to list every timezone and convert times correctly, including daylight saving"
  echo "     Command it will run : ${_TZ_PKG_CMD[*]}"
  read -r -p "     Download and install it now? (y/N): " ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "  ↩️  Not installed — using the manual list of fixed offsets instead."; return 1 ;; esac
  if "${_TZ_PKG_CMD[@]}" && _tz_db_present; then echo "  ✅ $_TZ_PKG_NAME installed."; return 0; fi
  echo "  ⚠️  The install did not finish — using the manual list of fixed offsets instead."
  return 1
}

# Manual fallback: fixed UTC offsets (no daylight saving), searchable by region/abbreviation. Needs no files.
_TZ_MANUAL=(
"-12:00|Baker Island"
"-11:00|American Samoa (SST) · Niue"
"-10:00|Hawaii (HST)"
"-09:30|Marquesas Islands"
"-09:00|Alaska (AKST)"
"-08:00|US/Canada Pacific (PST) · Los Angeles · Vancouver"
"-07:00|US/Canada Mountain (MST) · Denver · Phoenix"
"-06:00|US/Canada Central (CST) · Chicago · Mexico City"
"-05:00|US/Canada Eastern (EST) · New York · Toronto · Bogota · Lima"
"-04:00|Atlantic (AST) · Caracas · La Paz · Santiago"
"-03:30|Newfoundland (NST)"
"-03:00|Brasilia (BRT) · Buenos Aires · Montevideo"
"-02:00|South Georgia · Fernando de Noronha"
"-01:00|Azores · Cape Verde"
"+00:00|UTC · GMT · London (winter) · Lisbon · Dublin · Reykjavik · Accra"
"+01:00|Central Europe (CET) · Paris · Berlin · Rome · Madrid · Lagos"
"+02:00|Eastern Europe (EET) · Athens · Cairo · Johannesburg (SAST) · Kyiv"
"+03:00|Moscow (MSK) · Istanbul · Riyadh · Nairobi · Baghdad"
"+03:30|Tehran (IRST)"
"+04:00|Dubai (GST) · Baku · Muscat"
"+04:30|Kabul"
"+05:00|Pakistan (PKT) · Tashkent · Maldives"
"+05:30|India (IST) · Sri Lanka · Kolkata · Mumbai · Delhi"
"+05:45|Nepal (NPT) · Kathmandu"
"+06:00|Bangladesh (BST) · Dhaka · Almaty · Bhutan"
"+06:30|Myanmar · Yangon · Cocos Islands"
"+07:00|Bangkok · Jakarta (WIB) · Hanoi · Ho Chi Minh"
"+08:00|China (CST) · Singapore · Hong Kong · Perth (AWST) · Manila · Kuala Lumpur"
"+08:45|Eucla (Australia)"
"+09:00|Japan (JST) · Korea (KST) · Seoul · Tokyo"
"+09:30|Adelaide (ACST) · Darwin"
"+10:00|Sydney (AEST) · Brisbane · Melbourne · Vladivostok · Guam"
"+10:30|Lord Howe Island"
"+11:00|Solomon Islands · Noumea · Magadan"
"+12:00|New Zealand (NZST) · Fiji · Kamchatka"
"+12:45|Chatham Islands"
"+13:00|Tonga · Samoa · Phoenix Islands"
"+14:00|Line Islands · Kiritimati"
)

_tz_load_manual() {
  local e
  _TZ_NAMES=(); _TZ_INFO=()
  for e in "${_TZ_MANUAL[@]}"; do _TZ_NAMES+=("UTC${e%%|*}"); _TZ_INFO+=("${e#*|}"); done
}

_tz_load() {
  _TZ_NAMES=(); _TZ_INFO=()
  local n a o
  if command -v python3 >/dev/null 2>&1; then
    while IFS='|' read -r n a o; do
      [ -n "$n" ] || continue
      _TZ_NAMES+=("$n"); _TZ_INFO+=("$(printf '%-5s UTC%s' "$a" "$o")")
    done < <(python3 -I - <<'PY' 2>/dev/null
import os, re, io, struct, datetime
import zoneinfo
ok = re.compile(r'^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$')
now = datetime.datetime.now(datetime.timezone.utc)

def show(n, z):
    t = now.astimezone(z)
    m = int(t.utcoffset().total_seconds() // 60); sg = '+' if m >= 0 else '-'; m = abs(m)
    print('%s|%s|%s%02d:%02d' % (n, t.tzname() or '', sg, m // 60, m % 60))

# 1) tz files on disk (Termux keeps them under $PREFIX)
try:
    extra = [os.environ.get('TZDIR', ''), os.environ.get('PREFIX', '') + '/share/zoneinfo']
    zoneinfo.reset_tzpath([p for p in extra + list(zoneinfo.TZPATH) if p.startswith('/')])
    names = sorted(zoneinfo.available_timezones())
except Exception:
    names = []
done = 0
for n in names:
    if not ok.match(n) or n.split('/')[0] in ('posix', 'right') or n in ('Factory', 'localtime'):
        continue
    try:
        show(n, zoneinfo.ZoneInfo(n)); done += 1
    except Exception:
        pass

# 2) Android keeps every zone inside ONE file ("tzdata": header, index of name/offset/length, data)
if not done:
    for c in (os.environ.get('ANDROID_TZDATA_ROOT', '/nonexistent') + '/etc/tz/tzdata',
              '/apex/com.android.tzdata/etc/tz/tzdata', '/system/usr/share/zoneinfo/tzdata'):
        try:
            d = open(c, 'rb').read()
            if not d.startswith(b'tzdata'):
                continue
            idx, dat, _ = struct.unpack('>3i', d[12:24])
            for pos in range(idx, dat, 52):
                n = d[pos:pos + 40].split(b'\0', 1)[0].decode('ascii', 'replace')
                off, ln = struct.unpack('>2i', d[pos + 40:pos + 48])
                if not ok.match(n):
                    continue
                try:
                    show(n, zoneinfo.ZoneInfo.from_file(io.BytesIO(d[dat + off:dat + off + ln]), key=n))
                except Exception:
                    pass
            break
        except Exception:
            continue
PY
)
  fi
  if [ "${#_TZ_NAMES[@]}" -eq 0 ]; then       # no usable python3: read the tz database files / index instead
    local d f t
    for d in "${_TZ_DIRS[@]}" /system/usr/share/zoneinfo; do
      [ -n "$d" ] && [ -d "$d" ] || continue
      if [ -r "$d/tzdata.zi" ]; then          # one file that names every zone and every alias
        while read -r t n a; do
          case "$t" in Z) f="$n" ;; L) f="$a" ;; *) continue ;; esac
          [[ "$f" =~ ^[ABCDEFGHIJKLMNOPQRSTUVWXYZ][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){0,2}$ ]] && _TZ_NAMES+=("$f")
        done < "$d/tzdata.zi"
      else
        while IFS= read -r f; do
          f="${f#"$d"/}"
          case "$f" in posix/*|right/*|posixrules|localtime|Factory|*.*|*[!A-Za-z0-9_+/-]*) continue ;; esac
          # a real zone: starts with a capital (checked explicitly - [A-Z] also matches lower case in some
          # locales) and is Area/City, or one of the few top-level names. Skips files like tzdata, tz_version.
          [[ "$f" =~ ^[ABCDEFGHIJKLMNOPQRSTUVWXYZ] ]] || continue
          [[ "$f" == */* || "$f" == UTC || "$f" == GMT || "$f" == UCT || "$f" == Zulu || "$f" == Universal || "$f" == Greenwich ]] || continue
          _TZ_NAMES+=("$f")
        done < <(find -L "$d" -type f 2>/dev/null)
      fi
      [ "${#_TZ_NAMES[@]}" -gt 0 ] && break
    done
  fi
  if [ "${#_TZ_NAMES[@]}" -eq 0 ] && command -v timedatectl >/dev/null 2>&1; then
    mapfile -t _TZ_NAMES < <(timedatectl list-timezones 2>/dev/null)
  fi
  if [ "${#_TZ_INFO[@]}" -ne "${#_TZ_NAMES[@]}" ]; then
    mapfile -t _TZ_NAMES < <(printf '%s\n' "${_TZ_NAMES[@]}" | LC_ALL=C sort -u)
    _TZ_INFO=(); local i; for i in "${!_TZ_NAMES[@]}"; do _TZ_INFO+=(""); done
  fi
}

_st_tz_build() {
  local i
  _st_reset
  _st_eq "" "${app_timezone:-}"
  _st_add r "System default" "$_o" "follow this computer's clock" "tz:"
  (( _TZ_MANUAL_ONLY )) || _st_add a "Manual list (fixed offsets)" 0 "UTC-12:00 … UTC+14:00, no daylight saving" "manual"
  for i in "${!_TZ_NAMES[@]}"; do
    _st_eq "${_TZ_NAMES[$i]}" "${app_timezone:-}"
    _st_add r "${_TZ_NAMES[$i]}" "$_o" "${_TZ_INFO[$i]}" "tz:${_TZ_NAMES[$i]}"
  done
}

# the fixed-offset sub screen (opened from the "Manual list" row of the full list)
_st_tzm_build() {
  local e
  _st_reset
  for e in "${_TZ_MANUAL[@]}"; do
    _st_eq "UTC${e%%|*}" "${app_timezone:-}"
    _st_add r "UTC${e%%|*}" "$_o" "${e#*|}" "tz:UTC${e%%|*}"
  done
}

_st_tz_act() {
  local tag="${_st_tag[$1]}" z before="${app_timezone:-}"
  if [ "$tag" = manual ]; then              # open the manual list; if a zone was picked there, close this screen too
    _st_note "Fixed UTC offsets — no automatic daylight-saving change. Search by region: =india  =new york  =tokyo"
    _st_run "Timezone › Manual" _st_tzm_build _st_tz_act
    [ "${app_timezone:-}" != "$before" ] && _st_back=1
    return
  fi
  z="${tag#tz:}"
  if [ -n "$z" ] && ! _tz_valid "$z"; then   # stay on this screen so another zone can be picked
    _st_wipe; _st_note "⚠️  '$z' cannot be used on this computer — pick another, or use the Manual list."
    return
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
  local manual=0
  _TZ_MANUAL_ONLY=0
  if _tz_db_present; then _tz_load; fi
  # no database, or only junk came back (fewer than 20 zones): offer to install it, else manual list
  if ! _tz_db_present || [ "${#_TZ_NAMES[@]}" -lt 20 ]; then
    _tz_bootstrap && { _tz_load; [ "${#_TZ_NAMES[@]}" -ge 20 ] || manual=1; } || manual=1
  fi
  if (( manual )); then
    _tz_load_manual; _TZ_MANUAL_ONLY=1
    _st_note "Manual list: fixed UTC offsets (no automatic daylight-saving change). Search by region, e.g. =india  =new york  =tokyo"
  else
    _st_note "Type  =  then part of a name, abbreviation or offset to search   (=kolkata · =ist · =new york · =+05:30)"
  fi
  _st_note "Now: $(_tz_label)"
  _st_filter_wide=1
  _st_run "Timezone" _st_tz_build _st_tz_act
  _st_filter_wide=0
}
