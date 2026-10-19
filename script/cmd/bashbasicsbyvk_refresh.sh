handle_refresh() {
    local saved_path="$PWD"

    cd "$HOME" || return 1

    hash -r

    # no "source ~/.bashrc" here: the interactive bash started below reads it itself

    exec bash -l -c 'cd -- "$1" && exec bash' bash "$saved_path"
}