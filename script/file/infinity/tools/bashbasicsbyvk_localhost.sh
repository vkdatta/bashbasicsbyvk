# bashbasicsbyvk_localhost.sh - Localhost server, a function of the app (Infinity Stones, 6).  Runs INSIDE the app: see bashbasicsbyvk_gitpush.sh.

bvk_localhost() { _inf_sub "" _lh_body "$@"; }

_lh_body() {
clear

echo "=============================================="
echo "      Localhost Server"
echo "=============================================="
echo
echo "Valid TCP Port Range : 1 - 65535"
echo

echo "Busy Ports:"
echo "-----------"

if command -v lsof >/dev/null 2>&1; then

    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
        | awk 'NR>1{split($9,a,":");print a[length(a)]"\t"$1}' \
        | sort -n | uniq

elif command -v ss >/dev/null 2>&1; then

    ss -ltnp 2>/dev/null \
        | awk 'NR>1{split($4,a,":");print a[length(a)]}' \
        | sort -n | uniq

elif command -v netstat >/dev/null 2>&1; then

    netstat -ltn 2>/dev/null \
        | awk 'NR>2{split($4,a,":");print a[length(a)]}' \
        | sort -n | uniq

else

    echo "Unable to detect busy ports."

fi

echo

# A plain line only if the menu is not installed.
    ask_yes() {
    local ans=""
    if _bvk_yn ans "$1" -t "Localhost" -i "🌐"; then
        [ "$ans" = y ] && return 0
        return 1
    fi
    if [ "${2:-}" = -b ] && _bvk_back; then return 4; fi
    _mc_unwind && return 2                              # q: close up to the main loop
    return 1
    }

    port_busy() {

    if command -v lsof >/dev/null 2>&1; then
        lsof -i :"$1" >/dev/null 2>&1 && return 0
    fi

    if command -v fuser >/dev/null 2>&1; then
        fuser "$1"/tcp >/dev/null 2>&1 && return 0
    fi

    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null \
            | awk -v p="$1" 'NR>1{split($4,a,":");if(a[length(a)]==p){f=1}}END{exit !f}' \
            && return 0
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null \
            | awk -v p="$1" 'NR>2{split($4,a,":");if(a[length(a)]==p){f=1}}END{exit !f}' \
            && return 0
    fi

    return 1
    }

    kill_port() {

    echo
    echo "Attempting to free port $1..."

    # Try graceful termination first (SIGTERM), then force (SIGKILL) if needed.

    if command -v fuser >/dev/null 2>&1; then
        fuser -k "$1"/tcp >/dev/null 2>&1
        sleep 1
        fuser -k -KILL "$1"/tcp >/dev/null 2>&1
    fi

    if command -v lsof >/dev/null 2>&1; then
        PIDS=$(lsof -ti :"$1" 2>/dev/null)

        if [ -n "$PIDS" ]; then
            kill $PIDS 2>/dev/null
            sleep 1
            PIDS=$(lsof -ti :"$1" 2>/dev/null)
            if [ -n "$PIDS" ]; then
                kill -9 $PIDS 2>/dev/null
            fi
        fi
    fi

    sleep 1

    if port_busy "$1"; then
        echo "Warning: port $1 may still be in use."
        return 1
    fi

    echo "Port $1 freed."
    return 0
    }

# Step 1: the port.  rc 0 answered · 1 u · 2 q · 3 not a usable port (the message is printed here)
    _lh_s_port() {
    local _CE_SELECT=0                                  # the port typed before starts selected when u comes back here
    [ -n "${PORT:-}" ] && _CE_SELECT=1
    echo
    _mc_footer_std -b
    _CM_BACKED=0
    if ! _bvk_read PORT "Enter localhost port: " -i "${PORT:-}"; then
        [ "${_CM_BACKED:-0}" = 1 ] && return 1
        _mc_unwind && return 2                          # q: close up to the main loop
        return 3
    fi
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo; echo "Invalid port."; return 3
    fi
    if ((PORT < 1 || PORT > 65535)); then
        echo; echo "Port must be between 1 and 65535."; return 3
    fi
    return 0
    }

# Step 2: "Force it?" - asked only when the port is busy (a free port: nothing to ask, also when u comes back here from a later step)
    _lh_s_force() {
    local rc=0
    port_busy "$PORT" || return 0
    echo
    ask_yes "Port $PORT is already in use. Force it?" -b || rc=$?
    case "$rc" in
        0) kill_port "$PORT"; return 0 ;;
        4) return 1 ;;
        2) exit 42 ;;                                   # q: close up to the main loop
    esac
    echo
    echo "Operation cancelled."
    exit 0
    }

_lh_rc=0
_mc_steps _lh_s_port _lh_s_force || _lh_rc=$?
case "$_lh_rc" in
    0) ;;
    1) echo; echo "Operation cancelled."; exit 0 ;;      # u on the FIRST question: out of the tool, back to the menu it was opened from
    2) exit 42 ;;                                      # q: close up to the main loop
    *) exit 1 ;;
esac

if command -v python3 >/dev/null 2>&1; then
    _LH_PY="python3"
elif command -v python >/dev/null 2>&1; then
    _LH_PY="python"
else
    _dep_need -c "Local web server" python3 || exit 1
    _LH_PY="python3"
fi

    start_server() {

    TMPFILE=$(mktemp)
    trap 'rm -f "$TMPFILE"' EXIT

    "$_LH_PY" -m http.server "$PORT" \
        --bind 127.0.0.1 \
        2>"$TMPFILE"

    STATUS=$?

    if grep -q "Address already in use" "$TMPFILE"; then

        echo
        echo "Python reports port already in use."

        AGAIN=n; ask_yes "Force terminate process and retry?" && AGAIN=y

        case "$AGAIN" in

            [Yy]*)

                kill_port "$PORT"

                echo
                echo "Retrying..."
                echo

                trap - EXIT
                rm -f "$TMPFILE"

                exec "$_LH_PY" -m http.server "$PORT" --bind 127.0.0.1

                ;;

            *)

                echo
                echo "Cancelled."

                exit 1

                ;;

        esac

    fi

    cat "$TMPFILE"

    return $STATUS
    }

echo
echo "=============================================="
echo "Localhost created."
echo
echo "View at:"
echo
echo "    http://localhost:$PORT/"
echo
echo "Press CTRL+C to stop."
echo "=============================================="
echo

start_server
}
