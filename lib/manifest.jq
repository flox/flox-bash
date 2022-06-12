#
# jq functions used by flox in the processing of manifest.json
#
# Usage:
#   jq -e -n -r -s -f <this file> \
#     --slurpfile manifest <path/to/manifest.json>
#     --args <function> <funcargs>
#

# Start by defining some constants.

# String to be prepended to flox flake uri.
"flake:floxpkgs" as $floxpkgsUri # making explicit for debugging
|
$ARGS.positional[0] as $function
|
$ARGS.positional[1:] as $funcargs
|

# Verify we're talking to the expected schema version.
if $manifest[].version != 1 and $manifest[].version != 2 then
  error(
    "unsupported manifest schema version: " +
    ( $manifest[].version | tostring )
  )
else . end
|

# Helper method to validate number of arguments to function call.
def expectedArgs(count; args):
  (args | length) as $argc |
  if $argc < count then
    error("too few arguments \($argc) - was expecting \(count)")
  elif $argc > count then
    error("too many arguments \($argc) - was expecting \(count)")
  else . end;

#
# Functions which convert between flakeref and floxpkg tuple elements.
#
# floxpkg: <channel>.<stability>.<pkgname> (fully-qualified)
# flake:floxpkgs#catalog.<system>.<channel>.<stability>.<pkgname>
#
# Sample element:
# {
#   "active": true,
#   "attrPath": "$catalogAttrPathPrefix.nixpkgs.stable.vim",
#   "originalUrl": "flake:floxpkgs",
#   "storePaths": [
#     "/nix/store/ivwgm9bdsvhnx8y7ac169cx2z82rwcla-vim-8.2.4350"
#   ],
#   "url": "github:flox-examples/companypkgs/ef23087ad88d59f0c0bc0f05de65577009c0c676",
#   "position": 3
# }
#
#

# Convert flake attrPath to floxpkgs <channel>.<stability>.<name> triple.
def attrPathToFloxpkg(arg):
  arg |
  ltrimstr("catalog.\($system).") | # XXX FIXME once the dust settles.
  ltrimstr("\($catalogAttrPathPrefix).");

# Add "position" index as we define $elements.
( $manifest[].elements | to_entries | map(
  .value * {
    position:.key,
    packageName: (
      if .value.attrPath then (
        attrPathToFloxpkg(.value.attrPath)
        | split(".")
        | .[0] as $channel
        | .[1] as $stability
        | (.[2:] | join("."))
      ) else (
        .value.storePaths[0] | .[44:]
      ) end
    )
  }
) ) as $elements
|

def attrPathToTOML(arg):
  attrPathToFloxpkg(arg) | split(".") |
  .[0] as $channel |
  .[1] as $stability |
  (.[2:] | join(".")) as $nameAttrPath |
  "  [packages.\"\($nameAttrPath)\"]
  channel = \"\($channel)\"
  stability = \"\($stability)\"
";

def storePathsToTOML(storePaths):
  ( "\"" + ( storePaths | join("\",\n      \"") ) + "\"" ) as $storePaths |
  ( storePaths[0] | .[44:] ) as $pkgname |
  "  [packages.\"\($pkgname)\"]
  storePaths = [
    \($storePaths)
  ]
";

def floxpkgToAttrPath(args): expectedArgs(1; args) |
  ["catalog", $system, args[0]] | join(".");

def flakerefToAttrPath(args): expectedArgs(1; args) |
  args[0] | split("#") | .[1];

def floxpkgToFlakeref(args): expectedArgs(1; args) |
  floxpkgToAttrPath(args) as $attrPath |
  "\($floxpkgsUri)#\(.attrPath)";

def flakerefToFloxpkg(args): expectedArgs(1; args) |
  flakerefToAttrPath(args) as $attrPath |
  attrPathToFloxpkg($attrPath);

def floxpkgFromElementV1:
  if .attrPath then
    if ( .originalUri == $floxpkgsUri ) then
      attrPathToFloxpkg(.attrPath)
    else
      "\(.originalUri)#\(.attrPath)"
    end
  else .storePaths[] end;
def floxpkgFromElementV2:
  if .attrPath then
    if ( .originalUrl == $floxpkgsUri ) then
      attrPathToFloxpkg(.attrPath)
    else
      "\(.originalUrl)#\(.attrPath)"
    end
  else .storePaths[] end;
def floxpkgFromElement:
  if $manifest[].version == 2 then
    floxpkgFromElementV2
  else
    floxpkgFromElementV1
  end;

def floxpkgFromElementWithRunPath:
  if .attrPath then
    attrPathToFloxpkg(.attrPath) + "\t" + (.storePaths | join(","))
  else .storePaths[] end;

def TOMLFromElement:
  if .attrPath then
    attrPathToTOML(.attrPath)
  else
    storePathsToTOML(.storePaths)
  end;

def flakerefFromElementV1:
  "\(.originalUri)#\(.attrPath)";
