#
# jq functions used by flox in the processing of manifest.json
#
# Usage:
#   jq -e -n -r -s -f <this file> \
#     --slurpfile manifest <path/to/manifest.json>
#     --args <function> <args>
#

# Start by defining some constants.

# String to be prepended to flox flake uri.
"@@FLOX_FLAKE_PREFIX@@" as $floxFlakePrefix
|
$ARGS.positional[0] as $function
|
$ARGS.positional[1:] as $args
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

def floxpkgToOriginalUri(arg):
  "flake:" + $floxFlakePrefix + (arg | split(".") | .[0]);

def floxpkgToAttrPath(arg):
  "legacyPackages." + $system + "." + (arg | split(".") | .[1:] | join("."));

def flakerefToOriginalUri(arg):
  arg | split("#") | .[0];

def flakerefToAttrPath(arg):
  arg | split("#") | .[1];

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
def floxpkgToElement(arg):
  $elements | map(select(
    (.attrPath == floxpkgToAttrPath(arg)) and
    (.originalUri == floxpkgToOriginalUri(arg))
  )) | .[0];

def flakerefToElement(arg):
  $elements | map(select(
    (.attrPath == flakerefToAttrPath(arg)) and
    (.originalUri == flakerefToOriginalUri(arg))
  )) | .[0];

def storepathToElement(arg):
  $elements | map(select(.storePaths | contains([arg]))) | .[0];

#
# Functions to look up element and return data in requested format.
#
def floxpkgToFlakeref(arg):
  floxpkgToElement(arg) | ( .originalUri + "#" + .attrPath );

def floxpkgToPosition(arg):
  floxpkgToElement(arg) | .position;

def flakerefToFloxpkg(arg):
  flakerefToElement(arg) | (
    originalUriToChannel(.originalUri) + "." +
    attrPathToStabilityPkgname(.attrPath)
  );

def flakerefToPosition(arg):
  flakerefToElement(arg) | .position;

def storepathToPosition(arg):
  storepathToElement(arg) | .position;

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
    error("excess argument: " + $args[1])
  elif $argc > 1 then
    error("excess arguments: " + ($args[1:] | join(" ")))
  elif $args[0] == "--out-path" then
    $elements | map(
      (.position | tostring) + " " + floxpkgFromElementWithRunPath
    ) | join("\n")
  else
    error("unknown option: " + $args[0])
  end;

#
# Call requested function with provided args.
# Think of this as this script's public API specification.
#
# XXX Convert to some better way using "jq -L"?
#
     if $function == "floxpkgToFlakeref"   then floxpkgToFlakeref($args[0])
else if $function == "flakerefToFloxpkg"   then flakerefToFloxpkg($args[0])
else if $function == "floxpkgToPosition"   then floxpkgToPosition($args[0])
else if $function == "flakerefToPosition"  then flakerefToPosition($args[0])
else if $function == "storepathToPosition" then storepathToPosition($args[0])
else if $function == "listProfile"         then listProfile($args)
else null end end end end end end
