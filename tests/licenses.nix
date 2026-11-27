# What one host installs, with its licence and the licence rules it breaks:
# one line per item, "|"-separated as source, name, licence, note, rules.
# Evaluation only. Read by tests/licenses.sh.
{ flake, host }:
let
  lib = flake.inputs.nixpkgs.lib;
  recorded = import "${flake.outPath}/nix/licenses.nix" { inherit lib; };
  user = (import "${flake.outPath}/hosts/${host}.nix").user;
  isDarwin = host != "wsl";
  configuration =
    if isDarwin then flake.darwinConfigurations.${host} else flake.homeConfigurations."${user}@wsl";
  system = configuration.config;
  home = if isDarwin then system.home-manager.users.${user} else system;
  nixpkgsConfig = configuration.pkgs.config;
  # The flake's allowance by name only: allowUnfree is not asked, because it
  # would admit every unfree package.
  admitsUnfree = pkg: (nixpkgsConfig.allowUnfreePredicate or (_: false)) pkg;

  licenseType = license: license.licenseType or "simple";

  # Fails closed: a bare string, or a licence without the field, does not hold.
  holds =
    field: license:
    if builtins.isList license then
      lib.all (holds field) license
    else if builtins.isString license then
      false
    else if licenseType license == "simple" then
      license.${field} or false
    else if licenseType license == "compound" && license.operator == "OR" then
      lib.any (holds field) license.licenses
    else if licenseType license == "compound" && license.operator == "AND" then
      lib.all (holds field) license.licenses
    else if licenseType license == "exception" then
      holds field license.license && holds field license.exception
    else if licenseType license == "plus" then
      holds field license.license
    else
      false;

  leaves =
    license:
    if builtins.isList license then
      lib.concatMap leaves license
    else if builtins.isString license then
      [ license ]
    else if licenseType license == "compound" then
      lib.concatMap leaves license.licenses
    else if licenseType license == "exception" then
      leaves license.license ++ leaves license.exception
    else if licenseType license == "plus" then
      leaves license.license
    else
      [ license ];

  # NC as a whole word of the id, so NCSA, a free licence, is no match, or
  # non-commercial in the full name, the only mark inria-compcert has. Every
  # leaf counts, an alternative of an OR included.
  isNonCommercial =
    leaf:
    let
      ids =
        if builtins.isString leaf then
          [ leaf ]
        else
          [
            (leaf.spdxId or "")
            (leaf.shortName or "")
          ];
      words = id: builtins.filter builtins.isString (builtins.split "[^a-z0-9]+" (lib.toLower id));
    in
    lib.any (id: builtins.elem "nc" (words id)) ids
    || builtins.match ".*non-?commercial.*" (lib.toLower (leaf.fullName or "")) != null;

  render =
    license:
    if builtins.isList license then
      "[${lib.concatMapStringsSep ", " render license}]"
    else if builtins.isString license then
      "\"${license}\""
    else if licenseType license == "simple" then
      license.spdxId or license.shortName or license.fullName or "?"
    else if licenseType license == "compound" then
      "(${lib.concatMapStringsSep " ${license.operator} " render license.licenses})"
    else if licenseType license == "exception" then
      "${render license.license} WITH ${render license.exception}"
    else if licenseType license == "plus" then
      "${render license.license}+"
    else
      "?";

  # license is null when nothing gives one, and an empty list or compound names
  # none; missing is the rule either breaks.
  row =
    {
      source,
      name,
      license,
      admitted,
      unfreeNote,
      missing,
      fromFile,
    }:
    let
      named = license != null && leaves license != [ ];
      rules =
        if !named then
          [ missing ]
        else
          lib.optional (lib.any isNonCommercial (leaves license)) "non-commercial"
          ++ lib.optional (!admitted && !holds "free" license) "unfree"
          ++ lib.optional (!admitted && !holds "redistributable" license) "non-redistributable";
      notes =
        lib.optional (named && admitted && !holds "free" license) unfreeNote
        ++ lib.optional (named && fromFile) "licence from nix/licenses.nix";
    in
    lib.concatStringsSep "|" [
      source
      name
      (if license == null then "none" else render license)
      (lib.concatStringsSep ", " notes)
      (lib.concatStringsSep " " rules)
    ];

  nixRow =
    source: pkg:
    let
      name = lib.getName pkg;
    in
    row {
      inherit source name;
      license = pkg.meta.license or recorded.generated.${name} or null;
      admitted = admitsUnfree pkg;
      unfreeNote = "unfree, allowed by name";
      missing = "no-licence";
      fromFile = !(pkg ? meta.license);
    };

  outsideRow =
    source: name:
    row {
      inherit source name;
      license = recorded.outsideNix.${host}.${name} or null;
      admitted = true;
      unfreeNote = "proprietary";
      missing = "no-entry";
      fromFile = true;
    };

  unreadRow =
    source: name: missing:
    row {
      inherit source name missing;
      license = null;
      admitted = true;
      unfreeNote = "";
      fromFile = false;
    };

  # Every `winget install` in design.md with arguments is a Windows-side install
  # for wsl; one with none names the command in prose.
  design = builtins.readFile "${flake.outPath}/docs/design.md";
  wingetArgumentLists = builtins.filter (arguments: arguments != [ ]) (
    map (
      match:
      builtins.filter (token: builtins.isString token && token != "") (
        builtins.split "[[:space:]]+" (builtins.head match)
      )
    ) (builtins.filter builtins.isList (builtins.split "winget install(([[:space:]][^`\n]*)?)" design))
  );
  # Every option `winget install` takes, by whether it takes a value: another
  # option makes the command unparsed.
  wingetQueryOptions = [
    "--id"
    "-q"
    "--query"
  ];
  wingetValueOptions = [
    "-m"
    "--manifest"
    "--name"
    "--moniker"
    "-v"
    "--version"
    "-s"
    "--source"
    "--scope"
    "-a"
    "--architecture"
    "--installer-type"
    "--locale"
    "-o"
    "--log"
    "--custom"
    "--override"
    "-l"
    "--location"
    "--dependency-source"
    "--header"
    "--authentication-mode"
    "--authentication-account"
    "-r"
    "--rename"
    "--proxy"
  ];
  wingetSwitches = [
    "-e"
    "--exact"
    "-i"
    "--interactive"
    "-h"
    "--silent"
    "--ignore-security-hash"
    "--allow-reboot"
    "--skip-dependencies"
    "--ignore-local-archive-malware-scan"
    "--accept-package-agreements"
    "--no-upgrade"
    "--accept-source-agreements"
    "--uninstall-previous"
    "--force"
    "-?"
    "--help"
    "--wait"
    "--logs"
    "--open-logs"
    "--verbose"
    "--verbose-logs"
    "--nowarn"
    "--ignore-warnings"
    "--disable-interactivity"
    "--no-proxy"
  ];
  # The packages that the arguments name, or null on an unknown option or one
  # that lacks its value.
  wingetPackages =
    arguments:
    let
      token = builtins.head arguments;
      rest = builtins.tail arguments;
      option = builtins.match "(-[^=]*)(=(.*))?" token;
      optionName = builtins.elemAt option 0;
      inlineValue = builtins.elemAt option 2;
      value = if inlineValue != null then inlineValue else builtins.head rest;
      afterValue = if inlineValue != null then rest else builtins.tail rest;
      hasValue = inlineValue != null || rest != [ ];
      prepend =
        names: remaining:
        let
          more = wingetPackages remaining;
        in
        if more == null then null else names ++ more;
    in
    if arguments == [ ] then
      [ ]
    else if option == null then
      prepend [ token ] rest
    else if builtins.elem optionName wingetSwitches && inlineValue == null then
      prepend [ ] rest
    else if builtins.elem optionName wingetQueryOptions && hasValue then
      prepend [ value ] afterValue
    else if builtins.elem optionName wingetValueOptions && hasValue then
      prepend [ ] afterValue
    else
      null;
  # winget installs every query it is given, so a command with two is unparsed
  # rather than read in part.
  wingetCommands = map (arguments: {
    inherit arguments;
    packages = wingetPackages arguments;
  }) wingetArgumentLists;
  isParsed = command: command.packages != null && builtins.length command.packages == 1;
  wingetIds = lib.unique (map (command: builtins.head command.packages) (builtins.filter isParsed wingetCommands));
  unparsedWinget = map (command: lib.concatStringsSep "_" command.arguments) (
    builtins.filter (command: !isParsed command) wingetCommands
  );
  # By how they install, each with the names it takes.
  installs =
    lib.optionalAttrs (host == "wsl") { winget = wingetIds; }
    // lib.optionalAttrs isDarwin {
      cask = map (cask: cask.name or cask) system.homebrew.casks;
      brew = map (brew: brew.name or brew) system.homebrew.brews;
    };
  # Brewfile lines given as raw text install what the lists above do not name.
  brewfileInstalls = builtins.filter (
    line: builtins.match "[[:space:]]*(cask|brew|mas)([^A-Za-z0-9_].*)?" line != null
  ) (lib.splitString "\n" system.homebrew.extraConfig);
  installed = lib.concatLists (lib.attrValues installs);
  byHand = builtins.filter (name: !builtins.elem name installed) (
    lib.attrNames recorded.outsideNix.${host}
  );
in
lib.concatMapStrings (line: line + "\n") (
  map (nixRow "home") home.home.packages
  ++ lib.optionals isDarwin (
    map (nixRow "system") system.environment.systemPackages ++ map (nixRow "font") system.fonts.packages
  )
  ++ lib.concatLists (lib.mapAttrsToList (source: map (outsideRow source)) installs)
  ++ lib.optionals (host == "wsl") (map (name: unreadRow "winget" name "unparsed") unparsedWinget)
  ++ lib.optional (isDarwin && brewfileInstalls != [ ]) (unreadRow "homebrew" "extraConfig" "unread")
  ++ map (outsideRow "by-hand") byHand
)
