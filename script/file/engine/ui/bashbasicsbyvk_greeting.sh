# greeting — the first row of the main screen:   💫 Hey night owl, Geecko 🦉
#
#   WHO     the first word of the billing name of the active -auth user, else the start of the mail (john.doe9@x -> John);
#           nobody signed in (or nothing usable) -> a playful placeholder (geecko, qtπ ...), picked once per session
#   WHEN    the hour of the day (night owl / early bird / morning / afternoon / evening / late) or the weekday ("Ah, Monday again")
#   HOLIDAY a date that is the same every year wishes you (New Year, Valentine's, Halloween, Christmas ...).  Movable feasts
#           (Diwali, Eid, Easter ...) change every year, so they are NOT here.  India-only days show only in a +05:30 zone.
#
# The header is redrawn all the time, so this never forks and never waits: the text is built once a minute and kept; the phrase
# is picked once per session (the greeting does not flicker between redraws).  Time and date follow Settings → Timezone, because
# the app exports TZ and  printf '%(...)T'  honours it.
#
#   _gr_line   -> _GR_TXT  (the whole greeting, without the 💫)
#   _gr_row    prints the row  "💫 <greeting>"  (newline included)

declare -g _GR_SEED="" _GR_KEY="" _GR_TXT="" _GR_NAME=""

# {n} = the name.  Pools are indexed by the session's seed, so a new session may say it another way.
declare -g -a _GR_PLACEHOLDER=(geecko "qtπ" champ captain sparky wizard legend stranger hotshot "friend")

declare -g -a _GR_T_NIGHT=(      # 00:00–03:59
  "Hey night owl {n}, the terminal never sleeps 🦉"
  "Still up, {n}? The night owls salute you 🦉"
  "Burning the midnight oil, {n}? 🌙"
  "Hello {n} — the quiet hours are the best hours 🌙")
declare -g -a _GR_T_EARLY=(      # 04:00–05:59
  "Hey early bird {n} — the worm is all yours 🐦"
  "Up before the sun, {n}? Respect 🌅"
  "Good morning, early bird {n} 🐦")
declare -g -a _GR_T_MORNING=(    # 06:00–11:59
  "Good morning, {n} ☀️"
  "Morning, {n} — coffee first, commands second ☕"
  "Rise and shine, {n} 🌤️"
  "Hello {n}, fresh day, fresh folders 📂")
declare -g -a _GR_T_NOON=(       # 12:00–16:59
  "Good afternoon, {n} 🌞"
  "Hey {n}, the afternoon is yours"
  "Hello {n} — post-lunch productivity mode 🍛")
declare -g -a _GR_T_EVENING=(    # 17:00–20:59
  "Good evening, {n} 🌇"
  "Evening, {n} — golden hour for shell scripts"
  "Hey {n}, winding down or just warming up?")
declare -g -a _GR_T_LATE=(       # 21:00–23:59
  "Good night, {n}… or one more command? 🌙"
  "Hey night owl {n}, the stars are out ✨"
  "Hello {n} — late-night commits are the bravest ones 🦉")

# by weekday (date +%u: 1 = Monday ... 7 = Sunday)
declare -g -a _GR_D_1=("Ah, Monday again, {n} 😅" "Monday, {n}. Deep breath — you've got this 💪" "New week, clean slate, {n} 🧼")
declare -g -a _GR_D_2=("Tuesday, {n} — the week is warming up" "Happy Tuesday, {n} 🌮" "Hey {n}, Tuesday is just Monday with momentum")
declare -g -a _GR_D_3=("Hump day, {n} 🐪 — halfway there" "Wednesday, {n} — it's downhill from here" "Mid-week check-in, {n}")
declare -g -a _GR_D_4=("Thursday, {n} — Friday is in sight 👀" "Almost Friday, {n}!" "Hey {n}, it's Thursday: Friday's warm-up act")
declare -g -a _GR_D_5=("Friday, {n}! 🎉 Almost there" "TGIF, {n} 🥳" "Hey {n}, the weekend is knocking 🚪")
declare -g -a _GR_D_6=("Happy Saturday, {n} 🛋️ — no meetings, only folders" "Weekend mode on, {n} 😎" "Saturday, {n} — side-project hours 🛠️")
declare -g -a _GR_D_7=("Lazy Sunday, {n} ☕" "Sunday, {n} — a little tidying before Monday? 🧹" "Hello {n}, Sunday vibes 🌿")

