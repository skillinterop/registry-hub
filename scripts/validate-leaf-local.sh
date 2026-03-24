#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/validate-leaf-local.sh --repo-root <leaf> --logical-root <logical-root> --schema-file <schema> --artifact-dir <dir> --artifact-file <file>" >&2
  exit 1
}

REPO_ROOT=""
LOGICAL_ROOT=""
SCHEMA_FILE=""
ARTIFACT_DIR=""
ARTIFACT_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --logical-root)
      LOGICAL_ROOT="$2"
      shift 2
      ;;
    --schema-file)
      SCHEMA_FILE="$2"
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --artifact-file)
      ARTIFACT_FILE="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$REPO_ROOT" ] || [ -z "$LOGICAL_ROOT" ] || [ -z "$SCHEMA_FILE" ] || [ -z "$ARTIFACT_DIR" ] || [ -z "$ARTIFACT_FILE" ]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(dirname "$SCRIPT_DIR")"
INDEX_PATH="$REPO_ROOT/index.jsonld"
LOGICAL_INDEX_PATH="$LOGICAL_ROOT/index.jsonld"
COMMON_SCHEMA="$HUB_DIR/schemas/shared/common.schema.json"
JSONLD_SCHEMA="$HUB_DIR/schemas/shared/jsonld-catalog.schema.json"
SCHEMA_TEMP_DIR="$(mktemp -d)"
COMMON_SCHEMA_ALIAS="$SCHEMA_TEMP_DIR/common.schema.raw-id.json"

cleanup() {
  rm -rf "$SCHEMA_TEMP_DIR"
}
trap cleanup EXIT

if [ ! -d "$HUB_DIR/node_modules/ajv" ] || [ ! -d "$HUB_DIR/node_modules/ajv-formats" ]; then
  echo "FAIL registry-hub-repo/node_modules: ajv runtime dependencies not found" >&2
  exit 1
fi

if [ ! -f "$INDEX_PATH" ]; then
  echo "FAIL $LOGICAL_INDEX_PATH: file not found at $INDEX_PATH" >&2
  exit 1
fi

python3 - <<'PY' "$COMMON_SCHEMA" "$COMMON_SCHEMA_ALIAS"
import json, sys
source, target = sys.argv[1], sys.argv[2]
with open(source) as f:
    data = json.load(f)
data["$id"] = "https://raw.githubusercontent.com/skillinterop/registry-hub/main/schemas/shared/common.schema.json"
with open(target, "w") as f:
    json.dump(data, f, indent=2)
PY

if ! output=$(node - "$HUB_DIR" "$INDEX_PATH" "$SCHEMA_FILE" "$COMMON_SCHEMA" "$COMMON_SCHEMA_ALIAS" "$JSONLD_SCHEMA" <<'NODE' 2>&1
const fs = require('fs');
const path = require('path');
const Ajv = require(path.join(process.argv[2], 'node_modules/ajv'));
const addFormats = require(path.join(process.argv[2], 'node_modules/ajv-formats'));

const [, , hubDir, dataPath, schemaPath, commonSchemaPath, commonAliasPath, jsonLdSchemaPath] = process.argv;
const ajv = new Ajv({ strict: false, allErrors: true, validateFormats: true });
addFormats(ajv);
const load = (filePath) => JSON.parse(fs.readFileSync(filePath, 'utf8'));
ajv.addSchema(load(commonSchemaPath));
ajv.addSchema(load(commonAliasPath));
ajv.addSchema(load(jsonLdSchemaPath));
const validate = ajv.compile(load(schemaPath));
const data = load(dataPath);
if (!validate(data)) {
  console.error(ajv.errorsText(validate.errors, { separator: '; ' }));
  process.exit(1);
}
NODE
); then
  output="$(echo "$output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  echo "FAIL $LOGICAL_INDEX_PATH: $output" >&2
  exit 1
fi

while IFS=$'\t' read -r name url; do
  if [ -z "$name" ] || [ -z "$url" ]; then
    continue
  fi

  expected_url="./$ARTIFACT_DIR/$name/$ARTIFACT_FILE"
  if [ "$url" != "$expected_url" ]; then
    echo "FAIL $LOGICAL_INDEX_PATH: dataset url for $name must equal $expected_url (found $url)" >&2
    exit 1
  fi

  artifact_path="$REPO_ROOT/${url#./}"
  if [ ! -f "$artifact_path" ]; then
    echo "FAIL $LOGICAL_INDEX_PATH: artifact not found at $artifact_path" >&2
    exit 1
  fi
done < <(jq -r '.dataset[] | [.name, .url] | @tsv' "$INDEX_PATH")

echo "OK $LOGICAL_INDEX_PATH"
