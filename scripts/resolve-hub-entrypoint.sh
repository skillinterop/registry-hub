#!/bin/bash
set -euo pipefail

CATALOG_PATH="${1:-registry-catalog.jsonld}"

if [ ! -f "$CATALOG_PATH" ]; then
  echo "Catalog not found: $CATALOG_PATH" >&2
  exit 1
fi

if ! jq empty "$CATALOG_PATH" >/dev/null 2>&1; then
  echo "Catalog is not valid JSON: $CATALOG_PATH" >&2
  exit 1
fi

jq '{
  registries: [
    .hasPart[] | {
      name,
      registryType: .["skillinterop:registryType"],
      url
    }
  ],
  hubIndexUrl: (
    if (.distribution // []) | length > 0
    then .distribution[0].contentUrl
    else null
    end
  )
}' "$CATALOG_PATH"
