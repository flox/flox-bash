#
# jq functions used by flox in the processing of manifest.json
#
# Usage:
#   jq -r -s -f <this file> \
#     --args <function> <args> \
#     < <path/to/manifest.json>
#

# Start by defining some constants.
"@@SYSTEM@@" as $system # TODO: make this an input
|
# String to be prepended to flox flake uri.
"@@FLOX_FLAKE_PREFIX@@" as $floxFlakePrefix
|
$ARGS.positional[0] as $function
|
$ARGS.positional[1] as $arg
|

# Pull input into $manifest variable.
. as $manifest
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
# Call requested function with provided args.
# XXX Convert to library using jq's "-L" and "--raw-input" flags.
#
     if $function == "floxpkgToFlakeref"   then floxpkgToFlakeref($arg)
else if $function == "flakerefToFloxpkg"   then flakerefToFloxpkg($arg)
else if $function == "floxpkgToPosition"   then floxpkgToPosition($arg)
else if $function == "flakerefToPosition"  then flakerefToPosition($arg)
else if $function == "storepathToPosition" then storepathToPosition($arg)
else null end end end end end
