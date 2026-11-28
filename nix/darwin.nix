{ pkgs, host, ... }:
let
  agents = import ./agents.nix { inherit pkgs; };
  # Claude Code skips a managed file it cannot read, so this is world-readable;
  # root owns it, so the agent cannot change it without sudo.
  managedSettings = "/Library/Application Support/ClaudeCode/managed-settings.d/50-dotfiles.json";
in
{
  nixpkgs.hostPlatform = host.system;

  # Determinate Nix manages Nix itself; nix-darwin aborts activation otherwise.
  nix.enable = false;

  system.primaryUser = host.user;
  # For GUI apps, which launchd starts without a shell.
  launchd.user.envVariables = {
    ORCA_TELEMETRY_DISABLED = "1";
    HOMEBREW_NO_ANALYTICS = "1";
  };
  # The ghtkn agent that holds every gh and git token (ADR 0004), the same
  # build as the ghtkn on PATH. It starts locked, so each start needs
  # `ghtkn agent unlock --enable-refresh`. Restarted only after a failure:
  # `ghtkn agent stop` exits 0.
  launchd.user.agents.ghtkn-agent.serviceConfig = {
    ProgramArguments = [
      (pkgs.lib.getExe pkgs.ghtkn)
      "agent"
      "start"
    ];
    RunAtLoad = true;
    KeepAlive.SuccessfulExit = false;
  };
  users.users.${host.user}.home = "/Users/${host.user}";
  system.stateVersion = 6;

  # extraActivation runs as root under `set -e`, before postActivation, where
  # home-manager writes settings.json: the drop-in is written first, and a
  # failure stops the switch before settings.json (spec/settings_writers.tla).
  system.activationScripts.extraActivation.text = ''
    echo "writing the Claude Code managed-settings drop-in" >&2
    ${pkgs.lib.getExe agents.claude-settings} managed ${host.profile} /Users/${host.user} ${pkgs.lib.escapeShellArg managedSettings}
  '';

  # $ZDOTDIR/.zshrc runs the one compinit, after it has put each profile's
  # completions on fpath, and sets its own prompt.
  programs.zsh = {
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };

  # The per-user profile links only environment.pathsToLink, and .zshrc sources
  # the plugins from these two directories in it.
  environment.pathsToLink = [
    "/share/zsh-autosuggestions"
    "/share/zsh-syntax-highlighting"
  ];

  home-manager = {
    useGlobalPkgs = true;
    # Packages land in /etc/profiles/per-user/<user>/bin, which $ZDOTDIR/.zshenv
    # puts on PATH.
    useUserPackages = true;
    extraSpecialArgs = { inherit host managedSettings; };
    users.${host.user} = ./home.nix;
  };
}
