#
# jq functions for managing the flox registry.
#
# Analogous to ~/.cache/nix/flake-registry.json, the flox registry
# contains configuration data managed imperatively by flox CLI
# subcommands.
#
# Usage:
#   jq -e -n -r -s -f <this file> \
#     --slurpfile registry <path/to/registry.json>
#     --args <function> <funcargs>
#
$ARGS.positional[0] as $function
|
$ARGS.positional[1:] as $funcargs
|
($registry | .[]) as $registry
|

# Verify we're talking to the expected schema version.
if $registry.version != 1 then
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
def get(args): expectedArgs(1; args) |
  $registry.data | .[args[0]];

def setNumber(args): expectedArgs(2; args) |
  $registry * { "data": {(args[0]): (args[1] | tonumber)} };

def setString(args): expectedArgs(2; args) |
  $registry * { "data": {(args[0]): (args[1] | tostring)} };

def set(args):
  setString(args);

def del(args): expectedArgs(1; args) |
  $registry | delpaths([["data",args[0]]]);

def dump(args): expectedArgs(0; args) |
  $registry;

def version(args): expectedArgs(0; args) |
  $registry | .version;

#
# Call requested function with provided args.
# Think of this as this script's public API specification.
#
# XXX Convert to some better way using "jq -L"?
#
     if $function == "get"       then get($funcargs)
else if $function == "set"       then set($funcargs)
else if $function == "setNumber" then setNumber($funcargs)
else if $function == "setString" then setString($funcargs)
else if $function == "del"       then del($funcargs)
else if $function == "dump"      then dump($funcargs)
else if $function == "version"   then version($funcargs)
else error("unknown function: \"\($function)\"")
end end end end end end end
