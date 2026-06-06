#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required" >&2
  exit 1
fi

for city in "$@"; do
  encoded=$(printf '%s' "$city" | jq -s -R -r @uri)
  resp=$(curl -sS "https://geocoding-api.open-meteo.com/v1/search?name=${encoded}&count=1")
  results=$(echo "$resp" | jq '.results // empty')
  if [ -z "$results" ]; then
    echo "Error: no results for '$city'" >&2
    exit 1
  fi
  name=$(echo "$resp" | jq -r '.results[0].name')
  lat=$(echo "$resp" | jq -r '.results[0].latitude')
  lon=$(echo "$resp" | jq -r '.results[0].longitude')
  echo "%{name: \"${name}\", lat: ${lat}, lon: ${lon}},"
done
