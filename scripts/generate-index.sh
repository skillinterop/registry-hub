#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/hub-config.json"
OUTPUT_FILE="$ROOT_DIR/hub-index.json"

raw_base_url() {
  printf '%s' "$1" | sed 's|^https://github.com/|https://raw.githubusercontent.com/|'
}

HUB_VERSION=$(jq -r '.hubVersion' "$CONFIG_FILE")
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REGISTRIES_JSON="[]"
ITEMS_JSON="[]"

while IFS= read -r source; do
  REGISTRY_TYPE=$(echo "$source" | jq -r '.registryType')
  REPO_URL=$(echo "$source" | jq -r '.repoUrl')
  CATALOG_PATH=$(echo "$source" | jq -r '.catalogPath')
  BRANCH=$(echo "$source" | jq -r '.branch')
  CHANNEL=$(echo "$source" | jq -r '.channel')
  RAW_BASE=$(raw_base_url "$REPO_URL")
  RAW_CATALOG_URL="${RAW_BASE}/${BRANCH}/${CATALOG_PATH}"

  echo "Fetching $REGISTRY_TYPE from $RAW_CATALOG_URL..."

  if ! CATALOG=$(curl -sf --connect-timeout 10 --max-time 30 "$RAW_CATALOG_URL"); then
    echo "  WARNING: Failed to fetch $REGISTRY_TYPE from $RAW_CATALOG_URL" >&2
    CATALOG='{"dataset":[]}'
  fi

  if ! echo "$CATALOG" | jq empty 2>/dev/null; then
    echo "  WARNING: Invalid JSON from $RAW_CATALOG_URL, skipping" >&2
    CATALOG='{"dataset":[]}'
  fi

  if [ "$CHANNEL" = "all" ]; then
    FILTERED_ITEMS=$(echo "$CATALOG" | jq --arg repo "$REPO_URL" --arg type "$REGISTRY_TYPE" --arg catalog "$RAW_CATALOG_URL" --arg rawBase "$RAW_BASE" --arg branch "$BRANCH" \
      '[.dataset[] | {
        canonicalId: .identifier,
        registryType: $type,
        name: .name,
        version: .version,
        description: .description,
        channel: .["skillinterop:channel"],
        status: .["skillinterop:status"],
        sourceRepo: $repo,
        sourceCatalog: $catalog,
        artifactPath: .url,
        artifactUrl: ($rawBase + "/" + $branch + "/" + (.url | ltrimstr("./")))
      }]')
  else
    FILTERED_ITEMS=$(echo "$CATALOG" | jq --arg repo "$REPO_URL" --arg type "$REGISTRY_TYPE" --arg catalog "$RAW_CATALOG_URL" --arg rawBase "$RAW_BASE" --arg branch "$BRANCH" --arg chan "$CHANNEL" \
      '[.dataset[] | select(.["skillinterop:channel"] == $chan) | {
        canonicalId: .identifier,
        registryType: $type,
        name: .name,
        version: .version,
        description: .description,
        channel: .["skillinterop:channel"],
        status: .["skillinterop:status"],
        sourceRepo: $repo,
        sourceCatalog: $catalog,
        artifactPath: .url,
        artifactUrl: ($rawBase + "/" + $branch + "/" + (.url | ltrimstr("./")))
      }]')
  fi

  ITEM_COUNT=$(echo "$FILTERED_ITEMS" | jq 'length')

  REGISTRY_SUMMARY=$(jq -n \
    --arg type "$REGISTRY_TYPE" \
    --arg url "$REPO_URL" \
    --arg catalog "$RAW_CATALOG_URL" \
    --argjson count "$ITEM_COUNT" \
    --arg updated "$GENERATED_AT" \
    '{registryType: $type, repoUrl: $url, catalogUrl: $catalog, itemCount: $count, lastUpdated: $updated}')

  REGISTRIES_JSON=$(echo "$REGISTRIES_JSON" | jq --argjson reg "$REGISTRY_SUMMARY" '. + [$reg]')
  ITEMS_JSON=$(echo "$ITEMS_JSON" | jq --argjson items "$FILTERED_ITEMS" '. + $items')

  echo "  -> $ITEM_COUNT items"

done < <(jq -c '.sources[]' "$CONFIG_FILE")

ITEMS_JSON=$(echo "$ITEMS_JSON" | jq 'unique_by(.canonicalId)')
TOTAL_ITEMS=$(echo "$ITEMS_JSON" | jq 'length')

jq -n \
  --arg version "$HUB_VERSION" \
  --arg generated "$GENERATED_AT" \
  --argjson total "$TOTAL_ITEMS" \
  --argjson registries "$REGISTRIES_JSON" \
  --argjson items "$ITEMS_JSON" \
  '{
    hubVersion: $version,
    generatedAt: $generated,
    totalItems: $total,
    registries: $registries,
    items: $items
  }' > "$OUTPUT_FILE"

echo ""
echo "Generated $OUTPUT_FILE with $TOTAL_ITEMS items"
