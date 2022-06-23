#!/usr/bin/env bash
set -eu
attrPath="$1"
stability="$2"
channel="$3"
system=$(nix show-config | grep "system =" | cut -f3 -d' ')

attrPathAsArray=$(nix eval --expr "\"$attrPath\"" --apply '(x: builtins.filter builtins.isString (builtins.split "\\." x))' --json)

# Eval-time
drvAttrs="$(nix eval --json .#"${attrPath}.drvAttrs" )"
meta="$(nix eval --json .#"${attrPath}.meta" )"
version="$(echo "$drvAttrs" | jq .version)"
name="$(echo "$drvAttrs" | jq .name)"
pname="$(echo "$drvAttrs" | jq .pname)"
outPath="$(nix eval --json .#"${attrPath}.outPath" )"

# Build-time
buildJson=$(nix build .#"$attrPath" --json)
drvPath=$(echo "$buildJson" | jq .[0].drvPath -r)
outputs=$(echo "$buildJson" | jq .[0].outputs)
drv=${drvPath##"/nix/store/"}
timeToBuild=$( (stat "/nix/var/log/nix/drvs/${drv:0:2}/${drv:2}.bz2" -t | awk '{print $14 - $15}' ) || echo 0)

# Run-time
command nix profile install --profile ./tmp-profile ".#$attrPath"
element=$(jq '.elements[0]' ./tmp-profile/manifest.json)
rm tmp-profile*

cat <<EOF
{
  "eval": {
    "flake": {
      "locked": $(nix flake metadata --json | jq .locked),
      "original": $(nix flake metadata --json | jq .original)
    },
    "attrPath": $attrPathAsArray,
    "name": $name,
    "pname": $pname,
    "drvPath": "$drvPath",
    "outPath": $outPath,
    "outputs": $outputs,
    "version": $version,
    "meta": $meta,
    "stability": "$stability",
    "channel": "$channel"
  },
  "build": {
    "drvPath": "$drvPath",
    "hasBin": $(stat ./result/bin >/dev/null || stat ./result-bin/bin >/dev/null && echo true || echo false),
    "hasMan": $(stat ./result/man >/dev/null && echo true || echo false),
    "outputs": $outputs,
    "size": "$(nix path-info --json ./result | jq .[0].narsize)",
    "system": "$system",
    "timeToBuild": $timeToBuild
  },
  "cache":
  [
    {
      "cacheUrl": "localhost",
      "registrationTime": $(nix path-info --json ./result | jq .[0].registrationTime),
      "narinfo": $(nix path-info --json ./result)
    }
  ],
  "element": $element
}
EOF
