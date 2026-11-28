#!/usr/bin/env bash
# Break one condition of the package wiring at a time and require the checks in
# tests/packages.sh that cover it to fail. A surviving mutant means those checks
# prove nothing. The per-tool checks are mutated through `git` (which /usr/bin
# also has) and `claude` (which it does not). These checks have no mutant:
# host-user, profile-facts, build-home-files, build-system, build-generation and
# etc-zshrc-generated guard this harness rather than the files under test, and
# generation-home-path is home-manager's own link to the profile this test
# already built.
# The per-user group reads the built macOS system, so it needs a mac; CI runs
# it in the darwin jobs and the common group on the Linux runner. The per-host
# group's mutants depend on the host, so every job runs it.
# Usage: tests/mutate-packages.sh [group]
#        group: all (default), common, per-user, per-host
# Env: DOTFILES_HOST and ZSH_BIN are passed through to tests/packages.sh.
set -uo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
group=${1:-all}
default_host=wsl
[[ $(uname -s) == Darwin ]] && default_host=personal-mac
host=${DOTFILES_HOST:-$default_host}

# shellcheck source=tests/lib/mutate.sh
source "$repo_dir/tests/lib/mutate.sh"

runs() { # <group>
  [[ $group == all || $group == "$1" ]]
}

copied=(flake.nix flake.lock hosts nix home)
run_mutant() { # <dir> <check>... <file> <old> <new>
  local dir=$1 checks=$2 file=$3 old=$4 new=$5 entry out
  for entry in "${copied[@]}"; do
    cp -R "$repo_dir/$entry" "$dir/$entry"
  done
  mutate_apply "$dir/$file" "$old" "$new" || return
  out=$("$repo_dir/tests/packages.sh" "$dir" 2>&1) || true
  # shellcheck disable=SC2086 # one check name per word
  mutate_checks_failed "$out" $checks
}

expect_caught() { # <check>... <description> <file> <old> <new>
  mutant "$2" run_mutant "$1" "$3" "$4" "$5"
}

mutate_inputs "${copied[@]}" tests/packages.sh tests/mutate-packages.sh tests/lib/
mutate_baseline 'the files as committed' "$repo_dir/tests/packages.sh"

