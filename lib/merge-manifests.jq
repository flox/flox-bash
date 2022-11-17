# Invoke with:
#   cat current/manifest.json new/manifest.json | \
#     jq -s -f lib/mergemanifests.jq --argjson replace (0|1)

# Need to eliminate the tuple of originalUrl and attrPath,
# so define helper function which combines these into a new
# attribute that can be used with the unique_by() function,
# then remove it from the stream after duplicates are removed.
def unique_by_flake_url:
  map(
    # Put final package name at front to keep things sorted by pname.
    ( .attrPath | split(".") | .[2:] | join(".") ) as $pname |
    . * {"flakeUrl": "\($pname):\(.originalUrl)#\(.attrPath)"}
  ) |
  unique_by(.flakeUrl) |
  map(. | del(.flakeUrl));

def merge(prev; new):
  ( prev | .elements // [] ) as $prevElements |
  ( new | .elements ) as $newElements |
  ( prev * ( new * {
    "elements": ($newElements + $prevElements) | unique_by_flake_url
  } ) );

reduce .[] as $x (
  # INIT: sets initial value of "."
  {};
  # UPDATE: takes "." as input, replaces "."
  merge(.;$x)
)
