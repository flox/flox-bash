{
  description = "Built packages";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  nixConfig.substituters = ["https://storehouse.beta.floxdev.com" "https://cache.nixos.org"];
  nixConfig.extra-trusted-public-keys = ["storehouse.beta.floxdev.com:lkSTQtvEYXvCPDl3kBX4omHiDTiIF6xZ/q2OmRVRZw4="];

  # can put this into a "channel-like" location with hashed-mirrors?
  # inputs.db.url = "https://storehouse.beta.floxdev.com/channels/pkgs.json.tar.gz";

  outputs = { self, nixpkgs, # db,
  }: let
    supportedSystems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
    nixpkgsFor = forAllSystems (system: import nixpkgs {inherit system;});

    config = with builtins; fromTOML (readFile ./urls.toml);
  in rec {

    legacyPackages = with builtins; let
      database = fromJSON (readFile ./pkgs.json);
      pkgs = nixpkgs.lib.attrsets.mapAttrsRecursiveCond
      (a: !a ? path) ( path: value: nixpkgs.lib.attrsets.attrByPath path {}
        (builtins.getFlake "github:flox/nixpkgs/${value.nixpkgs}").outputs.legacyPackages
      ) database;
    in pkgs;

    firewallPackages = with builtins; let database = fromJSON (readFile ./pkgs.json);
    in nixpkgs.lib.attrsets.mapAttrsRecursiveCond
      (a: !a ? path) (
        path: value: let system = with builtins; elemAt path 0; in
          # This is required because top-level builds need a drvPath, upstream bug?
          (nixpkgsFor.${system}.pkgs.buildEnv {
            name = "wrapper";
            meta = let m = (nixpkgs.lib.attrByPath path {} nixpkgsFor);
            e = tryEval m;
            in if e.success && e.value?meta then e.value.meta else {};
            paths = [ {
              type = "derivation";
              outPath = storePath value.path;
      }];}))
      database;

    # Re-factor when impure derivations exist
    floxPackages = forAllSystems (
      system:
        builtins.mapAttrs (
          n: v: let
            hydraUrl = builtins.elemAt config.${n} 0;
            project = builtins.elemAt config.${n} 1;
          in
            nixpkgs.lib.mapAttrsRecursiveCond
            (as: !(as ? "type" && as.type == "derivation"))
            ( path: x:
                nixpkgs.lib.genAttrs ["stable" "unstable" "staging" "master"]
                (
                  stability: {
                    type = "app";
                    program = with nixpkgs.legacyPackages.${system};
                      (
                        writeScript "latest.sh" ''
                          # Get the latest build
                          IFS=' ' read drvpath drvattr drvid < <(echo $(
                           ${curl}/bin/curl -qs \
                            -H "Content-Type: application/json" \
                            -L https://beta.floxdev.com/api/derivations/${project}/${stability}/${builtins.concatStringsSep "." path} \
                            -H "cookie: $COOKIE" \
                            | ${jq}/bin/jq '.[0]|.drvPath,.drvAttrName,.drvID' -rc
                            ))

                          # Get the evaluation information
                          IFS=' ' read nixpath < <(echo $(
                           ${curl}/bin/curl -qs \
                            -H "Content-Type: application/json" \
                            -H "cookie: $COOKIE" \
                            -L https://beta.floxdev.com/api/derivation/"$drvid"/outputs \
                            | ${jq}/bin/jq '.derivations[] | select(.outType == "out").nixStoreKey' -rc
                            ))

                           # To do, save original flakeref or attrpath to make updgrades nice
                           ${nixUnstable}/bin/nix profile install \
                             --profile $PWD/flox-profile \
                             --substituters ${hydraUrl} \
                             --experimental-features 'nix-command flakes' \
                             --option extra-trusted-public-keys "storehouse.beta.floxdev.com:lkSTQtvEYXvCPDl3kBX4omHiDTiIF6xZ/q2OmRVRZw4=" \
                             /nix/store/"$nixpath"
                           echo Added /nix/store/"$nixpath" to $PWD/flox-profile >&2
                        ''
                      )
                      .outPath;
                  }
                )
            )
            (nixpkgsFor.${system} // {ssentr = {type = "derivation";};})
        )
        config
    );
    livePackages = forAllSystems (
      system:
        builtins.mapAttrs (
          n: v: let
            hydraUrl = builtins.elemAt config.${n} 0;
            project = builtins.elemAt config.${n} 1;
          in
            nixpkgs.lib.mapAttrsRecursiveCond
            (as: !(as ? "type" && as.type == "derivation"))
            ( path: x:
                nixpkgs.lib.genAttrs ["stable" "unstable" "staging" "master"]
                (
                  stability: {
                    type = "app";
                    program = with nixpkgs.legacyPackages.${system};
                      (
                        writeScript "latest.sh" ''
                          # Get the latest build
                          IFS=' ' read drvpath out job eval < <(echo $(
                           ${curl}/bin/curl -qs \
                            -H "Content-Type: application/json" \
                            -L ${hydraUrl}/job/${project}/${stability}/${builtins.concatStringsSep "." path}.${system}/latest \
                            | ${jq}/bin/jq '.drvpath,.buildoutputs.out.path,.job,.jobsetevals[0]' -rc
                            ))

                          # Get the evaluation information
                          IFS=' ' read flake < <(echo $(
                           ${curl}/bin/curl -qs \
                            -H "Content-Type: application/json" \
                            -L ${hydraUrl}/eval/"$eval" \
                            | ${jq}/bin/jq '.flake' -rc
                            ))

                           # echo drvpath: $drvpath >&2
                           # echo out: $out >&2
                           # echo job: $job >&2
                           # echo eval: $eval >&2
                           # echo flake: $flake >&2
                           if [ "$flake" = "null" ]; then
                            uri="$out"
                           else
                            uri="$flake#hydraJobs.$job"
                            ${nixUnstable}/bin/nix eval $flake#hydraJobs.$job.meta --json | ${jq}/bin/jq >&2
                           fi
                           # --substituters ${hydraUrl} \
                           ${nixUnstable}/bin/nix profile install \
                             --profile $PWD/flox-profile \
                             --experimental-features 'nix-command flakes' \
                             "$uri"
                           echo Added "$uri" to $PWD/flox-profile >&2
                        ''
                      )
                      .outPath;
                  }
                )
            )
            (nixpkgsFor.${system} // {ssentr = {type = "derivation";};})
        )
        config
    );
  };
}
