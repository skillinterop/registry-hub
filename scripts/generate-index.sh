#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/hub-config.json"
OUTPUT_FILE="$ROOT_DIR/hub-index.json"
WORKSPACE_ROOT="${REGISTRY_WORKSPACE_ROOT:-$(dirname "$ROOT_DIR")}"
USE_LOCAL_SOURCES="${REGISTRY_USE_LOCAL_SOURCES:-0}"

raw_base_url() {
  printf '%s' "$1" | sed 's|^https://github.com/|https://raw.githubusercontent.com/|'
}

repo_name_from_url() {
  local repo_url="$1"
  repo_url="${repo_url%.git}"
  printf '%s' "${repo_url##*/}"
}

read_catalog() {
  local registry_type="$1"
  local repo_url="$2"
  local catalog_path="$3"
  local branch="$4"
  local raw_catalog_url="$5"
  local catalog

  if [ "$USE_LOCAL_SOURCES" = "1" ]; then
    local repo_name
    local local_catalog_path
    repo_name="$(repo_name_from_url "$repo_url")"
    local_catalog_path="$WORKSPACE_ROOT/$repo_name/$catalog_path"
    echo "Reading $registry_type from local checkout $local_catalog_path..." >&2
    if [ ! -f "$local_catalog_path" ]; then
      echo "ERROR: Missing local catalog for $registry_type at $local_catalog_path" >&2
      exit 1
    fi
    catalog="$(cat "$local_catalog_path")"
  else
    echo "Fetching $registry_type from $raw_catalog_url..." >&2
    if ! catalog="$(curl -sf --connect-timeout 10 --max-time 30 "$raw_catalog_url")"; then
      echo "ERROR: Failed to fetch $registry_type from $raw_catalog_url" >&2
      exit 1
    fi
  fi

  if ! echo "$catalog" | jq empty >/dev/null 2>&1; then
    if [ "$USE_LOCAL_SOURCES" = "1" ]; then
      echo "ERROR: Invalid JSON in local catalog for $registry_type" >&2
    else
      echo "ERROR: Invalid JSON from $raw_catalog_url" >&2
    fi
    exit 1
  fi

  printf '%s' "$catalog"
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
  CATALOG="$(read_catalog "$REGISTRY_TYPE" "$REPO_URL" "$CATALOG_PATH" "$BRANCH" "$RAW_CATALOG_URL")"

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

  echo "  -> $ITEM_COUNT items" >&2
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

echo "Generated $OUTPUT_FILE with $TOTAL_ITEMS items"
