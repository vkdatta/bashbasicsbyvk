handle_refresh() {
    local saved_path="$PWD"

    cd "$HOME" || return 1

    hash -r

    source "$HOME/.bashrc"

    exec bash -l -c 'cd -- "$1" && exec bash' bash "$saved_path"
}