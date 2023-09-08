# dots

**This dotfiles's main purpose is simple and maintainable, reproducibility.**

## Materials

- [zsh](https://www.zsh.org/)
- [Starship](https://starship.rs/): `curl -sS https://starship.rs/install.sh | sh`
- [asdf-vm](https://asdf-vm.com/): `git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.12.0`
- [Rust](https://www.rust-lang.org/)
  - rustup: `curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh`
- [Go](https://go.dev/): Install Go by asdf-vm

### Commands

- [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep): `cargo install --locked ripgrep`
- [sharkdp/bat](https://github.com/sharkdp/bat): `cargo install --locked bat`
- [sharkdp/fd](https://github.com/sharkdp/fd): `cargo install --locked fd-find`
- [eza-community/eza](https://github.com/eza-community/eza): `cargo install --locked eza`
- [denisidoro/navi](https://github.com/denisidoro/navi): `cargo install --locked navi`
- [junegunn/fzf](https://github.com/junegunn/fzf): `cd fzf && ./install --xdg`
- [mislav/hub](https://github.com/mislav/hub): `sudo apt install hub`
- [x-motemen/ghq](https://github.com/x-motemen/ghq): `go install github.com/x-motemen/ghq@latest`
- [nvbn/thefuck](https://github.com/nvbn/thefuck): `sudo apt install python3-dev python3-pip python3-setuptools; pip3 install thefuck --user`

## Installation

1. Preparation

   ```bash
   sudo apt update -y && sudo apt install zsh
   chsh -s /bin/zsh
   ```

2. Execution

   ```bash
   git clone https://github.com/paveg/dots
   cd ./dots
   ./dots.sh
   ```
