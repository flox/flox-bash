# Adapted from https://matthewbauer.us/blog/all-the-versions.html
{
  inputs.stable.url = "github:flox/nixpkgs/stable";
  inputs.staging.url = "github:flox/nixpkgs/staging";
  inputs.unstable.url = "github:flox/nixpkgs/unstable";

  description = "Flake providing multiple versions from various nixpkgs";

  outputs = { self, ...  } @ args: {
    legacyPackages = args.unstable.lib.genAttrs ["x86_64-linux"] (system: let
      nixpkgs = args.unstable;
      channels = builtins.attrNames (builtins.removeAttrs args ["self" ] );
      pkgSets = builtins.listToAttrs (map (c: { name= c; value = import args.${c} {
        inherit system;
        config.allowUnfree = true;
      };}) channels);

      # Make the versions attribute safe
      sanitizeVersionName = with builtins; with nixpkgs.lib.strings; string: nixpkgs.lib.pipe string [
        unsafeDiscardStringContext
        # Strip all leading "."
        (x: elemAt (match "\\.*(.*)" x) 0)
        (split "[^[:alnum:]+_?=-]+")
        # Replace invalid character ranges with a "-"
        (concatMapStrings (s: if nixpkgs.lib.isList s then "_" else s))
        (x: substring (nixpkgs.lib.max (stringLength x - 207) 0) (-1) x)
        (x: if stringLength x == 0 then "unknown" else x)
      ];

      getPkg = name: channel: let
        pkg = nixpkgs.lib.attrsets.attrByPath name null pkgSets.${channel};
        version = pkg.version or (builtins.parseDrvName pkg.name).version;
      in
        if pkg ? name then { name = sanitizeVersionName version; value = pkg; }
        else null;
    in
      nixpkgs.lib.attrsets.mapAttrsRecursiveCond
      (a: (a.recurseForDerivations or false || a.recurseForRelease or false) && !(a?type && a.type == "derivation" ))
      ( path: value: with builtins; let
           getVersions = listToAttrs (filter (x: x != null) (map (getPkg path) channels));
           getPrimary = head (sort (a: b: compareVersions a b >=0 ) (attrNames getVersions));
        in getVersions.${getPrimary} // {versions=getVersions;}
      )
      nixpkgs.legacyPackages.${system}
    );
  };
}
