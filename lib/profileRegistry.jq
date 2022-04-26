# FIXME FIXME FIXME
#
# This is a copy of lib/registry.jq. It should instead be
# a module that first includes that file and then adds the
# profile-specific functions.
#
# FIXME FIXME FIXME
#
# jq functions for managing the flox registry.
#
# Analogous to ~/.cache/nix/flake-registry.json, the flox registry
# contains configuration data managed imperatively by flox CLI
# subcommands.
#
# Usage:
#   jq -e -n -r -s -f <this file> \
#     --arg version <version> \
#     --slurpfile registry <path/to/registry.json> \
#     --args <function> <funcargs>
#
$ARGS.positional[0] as $function
|
$ARGS.positional[1:] as $funcargs
|
($registry | .[]) as $registry
|

# Verify we're talking to the expected schema version.
if $registry.version != ($version | tonumber) then
  error(
    "unsupported registry schema version: " +
    ( $registry.version | tostring )
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
# Accessor methods.
#
def get(args):
  $registry | getpath(args) // empty;

def setNumber(args):
  $registry | setpath(args[0:-1]; (args[-1]|tonumber));

def setString(args):
  $registry | setpath(args[0:-1]; (args[-1]|tostring));

def set(args):
  setString(args);

def delete(args):
  $registry | delpaths([args]);

def addArrayNumber(args):
  $registry | setpath(
    args[0:-1];
    ( getpath(args[0:-1])? ) + [ (args[-1]|tonumber) ]
  );

def addArrayString(args):
  $registry | setpath(
    args[0:-1];
    ( getpath(args[0:-1])? ) + [ (args[-1]|tostring) ]
  );

def addArray(args):
  addArrayString(args);

def delArrayNumber(args):
  ( $registry | getpath(args[0:-1]) ) as $origarray |
  ( $origarray | index(args[-1]|tonumber) ) as $delindex |
  ( $origarray | del(.[$delindex]) ) as $newarray |
  $registry | setpath((args[0:-1]); $newarray);

def delArrayString(args):
  ( $registry | getpath(args[0:-1]) ) as $origarray |
  ( $origarray | index(args[-1]|tostring) ) as $delindex |
  ( $origarray | del(.[$delindex]) ) as $newarray |
  $registry | setpath((args[0:-1]); $newarray);

def delArray(args):
  delArrayString(args);

def dump(args): expectedArgs(0; args) |
  $registry;

def version(args): expectedArgs(0; args) |
  $registry | .version;

#
# Functions which present output directly to users.
#
def listGeneration:
  select(.value.created != null and .value.lastActive != null) |
  .key as $generation |
  (.value.created | todate) as $created |
  (.value.lastActive | todate) as $lastActive |
  # Cannot embed newlines so best we can do is return array and flatten later.
  [ "Generation \($generation):",
    "  Path:        \(.value.path)",
    "  Created:     \($created)",
    "  Last active: \($lastActive)" ] +
  if .value.logMessage != null then [
    "  Log entries:", (.value.logMessage | map("    \(.)"))
  ] else [] end;

def listGenerations(args):
  $registry | .generations | to_entries |
    map(listGeneration) | flatten | .[];

#
# Functions which generate script snippets.
#

# The process of generating a profile package is straightforward
# but requires that all storePaths referenced by the manifest are
# present on the system before invoking `nix profile build`. Take
# this opportunity to verify all the paths are present by invoking
# the `nix build` or `nix-store -r` commands that can create them.
def syncGeneration:
  .key as $generation |
  .value.path as $path |
  .value.created as $created |
  # Cannot embed newlines so best we can do is return array and flatten later.
  if .value.path != null then [
    # Ensure all flakes referenced in profile are built.
    "manifest $profileMetaDir/\($generation).json listFlakesInProfile | " +
    " $_xargs --no-run-if-empty $( [ -z \"$verbose\" ] || echo '--verbose' ) -- $_nix build --no-link && " +
    # Ensure all anonymous store paths referenced in profile are copied.
    "manifest $profileMetaDir/\($generation).json listStorePaths | " +
    " $_xargs --no-run-if-empty -n 1 -- $_sh -c '[ -d $0 ] || echo $0' | " +
    " $_xargs --no-run-if-empty --verbose -- $_nix_store -r && " +
    # Now we can attempt to build the profile and store in the bash $profilePath variable.
    "profilePath=$($_nix profile build $profileMetaDir/\($generation).json) && " +
    # Now create the generation link.
    "$_rm -f \($profileDir)/\($profileName)-\($generation)-link && " +
    "$_ln --force -s $profilePath \($profileDir)/\($profileName)-\($generation)-link && " +
    # And set the symbolic link's date.
    "$_touch -h --date=@\($created) \($profileDir)/\($profileName)-\($generation)-link && " +
    # Finally add a GC root for the new generation.
    "$_nix_store --add-root \($profileDir)/\($profileName)-\($generation)-link -r >/dev/null"
  ] else [] end;

def syncGenerations(args):
  ( $registry | .currentGen ) as $currentGen |
  ( $registry | .generations | to_entries ) | map(syncGeneration) + [
    # Set the current generation symlink. Let its timestamp be now.
    "$_rm -f \($profileDir)/\($profileName)",
    "$_ln --force -s \($profileName)-\($currentGen)-link \($profileDir)/\($profileName)"
  ] | flatten | .[];

#
# Call requested function with provided args.
# Think of this as this script's public API specification.
#
# XXX Convert to some better way using "jq -L"?
#
     if $function == "get"             then get($funcargs)
else if $function == "set"             then set($funcargs)
else if $function == "setNumber"       then setNumber($funcargs)
else if $function == "setString"       then setString($funcargs)
else if $function == "delete"          then delete($funcargs)
else if $function == "addArrayNumber"  then addArrayNumber($funcargs)
else if $function == "addArrayString"  then addArrayString($funcargs)
else if $function == "addArray"        then addArray($funcargs)
else if $function == "delArrayNumber"  then delArrayNumber($funcargs)
else if $function == "delArrayString"  then delArrayString($funcargs)
else if $function == "delArray"        then delArray($funcargs)
else if $function == "dump"            then dump($funcargs)
else if $function == "version"         then version($funcargs)
else if $function == "listGenerations" then listGenerations($funcargs)
else if $function == "syncGenerations" then syncGenerations($funcargs)
else error("unknown function: \"\($function)\"")
end end end end end end end end end end end end end end end
