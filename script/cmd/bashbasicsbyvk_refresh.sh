handle_refresh() {
    local saved_path="$PWD"

    cd "$HOME" || return 1

    hash -r

    # exec skips the EXIT trap and keeps the same PID: stop the loading-bar animator (and the loadtime log) first, or it
    # outlives this shell, never sees the wait end and keeps drawing its bar over the new shell, with no way to close it
    declare -F _lt_cleanup >/dev/null 2>&1 && _lt_cleanup

    # no "source ~/.bashrc" here: the interactive bash started below reads it itself

    exec bash -l -c 'cd -- "$1" && exec bash' bash "$saved_path"
}