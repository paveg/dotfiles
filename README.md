# dotfiles

**This dotfiles's main purpose is simple and maintainable, reproducibility.**

## Tools

- [Homebrew](https://brew.sh/)
- [AstroNvim](https://astronvim.com/)
- [alacritty](https://github.com/alacritty/alacritty)

## Installation

Prepare Homebrew as following command

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

And hit a script as following.

```bash
git clone paveg/dotfiles
./install.sh
```

## Maintenance

When you install some application from brew, you need to execute `brewbundle` and commit result.

```bash
# This command updates `.Brewfile`
brewbundle
```

### AstroNvim

If you track some changes upstream repo of the AstroNvim, it would be better to clone it again from template.

Note: https://docs.astronvim.com/

```bash
rm -rf $DOT_PATH/nvim
git clone --depth 1 https://github.com/AstroNvim/template $DOT_PATH/nvim
rm -rf $DOT_PATH/nvim/.git
```
