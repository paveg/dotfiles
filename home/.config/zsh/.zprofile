# macOS's /etc/zprofile runs path_helper after ~/.zshenv, which moves the system
# directories ahead of what .zshenv set (measured).
path=($_dots_path $path)
