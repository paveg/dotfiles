# /etc/zprofile runs path_helper (macOS) or sources /etc/profile (Debian), both of
# which move the system directories ahead of what .zshenv set.
path=($_dots_path $path)