if runs common; then
  # git is the case that matters most: /usr/bin has one, so a dropped package is
  # answered by the system copy rather than by "not found".
  expect_caught 'bin-git zsh-git package-names' 'git is dropped from the list' \
    nix/packages.nix $'    git\n' ''

  expect_caught 'bin-claude zsh-claude package-names' 'Claude Code is dropped from the list' \
    nix/packages.nix $'    claude-code\n' ''

  expect_caught 'package-names plugin-zsh-syntax-highlighting' \
    'the syntax-highlighting plugin is dropped from the list' \
    nix/packages.nix $'    zsh-syntax-highlighting\n' ''

  expect_caught 'package-names' 'the real gh is added next to the wrapper, which needs its name' \
    nix/packages.nix $'    atuin\n  ]\n' $'    atuin\n    gh\n  ]\n'

  expect_caught gh-is-wrapper 'the real gh is installed in place of the wrapper' \
    nix/vaults.nix 'home.packages = [ builds.gh ];' 'home.packages = [ pkgs.gh ];'

  expect_caught 'bin-gh zsh-gh package-names gh-is-wrapper' 'the gh wrapper is not installed' \
    nix/vaults.nix $'  home.packages = [ builds.gh ];\n' ''

  expect_caught completion-gh 'the wrapper brings no zsh completion' \
    nix/ghtkn.nix $'        ln -s ${pkgs.gh}/share/zsh/site-functions/_gh $out/share/zsh/site-functions/_gh\n' ''

  expect_caught 'package-names' 'a language runtime is installed globally' \
    nix/packages.nix $'    atuin\n  ]\n' $'    atuin\n    nodejs\n  ]\n'

  expect_caught 'unfree-admitted build-profile' 'the unfree allowance no longer names claude-code' \
    flake.nix '[ "claude-code" ]' '[ ]'

  expect_caught 'unfree-allow-unfree unfree-admitted' 'every unfree package is allowed' \
    flake.nix 'allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];' \
    'allowUnfree = true;'

  expect_caught 'unfree-admitted' 'the unfree predicate admits a second name' \
    flake.nix '[ "claude-code" ]' '[ "claude-code" "unrar" ]'

  expect_caught 'unfree-admitted' 'the unfree predicate admits anything it is asked about' \
    flake.nix 'pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ]' 'pkg: true'

  expect_caught 'unfree-admitted' 'the unfree predicate matches a prefix of the name' \
    flake.nix 'builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ]' \
    'nixpkgs.lib.hasPrefix "claude-code" (nixpkgs.lib.getName pkg)'

  expect_caught 'real-dir-.config/zsh real-dir-.config/mise real-dir-.config/atuin' \
    'the zsh directory is linked as a whole' \
    nix/home.nix $'      "zsh/.zshenv"\n      "zsh/.zprofile"\n      "zsh/.zshrc"\n      "mise/config.toml"\n      "atuin/config.toml"\n' \
    $'      "zsh"\n'

  expect_caught 'real-dir-.config/mise' 'the mise directory is linked as a whole' \
    nix/home.nix '"mise/config.toml"' '"mise"'

  # The platform file goes too: a link inside a linked directory fails the build.
  expect_caught 'real-dir-.config/git' 'the git directory is linked as a whole' \
    nix/home.nix \
    $'      "git/config"\n      "git/ignore"\n      "git/personal.gitconfig"\n    ] (path: {\n      source = link ".config/${path}";\n    })\n    // {\n      # The 1Password signer, and on wsl the ssh command, under the one name the git config includes.\n      "git/platform.gitconfig".source = link ".config/git/${platform}.gitconfig";\n    };\n' \
    $'      "git"\n    ] (path: {\n      source = link ".config/${path}";\n    });\n'

  expect_caught 'link-.config/git/personal.gitconfig' 'the personal identity is not linked' \
    nix/home.nix $'      "git/personal.gitconfig"\n' ''

  expect_caught 'link-.config/git/platform.gitconfig' 'the other OS'"'"'s signer is linked' \
    nix/home.nix 'then "darwin" else "wsl"' 'then "wsl" else "darwin"'

  expect_caught 'link-.config/atuin/config.toml real-dir-.config/atuin' 'the atuin config is not linked' \
    nix/home.nix $'      "atuin/config.toml"\n' ''

  expect_caught 'link-.config/zsh/.zshrc link-.config/mise/config.toml link-.config/atuin/config.toml link-.config/git/config' \
    'the files are copied into the store instead of linked out of it' \
    nix/home.nix '    source = link ".config/${path}";' '    source = ../home/.config/${path};'

  expect_caught 'link-.zshenv link-.config/zsh/.zshrc' 'the links point at a checkout somewhere else' \
    nix/home.nix '"${config.home.homeDirectory}/repos/github.com/paveg/dotfiles"' '"/tmp/elsewhere/dotfiles"'

  expect_caught 'link-.zshenv' 'the top-level .zshenv is not linked at all' \
    nix/home.nix $'  home.file.".zshenv".source = link ".zshenv";\n' ''

  expect_caught 'link-.zshenv' 'the top-level .zshenv is copied into the store' \
    nix/home.nix 'link ".zshenv"' '../home/.zshenv'

  expect_caught 'mise-refuses-asdf mise-disable-backends' 'the global mise config allows the asdf backend' \
    home/.config/mise/config.toml 'disable_backends = ["asdf"]' 'disable_backends = []'

  expect_caught 'mise-disable-backends' 'the global mise config disables a backend the projects use' \
    home/.config/mise/config.toml 'disable_backends = ["asdf"]' 'disable_backends = ["asdf", "aqua"]'

  expect_caught 'atuin-reads-config' 'the atuin config sets a style atuin does not have' \
    home/.config/atuin/config.toml 'style = "compact"' 'style = "bogus"'
fi

