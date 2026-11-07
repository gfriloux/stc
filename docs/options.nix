# The option reference — generated from the modules, never written by hand.
#
# Every visible stc.relics.* / stc.cogitator.* option is rendered to Markdown,
# one fragment per declaring source file and per language, under
# docs/src/options/{en,fr}/<slug>.md. The fragments are committed; the pages
# import them (`import Options from '.../options/en/<slug>.md'; <Options />`).
# checks.options-doc rebuilds them and fails on any difference, so a changed
# type, default or description cannot drift from its page. `just options-doc`
# regenerates them.
#
# Measured choices (see .claude/plans/v0.25.0/options-reference.md):
#   - One evaluation per class, of STC's own files only. The exported
#     wrappers also import upstream modules (impermanence, disko, …) that are
#     functions, which the module system cannot deduplicate: importing every
#     wrapper at once declares environment.persistence twice. Their path
#     imports are kept, and each upstream module is imported once from
#     `upstream` below. A wrapper gaining an upstream module missing there
#     fails this evaluation ("option … does not exist") as soon as an STC file
#     sets one of its options. One evaluation per module instead
#     took CI's all-systems check past the runner's 16 GB (measured: 11.7 GiB
#     on main, 16.1 GiB with ~45 evaluations).
#   - Keyed by class, then name: stc.relics.yubikey.enable exists both as a
#     NixOS and a Home Manager option, in two files. A merge by name alone
#     drops one of them.
#   - Submodule internals (`<path>.<name>._module.*`) come out visible and are
#     filtered by name. Deprecated stc.* aliases are invisible already.
#   - A default computed from the configuration (`config.networking.hostName`)
#     renders this evaluation's value unless the option sets `defaultText`.
#     The base modules carry a sentinel host name and home, and any rendered
#     value holding one of them, or a store path, fails the build.
#
# x86_64-linux only: option docs do not depend on the system.
{
  self,
  inputs,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    sentinel = "options-doc-sentinel";
    base = {
      system.stateVersion = "25.11";
      networking.hostName = sentinel;
      boot.loader.grub.enable = false;
      fileSystems."/".device = "none";
    };
    hbase = {
      home.username = sentinel;
      home.homeDirectory = "/home/${sentinel}";
      home.stateVersion = "25.11";
    };

    keep = o:
      o.visible
      && !(lib.hasInfix "._module." o.name)
      && (lib.hasPrefix "stc.relics." o.name || lib.hasPrefix "stc.cogitator." o.name);

    optionsOf = options: builtins.filter keep (lib.optionAttrSetToDocList options.stc);

    # Exported modules come wrapped by flake-parts (`{ _file; imports; }`) and
    # sometimes by STC (`{...}: { imports = [...]; }`); the paths inside are
    # STC's files. A function that requires arguments is an upstream module.
    unwrap = m:
      if builtins.isPath m
      then [m]
      else if builtins.isFunction m
      then lib.optionals (builtins.functionArgs m == {}) (lib.concatMap unwrap ((m {}).imports or []))
      else lib.concatMap unwrap (m.imports or []);

    ownFiles = modules: lib.concatMap unwrap (builtins.attrValues modules);

    # Every upstream module the exported wrappers import (relics/default.nix,
    # cogitator/default.nix), once each.
    upstream = {
      nixos = [
        inputs.impermanence.nixosModules.impermanence
        inputs.disko.nixosModules.disko
      ];
      home = [
        inputs.plasma-manager.homeModules.plasma-manager
        inputs.zen-browser.homeModules.beta
        inputs.gitflow-toolkit.homeModules.gitflow-toolkit
        inputs.catppuccin.homeModules.catppuccin
        inputs.television-ssh.homeModules.default
      ];
    };

    nixosOptions =
      optionsOf
      (lib.nixosSystem {
        inherit system;
        modules = ownFiles self.nixosModules ++ upstream.nixos ++ [base];
      }).options;

    homeOptions =
      optionsOf
      (inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = ownFiles self.homeModules ++ upstream.home ++ [hbase];
      }).options;

    # Deduplicated within a class, never across: the same option is reached
    # through every module that imports its relic.
    byName = opts: builtins.attrValues (lib.listToAttrs (map (o: lib.nameValuePair o.name o) opts));

    textOf = v:
      lib.trim (
        if v._type or null == "literalMD"
        then v.text
        else v.text or (builtins.toJSON v)
      );

    relative = d: lib.removePrefix "${self}/" (toString d);

    leaks = o:
      lib.any (v: lib.hasInfix sentinel v || lib.hasInfix "/nix/store/" v)
      (map textOf (lib.optional (o ? default) o.default ++ lib.optional (o ? example) o.example));

    checked = o:
      if builtins.length o.declarations != 1
      then throw "options-doc: ${o.name} is declared in ${toString (builtins.length o.declarations)} files"
      else if (o.description or null) == null || lib.trim o.description == ""
      then throw "options-doc: ${o.name} has no description"
      else if leaks o
      then throw "options-doc: ${o.name} renders a value of the doc evaluation: give it a defaultText"
      else o // {file = relative (builtins.head o.declarations);};

    options = map checked (byName nixosOptions ++ byName homeOptions);

    byFile = lib.groupBy (o: o.file) options;

    # docker-guards.nix and docker/guards.nix would share a slug.
    slugs = map slug (builtins.attrNames byFile);
    uniqueSlugs =
      if builtins.length (lib.unique slugs) == builtins.length slugs
      then slugs
      else throw "options-doc: two declaring files map to the same slug";

    slug = file: lib.replaceStrings ["/"] ["-"] (lib.removeSuffix ".nix" file);

    labels = {
      en = {
        type = "Type";
        default = "Default";
        required = "none, required when used";
        example = "Example";
        declared = "Declared in";
      };
      fr = {
        type = "Type";
        default = "Valeur par défaut";
        required = "aucune, requise à l'usage";
        example = "Exemple";
        declared = "Déclarée dans";
      };
    };

    # A one-line value stays inline; anything with a newline or a backtick goes
    # in a fenced block, where it cannot break the surrounding Markdown.
    value = label: v: let
      text = textOf v;
    in
      if lib.hasInfix "\n" text || lib.hasInfix "`" text
      then "- **${label}:**\n\n  ```nix\n${lib.concatMapStringsSep "\n" (l: "  ${l}") (lib.splitString "\n" text)}\n  ```"
      else "- **${label}:** `${text}`";

    renderOption = l: o:
      lib.concatStringsSep "\n" (
        [
          "#### `${o.name}`"
          ""
          (lib.trim o.description)
          ""
          "- **${l.type}:** `${o.type}`"
        ]
        # Every option without a default is one the consumer must set.
        ++ [
          (
            if o ? default
            then value l.default o.default
            else "- **${l.default}:** *${l.required}*"
          )
        ]
        ++ lib.optional (o ? example) (value l.example o.example)
        ++ ["- **${l.declared}:** [`${o.file}`](https://github.com/gfriloux/stc/blob/main/${o.file})"]
      );

    renderFile = lang: opts:
      lib.concatStringsSep "\n\n" (
        ["<!-- Generated by docs/options.nix — run `just options-doc`, do not edit. -->"]
        ++ map (renderOption labels.${lang}) (lib.sortOn (o: o.name) opts)
      )
      + "\n";

    optionsDoc = builtins.seq uniqueSlugs pkgs.linkFarm "stc-options-doc" (lib.concatLists (lib.mapAttrsToList (file: opts:
      map (lang: {
        name = "${lang}/${slug file}.md";
        path = pkgs.writeText "${slug file}-${lang}.md" (renderFile lang opts);
      }) ["en" "fr"])
    byFile));
  in
    lib.optionalAttrs (system == "x86_64-linux") {
      legacyPackages.options-doc = optionsDoc;

      # Drift, then coverage: every fragment is imported by a page in each
      # language, and that page renders it (an import alone shows nothing).
      checks.options-doc = pkgs.runCommand "options-doc" {} ''
        if ! diff -r ${optionsDoc} ${self}/docs/src/options; then
          echo
          echo "The option reference is out of date: run \`just options-doc\` and commit docs/src/options."
          exit 1
        fi

        missing=0
        for slug in ${lib.concatStringsSep " " uniqueSlugs}; do
          for lang in en fr; do
            found=0
            for page in $(grep -rl --include='*.mdx' "/options/$lang/$slug.md'" ${self}/docs/src/content/docs/$lang); do
              name=$(sed -n "s|^import \([A-Za-z0-9_]*\) from '.*/options/$lang/$slug.md';\$|\1|p" "$page")
              if [ -n "$name" ] && grep -qx "<$name />" "$page"; then
                found=1
              fi
            done
            if [ "$found" = 0 ]; then
              echo "$lang: no page renders options/$lang/$slug.md — import it from its page (en and fr)."
              missing=1
            fi
          done
        done
        [ "$missing" = 0 ] || exit 1
        touch $out
      '';
    };
}