def flakerefFromElementV2:
  "\(.originalUrl)#\(.attrPath)";
def flakerefFromElement:
  if $manifest[].version == 2 then
    flakerefFromElementV2(args)
  else
    flakerefFromElementV1(args)
  end;

def lockedFlakerefFromElementV1:
  "\(.uri)#\(.attrPath)";
def lockedFlakerefFromElementV2:
  "\(.url)#\(.attrPath)";
def lockedFlakerefFromElement:
  if $manifest[].version == 2 then
    lockedFlakerefFromElementV2
  else
    lockedFlakerefFromElementV1
  end;

#
# Functions to look up element and return data in requested format.
#

def floxpkgToElementV1(args): expectedArgs(1; args) |
  $elements | map(select(
    (.attrPath == floxpkgToAttrPath(args)) and
    (.originalUri == $floxpkgsUri)
  )) | .[0];
def floxpkgToElementV2(args): expectedArgs(1; args) |
  $elements | map(select(
    (.attrPath == floxpkgToAttrPath(args)) and
    (.originalUrl == $floxpkgsUri)
  )) | .[0];
def floxpkgToElement(args):
  if $manifest[].version == 2 then
    floxpkgToElementV2(args)
  else
    floxpkgToElementV1(args)
  end;

def flakerefToElementV1(args): expectedArgs(1; args) |
  $elements | map(select(
    (.attrPath == flakerefToAttrPath(args)) and
    (.originalUri == $floxpkgsUri)
  )) | .[0];
def flakerefToElementV2(args): expectedArgs(1; args) |
  $elements | map(select(
    (.attrPath == flakerefToAttrPath(args)) and
    (.originalUrl == $floxpkgsUri)
  )) | .[0];
def flakerefToElement(args):
  if $manifest[].version == 2 then
    flakerefToElementV2(args)
  else
    flakerefToElementV1(args)
  end;

def storepathToElement(args): expectedArgs(1; args) |
  $elements | map(select(.storePaths | contains([args[0]]))) | .[0];

def floxpkgToPosition(args): expectedArgs(1; args) |
  floxpkgToElement(args) | .position;

def flakerefToPosition(args): expectedArgs(1; args) |
  flakerefToElement(args) | .position;

def storepathToPosition(args): expectedArgs(1; args) |
  storepathToElement(args) | .position;

def positionToFloxpkg(args): expectedArgs(1; args) |
  $elements[args[0] | tonumber] | floxpkgFromElement;

#
# Functions which present output directly to users.
#
def listProfile(args):
  (args | length) as $argc |
  if $argc == 0 then
    $elements | map(
      (.position | tostring) + " " + floxpkgFromElement
    ) | join("\n")
  elif $argc == 2 then
    error("excess argument: " + args[1])
  elif $argc > 1 then
    error("excess arguments: " + (args[1:] | join(" ")))
  elif args[0] == "--out-path" then
    $elements | map(
      (.position | tostring) + " " + floxpkgFromElementWithRunPath
    ) | join("\n")
  else
    error("unknown option: " + args[0])
  end;

def listProfileTOML(args): expectedArgs(0; args) |
  $elements | sort_by(.packageName) | unique_by(.packageName) |
    map( TOMLFromElement) as $TOMLelements |
  (["[packages]"] + $TOMLelements) | join("\n");

def listFlakesInProfile(args): expectedArgs(0; args) |
  ( $elements | map(
    if .attrPath then lockedFlakerefFromElement else empty end
  ) ) as $flakesInProfile |
  if ($flakesInProfile | length) == 0 then " " else ($flakesInProfile | .[]) end;

def listStorePaths(args): expectedArgs(0; args) |
  ( $elements | map(.storePaths) | flatten ) as $anonStorePaths |
  if ($anonStorePaths | length) == 0 then " " else ($anonStorePaths | .[]) end;

# For debugging.
def dump(args): expectedArgs(0; args) |
  $manifest | .[];

#
# Call requested function with provided args.
# Think of this as this script's public API specification.
#
# XXX Convert to some better way using "jq -L"?
#
     if $function == "floxpkgToFlakeref"   then floxpkgToFlakeref($funcargs)
else if $function == "flakerefToFloxpkg"   then flakerefToFloxpkg($funcargs)
else if $function == "floxpkgToPosition"   then floxpkgToPosition($funcargs)
else if $function == "flakerefToPosition"  then flakerefToPosition($funcargs)
else if $function == "storepathToPosition" then storepathToPosition($funcargs)
else if $function == "positionToFloxpkg"   then positionToFloxpkg($funcargs)
else if $function == "listProfile"         then listProfile($funcargs)
else if $function == "listProfileTOML"     then listProfileTOML($funcargs)
else if $function == "listFlakesInProfile" then listFlakesInProfile($funcargs)
else if $function == "listStorePaths"      then listStorePaths($funcargs)
else if $function == "dump"                then dump($funcargs)
else error("unknown function: \"\($function)\"")
end end end end end end end end end end end