# fixed-date holidays:  MMDD|where|text     where = * (everywhere) · IN (only in a +05:30 zone)
declare -g -a _GR_HOLIDAYS=(
  "0101|*|Happy New Year, {n}! 🎆 Make this one count"
  "0126|IN|Happy Republic Day, {n} 🇮🇳"
  "0214|*|Happy Valentine's Day, {n} 💝"
  "0314|*|Happy Pi Day, {n} — 3.14159265… 🥧"
  "0401|*|Happy April Fools' Day, {n} 🤡 — trust nothing, not even this greeting"
  "0422|*|Happy Earth Day, {n} 🌍"
  "0501|*|Happy Labour Day, {n} — go easy on yourself 🛠️"
  "0815|IN|Happy Independence Day, {n} 🇮🇳"
  "1002|IN|Happy Gandhi Jayanti, {n} 🕊️"
  "1031|*|Happy Halloween, {n} 🎃 — trick or treat?"
  "1224|*|Merry Christmas Eve, {n} 🎄"
  "1225|*|Merry Christmas, {n} 🎅"
  "1231|*|Happy New Year's Eve, {n} 🥂 — last commit of the year?")

# _gr_name -> _GR_NAME  (empty when nobody usable is signed in).  Builtins only: two tiny files.
_gr_name() {
  _GR_NAME=""
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth" id k v line
  [ -r "$dir/active" ] && IFS= read -r id < "$dir/active"
  [[ "$id" =~ ^p_[0-9a-f]{16}$ ]] || return 0
  if [ -r "$dir/billing/$id" ]; then                                   # a name the person typed themselves wins
    while IFS='=' read -r k v || [ -n "$k" ]; do
      [ "$k" = name ] || continue
      v="${v%$'\r'}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%%[[:space:]]*}"
      _GR_NAME="${v:0:20}"; break
    done < "$dir/billing/$id"
  fi
  if [ -z "$_GR_NAME" ] && [ -r "$dir/profiles/$id" ]; then            # else the start of the mail: john.doe9@x -> John
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        [Mm][Aa][Ii][Ll]=*)
          v="${line#*=}"; v="${v%$'\r'}"; v="${v%%@*}"; v="${v%%[^[:alpha:]]*}"; v="${v,,}"
          (( ${#v} >= 2 )) && _GR_NAME="${v^}"
          break ;;
      esac
    done < "$dir/profiles/$id"
  fi
  return 0
}

# _gr_pick ARRAY_NAME  -> _GR_PICKED  (one element, chosen by the session's seed)
_gr_pick() {
  local -n _a="$1"
  _GR_PICKED="${_a[$(( (_GR_SEED / 2) % ${#_a[@]} ))]}"
}

_gr_line() {
  local id min
  [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/active" ] && IFS= read -r id < "${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/active"
  printf -v min '%(%Y%m%d%H%M)T' -1
  [ -n "$_GR_SEED" ] || _GR_SEED=$RANDOM
  [ "$_GR_KEY" = "$id $min" ] && [ -n "$_GR_TXT" ] && return 0          # built this minute for this user: keep it
  _GR_KEY="$id $min"

  _gr_name
  [ -n "$_GR_NAME" ] || _GR_NAME="${_GR_PLACEHOLDER[$(( _GR_SEED % ${#_GR_PLACEHOLDER[@]} ))]}"

  local t H u md j z
  printf -v t '%(%H %u %m%d %j %z)T' -1
  read -r H u md j z <<< "$t"
  H=$((10#$H)); j=$((10#$j))

  local txt="" h w
  for h in "${_GR_HOLIDAYS[@]}"; do                                    # a day that is the same every year wishes first
    [ "${h%%|*}" = "$md" ] || continue
    w="${h#*|}"; w="${w%%|*}"
    [ "$w" = "*" ] || { [ "$w" = IN ] && [ "$z" = "+0530" ]; } || continue
    txt="${h#*|*|}"; break
  done
  if [ -z "$txt" ] && [ "$j" = 256 ]; then txt="Happy Programmers' Day, {n} 👾 — it's day 256"; fi

  if [ -z "$txt" ]; then
    if (( _GR_SEED % 2 == 0 )); then                                   # half the sessions greet by the hour, half by the weekday
      if   (( H < 4 ));  then _gr_pick _GR_T_NIGHT
      elif (( H < 6 ));  then _gr_pick _GR_T_EARLY
      elif (( H < 12 )); then _gr_pick _GR_T_MORNING
      elif (( H < 17 )); then _gr_pick _GR_T_NOON
      elif (( H < 21 )); then _gr_pick _GR_T_EVENING
      else                    _gr_pick _GR_T_LATE
      fi
    else
      case "$u" in 1) _gr_pick _GR_D_1 ;; 2) _gr_pick _GR_D_2 ;; 3) _gr_pick _GR_D_3 ;; 4) _gr_pick _GR_D_4 ;;
                   5) _gr_pick _GR_D_5 ;; 6) _gr_pick _GR_D_6 ;; *) _gr_pick _GR_D_7 ;; esac
    fi
    txt="$_GR_PICKED"
  fi
  _GR_TXT="${txt//\{n\}/$_GR_NAME}"
  return 0
}

_gr_row() { _gr_line; printf '💫 %s\n' "$_GR_TXT"; }
