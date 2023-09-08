# dots

**This dotfiles's main purpose is simple and maintainable, reproducibility.**

## Materials

- [zsh](https://www.zsh.org/)
- [Starship](https://starship.rs/): `curl -sS https://starship.rs/install.sh | sh`
- [asdf-vm](https://asdf-vm.com/):
- [Rust](https://www.rust-lang.org/)
  - rustup: `curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh`
- [Go](https://go.dev/)

### Commands

- [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep): `cargo install --locked ripgrep`
- [sharkdp/bat](https://github.com/sharkdp/bat): `cargo install --locked bat`
- [sharkdp/fd](https://github.com/sharkdp/fd): `cargo install --locked fd-find`
- [eza-community/eza](https://github.com/eza-community/eza): `cargo install --locked eza`
- [junegunn/fzf](https://github.com/junegunn/fzf): `cd fzf && ./install --xdg`
- [mislav/hub](https://github.com/mislav/hub): `sudo apt install hub`

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
