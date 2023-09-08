# dots

**This dotfiles's main purpose is simple and maintainable, reproducibility.**

## Materials

- [zsh](https://www.zsh.org/)
- [Starship](https://starship.rs/)
  - Kindly install it as `curl -sS https://starship.rs/install.sh | sh`
- Rust
  - rustup: `curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh`

### Commands

- [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep): `cargo install --locked ripgrep`
- [sharkdp/bat](https://github.com/sharkdp/bat): `cargo install --locked bat`
- [sharkdp/fd](https://github.com/sharkdp/fd): `cargo install --locked fd-find`
- [eza-community/eza](https://github.com/eza-community/eza): `cargo install --locked eza`

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
