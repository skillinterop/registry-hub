#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/hub-config.json"
OUTPUT_FILE="$ROOT_DIR/hub-index.json"

# Read hub version
HUB_VERSION=$(jq -r '.hubVersion' "$CONFIG_FILE")
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize arrays for aggregation
REGISTRIES_JSON="[]"
ITEMS_JSON="[]"

# Process each source
while IFS= read -r source; do
  REGISTRY_TYPE=$(echo "$source" | jq -r '.registryType')
  REPO_URL=$(echo "$source" | jq -r '.repoUrl')
  MANIFEST_PATH=$(echo "$source" | jq -r '.manifestPath')
  BRANCH=$(echo "$source" | jq -r '.branch')
  CHANNEL=$(echo "$source" | jq -r '.channel')

  # Convert repo URL to raw content URL
  # https://github.com/org/repo -> https://raw.githubusercontent.com/org/repo/branch/path
  RAW_URL=$(echo "$REPO_URL" | sed 's|github.com|raw.githubusercontent.com|')/"$BRANCH"/"$MANIFEST_PATH"

  echo "Fetching $REGISTRY_TYPE from $RAW_URL..."

  # Fetch manifest with timeout
  if ! MANIFEST=$(curl -sf --connect-timeout 10 --max-time 30 "$RAW_URL"); then
    echo "  WARNING: Failed to fetch $REGISTRY_TYPE from $RAW_URL" >&2
    MANIFEST='{"items":[]}'
  fi

  # Validate JSON
  if ! echo "$MANIFEST" | jq empty 2>/dev/null; then
    echo "  WARNING: Invalid JSON from $RAW_URL, skipping" >&2
    MANIFEST='{"items":[]}'
  fi

  # Filter items by channel and transform
  if [ "$CHANNEL" = "all" ]; then
    FILTERED_ITEMS=$(echo "$MANIFEST" | jq --arg repo "$REPO_URL" --arg type "$REGISTRY_TYPE" \
      '[.items[] | {
        canonicalId: .canonicalId,
        registryType: $type,
        name: .name,
        version: .version,
        description: .description,
        channel: .channel,
        sourceRepo: $repo
      }]')
  else
    FILTERED_ITEMS=$(echo "$MANIFEST" | jq --arg repo "$REPO_URL" --arg type "$REGISTRY_TYPE" --arg chan "$CHANNEL" \
      '[.items[] | select(.channel == $chan) | {
        canonicalId: .canonicalId,
        registryType: $type,
        name: .name,
        version: .version,
        description: .description,
        channel: .channel,
        sourceRepo: $repo
      }]')
  fi

  ITEM_COUNT=$(echo "$FILTERED_ITEMS" | jq 'length')

  # Add registry summary
  REGISTRY_SUMMARY=$(jq -n \
    --arg type "$REGISTRY_TYPE" \
    --arg url "$REPO_URL" \
    --argjson count "$ITEM_COUNT" \
    --arg updated "$GENERATED_AT" \
    '{registryType: $type, repoUrl: $url, itemCount: $count, lastUpdated: $updated}')

  REGISTRIES_JSON=$(echo "$REGISTRIES_JSON" | jq --argjson reg "$REGISTRY_SUMMARY" '. + [$reg]')
  ITEMS_JSON=$(echo "$ITEMS_JSON" | jq --argjson items "$FILTERED_ITEMS" '. + $items')

  echo "  -> $ITEM_COUNT items"

done < <(jq -c '.sources[]' "$CONFIG_FILE")

# Deduplicate by canonicalId (first occurrence wins - matches source priority)
ITEMS_JSON=$(echo "$ITEMS_JSON" | jq 'unique_by(.canonicalId)')
TOTAL_ITEMS=$(echo "$ITEMS_JSON" | jq 'length')

# Generate final hub-index.json
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