if runs per-user; then
  if [[ $host == wsl ]]; then
    mutate_na "the per-user profile checks need a macOS host, and this run is on $host"
  else
    expect_caught 'per-user-git per-user-claude' 'the packages never reach the per-user profile' \
      nix/darwin.nix $'    useUserPackages = true;\n' ''

    expect_caught launchd-ORCA_TELEMETRY_DISABLED 'GUI apps never get ORCA_TELEMETRY_DISABLED' \
      nix/darwin.nix $'    ORCA_TELEMETRY_DISABLED = "1";\n' ''

    expect_caught launchd-HOMEBREW_NO_ANALYTICS 'GUI apps get HOMEBREW_NO_ANALYTICS with another value' \
      nix/darwin.nix 'HOMEBREW_NO_ANALYTICS = "1";' 'HOMEBREW_NO_ANALYTICS = "0";'

    expect_caught 'launchd-ORCA_TELEMETRY_DISABLED launchd-HOMEBREW_NO_ANALYTICS' \
      'the variables go to the system domain, not the user'"'"'s' \
      nix/darwin.nix 'launchd.user.envVariables = {' 'launchd.envVariables = {'

    expect_caught 'plugin-zsh-autosuggestions plugin-zsh-syntax-highlighting' \
      'the per-user profile does not link the plugin directories' \
      nix/darwin.nix $'    "/share/zsh-autosuggestions"\n    "/share/zsh-syntax-highlighting"\n' ''

    expect_caught etc-zshrc-no-compinit "nix-darwin's /etc/zshrc runs compinit before .zshrc" \
      nix/darwin.nix $'    enableCompletion = false;\n' ''

    expect_caught etc-zshrc-no-compinit "nix-darwin's /etc/zshrc runs bashcompinit" \
      nix/darwin.nix $'    enableBashCompletion = false;\n' ''

    expect_caught etc-zshrc-no-promptinit "nix-darwin's /etc/zshrc loads a prompt theme" \
      nix/darwin.nix $'    promptInit = "";\n' ''

    expect_caught 'agent-launchd-command agent-launchd-restart' 'the ghtkn agent never runs on macOS' \
      nix/darwin.nix \
      $'  launchd.user.agents.ghtkn-agent.serviceConfig = {\n    ProgramArguments = [\n      (pkgs.lib.getExe pkgs.ghtkn)\n      "agent"\n      "start"\n    ];\n    RunAtLoad = true;\n    KeepAlive.SuccessfulExit = false;\n  };\n' ''

    expect_caught agent-launchd-command 'the LaunchAgent runs ghtkn agent without start' \
      nix/darwin.nix $'      "agent"\n      "start"\n' $'      "agent"\n'

    expect_caught agent-launchd-restart 'the LaunchAgent restarts the agent after ghtkn agent stop too' \
      nix/darwin.nix 'KeepAlive.SuccessfulExit = false;' 'KeepAlive = true;'

    expect_caught agent-launchd-restart 'the agent does not start at login' \
      nix/darwin.nix $'    RunAtLoad = true;\n' ''
  fi
fi

