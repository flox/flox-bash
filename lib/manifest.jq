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
"@@FLOX_FLAKE_PREFIX@@" as $floxFlakePrefix
|
$ARGS.positional[0] as $function
|
$ARGS.positional[1:] as $funcargs
|

# Verify we're talking to the expected schema version.
if $manifest[].version != 1 then
  error(
    "unsupported manifest schema version: " +
    ( $manifest[].version | tostring )
  )
else . end
|

# Add "position" index as we define $elements.
( $manifest[].elements | to_entries | map(.value * {position:.key}) ) as $elements
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
# flake:@@FLOX_FLAKE_PREFIX@@<channel>#legacyPackages.<system>.<stability>.<pkgname>
#
# Sample element:
# {
#   "active": true,
#   "attrPath": "legacyPackages.@@SYSTEM@@.stable.vim",
#   "originalUri": "flake:@@FLOX_FLAKE_PREFIX@@nixpkgs",
#   "storePaths": [ "/nix/store/hjxr78h4ia3x6h51zf2inzfphsfq8njm-vim-8.2.4186" ],
#   "uri": "git+ssh://git@github.com/flox/builtpkgs?ref=master&rev=279633e152a0ae46311cf8bbb159e41a9159cfd0",
#   "position": 3
# }
#
def originalUriToChannel(arg):
  arg | ltrimstr("flake:" + $floxFlakePrefix);

def attrPathToStabilityPkgname(arg):
  arg | ltrimstr("legacyPackages." + $system + ".");

def floxpkgToOriginalUri(args): expectedArgs(1; args) |
  "flake:" + $floxFlakePrefix + (args[0] | split(".") | .[0]);

def floxpkgToAttrPath(args): expectedArgs(1; args) |
  "legacyPackages." + $system + "." + (args[0] | split(".") | .[1:] | join("."));

def flakerefToOriginalUri(args): expectedArgs(1; args) |
  args[0] | split("#") | .[0];

def flakerefToAttrPath(args): expectedArgs(1; args) |
  args[0] | split("#") | .[1];

def floxpkgFromElement:
  [
    originalUriToChannel(.originalUri),
    attrPathToStabilityPkgname(.attrPath)
  ] | join(".");

def floxpkgFromElementWithRunPath:
  ([
    originalUriToChannel(.originalUri),
    attrPathToStabilityPkgname(.attrPath)
  ] | join(".")) + "\t" + (.storePaths | join(","));

#
# Functions to look up elements.
#
def floxpkgToElement(args): expectedArgs(1; args) |
  $elements | map(select(
    (.attrPath == floxpkgToAttrPath(args)) and
    (.originalUri == floxpkgToOriginalUri(args))
  )) | .[0];

def flakerefToElement(args): expectedArgs(1; args) |
  $elements | map(select(
    (.attrPath == flakerefToAttrPath(args)) and
    (.originalUri == flakerefToOriginalUri(args))
  )) | .[0];

def storepathToElement(args): expectedArgs(1; args) |
  $elements | map(select(.storePaths | contains([args[0]]))) | .[0];

#
# Functions to look up element and return data in requested format.
#
def floxpkgToFlakeref(args): expectedArgs(1; args) |
  floxpkgToElement(args) | ( .originalUri + "#" + .attrPath );

def floxpkgToPosition(args): expectedArgs(1; args) |
  floxpkgToElement(args) | .position;

def flakerefToFloxpkg(args): expectedArgs(1; args) |
  flakerefToElement(args) | (
    originalUriToChannel(.originalUri) + "." +
    attrPathToStabilityPkgname(.attrPath)
  );

def flakerefToPosition(args): expectedArgs(1; args) |
  flakerefToElement(args) | .position;

def storepathToPosition(args): expectedArgs(1; args) |
  storepathToElement(args) | .position;

def positionToFloxpkg(args): expectedArgs(1; args) |
  $elements[args[0] | tonumber] | (
    originalUriToChannel(.originalUri) + "." +
    attrPathToStabilityPkgname(.attrPath)
  );

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
else if $function == "dump"                then dump($funcargs)
else error("unknown function: \"\($function)\"")
end end end end end end end end
