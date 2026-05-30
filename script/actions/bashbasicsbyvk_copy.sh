bashbasicsbyvk_copy() {
    local WORKER_URL MAX_OSC52_BYTES
    local TEMP_MODE FILE FILE_SIZE COPY_CMD
    local PAYLOAD ID RESPONSE EXIT_CODE
    local HTTP_STATUS FINAL_URL URL_PAYLOAD

    WORKER_URL="https://copy.bashbasics.workers.dev"
    MAX_OSC52_BYTES=1024

    TEMP_MODE=false

    trap '[ "$TEMP_MODE" = true ] && rm -f "$FILE"' RETURN

    FILE=$(mktemp)
    TEMP_MODE=true

    if [ -n "$1" ]; then

        if [ ! -r "$1" ]; then
            echo "❌ Error: Cannot read '$1'."
            return 1
        fi

        cat -- "$1" > "$FILE"

    else

        if [ -t 0 ]; then
            echo "Usage:"
            echo "  bashbasicsbyvk_copy <filename>"
            echo "  cat file.txt | bashbasicsbyvk_copy"
            echo "  echo hello | bashbasicsbyvk_copy"
            return 1
        fi

        cat > "$FILE"
    fi

    FILE_SIZE=$(wc -c < "$FILE")

    if command -v pbcopy >/dev/null 2>&1; then
        COPY_CMD="pbcopy"

    elif command -v clip.exe >/dev/null 2>&1; then
        COPY_CMD="clip.exe"

    elif command -v wl-copy >/dev/null 2>&1; then
        COPY_CMD="wl-copy"

    elif command -v xclip >/dev/null 2>&1; then
        COPY_CMD="xclip"

    elif command -v termux-clipboard-set >/dev/null 2>&1; then
        COPY_CMD="termux-clipboard-set"

    elif [ "$FILE_SIZE" -le "$MAX_OSC52_BYTES" ]; then
        COPY_CMD="osc52-direct"

    else
        COPY_CMD="worker-bridge"
    fi

    case "$COPY_CMD" in

        pbcopy|clip.exe|wl-copy|termux-clipboard-set)

            "$COPY_CMD" < "$FILE"

            echo "✅ Success: Copied via $COPY_CMD."
            ;;

        xclip)

            xclip -selection clipboard < "$FILE"

            echo "✅ Success: Copied via xclip."
            ;;

        osc52-direct)

            PAYLOAD=$(base64 < "$FILE" | tr -d '[:space:]')

            if [[ "$TERM" == screen* ]] || [[ "$TERM" == tmux* ]]; then
                printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$PAYLOAD"
            else
                printf "\033]52;c;%s\a" "$PAYLOAD"
            fi

            echo "✅ Success: Small file (<1KB) copied via OSC52."
            ;;

        worker-bridge)

            ID=$(openssl rand -hex 3)

            echo "☁️ Large content detected. Uploading..."

            RESPONSE=$(curl -s --fail -w "\n%{http_code}" \
                -H "Expect:" \
                -X PUT \
                --data-binary "@$FILE" \
                "$WORKER_URL/$ID")

            EXIT_CODE=$?

            HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
            FINAL_URL=$(echo "$RESPONSE" | head -n 1)

            if [ "$EXIT_CODE" -eq 0 ] && [ "$HTTP_STATUS" = "201" ]; then

                URL_PAYLOAD=$(printf "%s" "$FINAL_URL" | base64 | tr -d '\n')

                if [[ "$TERM" == screen* ]] || [[ "$TERM" == tmux* ]]; then
                    printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$URL_PAYLOAD"
                else
                    printf "\033]52;c;%s\a" "$URL_PAYLOAD"
                fi

                clear

                echo "✅ Success: Sync link copied to clipboard."
                echo "-------------------------------------------"
                echo "Link: $FINAL_URL"
                echo "-------------------------------------------"

                (
                    open "$FINAL_URL" \
                    || xdg-open "$FINAL_URL" \
                    || termux-open-url "$FINAL_URL"
                ) >/dev/null 2>&1 &
            else
                echo "❌ Error: Cloud push failed (HTTP $HTTP_STATUS)."
                return 1
            fi
            ;;
    esac

    return 0
}
