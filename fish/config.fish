if status is-interactive
    # Home Manager generates these integrations in the managed configuration.
    # Keep them here for compatibility with the legacy symlink installer.
    starship init fish | source
    atuin init fish --disable-up-arrow | source

    source (path resolve (status dirname)/interactive.fish)
end