# The host's own packages: what one host adds must not reach another.
if runs per-host; then
  if [[ $host == work-mac ]]; then
    expect_caught 'bin-peco zsh-peco package-names' 'work-mac loses peco' \
      hosts/work-mac.nix 'packages = pkgs: [ pkgs.peco ];' 'packages = pkgs: [ ];'

    expect_caught 'bin-peco zsh-peco package-names' 'the host list is never added to the profile' \
      nix/packages.nix $'  ]\n  ++ host.packages pkgs;\n' $'  ];\n'
  else
    expect_caught package-names "$host gets peco too" \
      "hosts/$host.nix" 'packages = pkgs: [ ];' 'packages = pkgs: [ pkgs.peco ];'

    expect_caught package-names 'peco moves into the list every host gets' \
      nix/packages.nix $'    atuin\n  ]\n' $'    atuin\n    peco\n  ]\n'
  fi

  personal_app_link='{ "ghtkn/gh-app".source = linkHome ".config/ghtkn/gh-app.personal"; }'
  if [[ $host == work-mac ]]; then
    expect_caught 'link-.config/ghtkn/ghtkn.yaml link-.config/ghtkn/gh-app' \
      'work-mac links the personal app instead of the work profile'"'"'s files' \
      nix/vaults.nix 'if host.profile == "work" then' 'if false then'

    expect_caught 'link-.config/ghtkn/ghtkn.yaml link-.config/ghtkn/gh-app' \
      'work-mac links the ghtkn files from outside the work profile'"'"'s ghtkn directory' \
      nix/vaults.nix '/.config/dots-work/ghtkn/${name}' '/.config/dots-work/${name}'

    expect_caught activation-no-ghtkn-render 'work-mac renders the personal ghtkn.yaml over its link' \
      nix/vaults.nix 'home.activation.ghtknConfig = lib.mkIf personal (' 'home.activation.ghtknConfig = lib.mkIf true ('
  else
    expect_caught 'activation-ghtkn-render activation-ghtkn-template' "$host never renders ghtkn.yaml" \
      nix/vaults.nix 'home.activation.ghtknConfig = lib.mkIf personal (' 'home.activation.ghtknConfig = lib.mkIf false ('

    if [[ $host == wsl ]]; then
      expect_caught activation-keeps-switch-path 'wsl empties the activation PATH, so the render step finds no op.exe' \
        nix/vaults.nix $'  home.emptyActivationPath = lib.mkIf (personal && !isDarwin) false;\n' ''
    else
      expect_caught activation-ghtkn-render "$host looks op up on a PATH that nix-darwin's activation does not give it" \
        nix/vaults.nix 'then "/usr/local/bin/op" else' 'then "op" else'
    fi

    expect_caught activation-ghtkn-render "$host calls the other OS's op" \
      nix/vaults.nix 'then "/usr/local/bin/op" else "op.exe"' 'then "op.exe" else "/usr/local/bin/op"'

    expect_caught activation-ghtkn-render "$host renders a file ghtkn does not read" \
      nix/vaults.nix '/ghtkn/ghtkn.yaml"}' '/ghtkn/config.yaml"}'

    expect_caught link-.config/ghtkn/gh-app "$host gives gh no app" \
      nix/vaults.nix "$personal_app_link" '{ }'

    expect_caught 'link-.config/ghtkn/gh-app not-linked-.config/ghtkn/ghtkn.yaml' \
      "$host links the work profile's ghtkn files" \
      nix/vaults.nix 'if host.profile == "work" then' 'if true then'

    expect_caught real-dir-.config/ghtkn "$host links the ghtkn directory as a whole, so ghtkn.yaml lands in the checkout" \
      nix/vaults.nix "$personal_app_link" '{ "ghtkn".source = linkHome ".config/ghtkn"; }'
  fi

  ssh_line='home.file.".ssh/config" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin { source = ./ssh_config; };'
  if [[ $host == wsl ]]; then
    expect_caught ssh-config 'wsl gets the macOS ssh config' \
      nix/home.nix 'lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {' 'lib.mkIf true {'

    expect_caught 'agent-systemd-command agent-systemd-enabled' 'wsl gets no ghtkn agent' \
      nix/vaults.nix 'systemd.user.services.ghtkn-agent = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {' \
      'systemd.user.services.ghtkn-agent = lib.mkIf false {'

    expect_caught agent-systemd-command 'the unit restarts the agent after ghtkn agent stop too' \
      nix/vaults.nix 'Restart = "on-failure";' 'Restart = "always";'

    expect_caught agent-systemd-enabled 'the unit is installed but never started' \
      nix/vaults.nix $'    Install.WantedBy = [ "default.target" ];\n' ''
  else
    expect_caught ssh-config "$host gets no ssh config" \
      nix/home.nix "  $ssh_line"$'\n' ''

    expect_caught ssh-config 'the ssh config links into the checkout, where an edit changes it live' \
      nix/home.nix 'source = ./ssh_config;' 'source = config.lib.file.mkOutOfStoreSymlink "${checkout}/nix/ssh_config";'

    expect_caught ssh-config 'another file is installed as the ssh config' \
      nix/home.nix 'source = ./ssh_config;' 'source = ../home/.config/git/ignore;'
  fi
fi

mutate_context="group $group, host $host"
mutate_finish
