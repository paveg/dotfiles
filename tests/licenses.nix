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
  # The flake's own allowance, asked the way nixpkgs asks it.
  admitsUnfree =
    pkg: nixpkgsConfig.allowUnfree || (nixpkgsConfig.allowUnfreePredicate or (_: false)) pkg;

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

  # NC as a whole word of the id, so NCSA, a free licence, is no match. Every
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
    lib.any (id: builtins.elem "nc" (words id)) ids;

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

  # license is null when nothing names one; missing is the rule that breaks.
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
      rules =
        if license == null then
          [ missing ]
        else
          lib.optional (lib.any isNonCommercial (leaves license)) "non-commercial"
          ++ lib.optional (!admitted && !holds "free" license) "unfree"
          ++ lib.optional (!admitted && !holds "redistributable" license) "non-redistributable";
      notes =
        lib.optional (license != null && admitted && !holds "free" license) unfreeNote
        ++ lib.optional (license != null && fromFile) "licence from nix/licenses.nix";
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

  # Every `winget install` in design.md is a Windows-side install for wsl.
  design = builtins.readFile "${flake.outPath}/docs/design.md";
  wingetIds = lib.unique (
    map (match: builtins.elemAt match 1) (
      builtins.filter builtins.isList (builtins.split "winget install (--id )?([A-Za-z0-9.]+)" design)
    )
  );
  # By how they install, each with the names it takes.
  installs =
    lib.optionalAttrs (host == "wsl") { winget = wingetIds; }
    // lib.optionalAttrs isDarwin {
      cask = map (cask: cask.name or cask) system.homebrew.casks;
      brew = map (brew: brew.name or brew) system.homebrew.brews;
    };
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
  ++ map (outsideRow "by-hand") byHand
)
