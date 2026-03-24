#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$HUB_DIR")"

COMMON_SCHEMA="$HUB_DIR/schemas/shared/common.schema.json"
JSONLD_SCHEMA="$HUB_DIR/schemas/shared/jsonld-catalog.schema.json"

if [ ! -d "$HUB_DIR/node_modules/ajv" ] || [ ! -d "$HUB_DIR/node_modules/ajv-formats" ]; then
  echo "FAIL registry-hub-repo/node_modules: ajv runtime dependencies not found" >&2
  exit 1
fi

logical_hub_config="registry-hub-repo/hub-config.json"
logical_registry_catalog="registry-hub-repo/registry-catalog.jsonld"
logical_hub_index="registry-hub-repo/hub-index.json"
logical_skill_index="skill-registry/index.jsonld"
logical_cao_index="cao-profile-registry/index.jsonld"
logical_reprogate_index="reprogate-registry/index.jsonld"

hub_config_path="${REGISTRY_HUB_CONFIG_OVERRIDE:-$HUB_DIR/hub-config.json}"
registry_catalog_path="${REGISTRY_CATALOG_OVERRIDE:-$HUB_DIR/registry-catalog.jsonld}"
hub_index_path="${HUB_INDEX_OVERRIDE:-$HUB_DIR/hub-index.json}"
skill_index_path="$WORKSPACE_ROOT/skill-registry/index.jsonld"
cao_index_path="$WORKSPACE_ROOT/cao-profile-registry/index.jsonld"
reprogate_index_path="$WORKSPACE_ROOT/reprogate-registry/index.jsonld"

failures=0
schema_temp_dir="$(mktemp -d)"
common_schema_alias="$schema_temp_dir/common.schema.raw-id.json"
enabled_local_sources="${REGISTRY_USE_LOCAL_SOURCES:-1}"

python3 - <<'PY' "$COMMON_SCHEMA" "$common_schema_alias"
import json, sys
source, target = sys.argv[1], sys.argv[2]
with open(source) as f:
    data = json.load(f)
data["$id"] = "https://raw.githubusercontent.com/skillinterop/registry-hub/main/schemas/shared/common.schema.json"
with open(target, "w") as f:
    json.dump(data, f, indent=2)
PY

report_ok() {
  echo "OK $1"
}

report_fail() {
  echo "FAIL $1: $2" >&2
  failures=1
}

validate_with_ajv() {
  local logical_path="$1"
  local data_path="$2"
  local schema_path="$3"
  shift 3

  if [ ! -f "$data_path" ]; then
    report_fail "$logical_path" "file not found at $data_path"
    return
  fi

  local output
  if output=$(node - "$HUB_DIR" "$data_path" "$schema_path" "$COMMON_SCHEMA" "$common_schema_alias" "$@" <<'NODE' 2>&1
const fs = require('fs');
const path = require('path');
const Ajv = require(path.join(process.argv[2], 'node_modules/ajv'));
const addFormats = require(path.join(process.argv[2], 'node_modules/ajv-formats'));

const [, , hubDir, dataPath, schemaPath, ...refPaths] = process.argv;
const ajv = new Ajv({ strict: false, allErrors: true, validateFormats: true });
addFormats(ajv);

const load = (filePath) => JSON.parse(fs.readFileSync(filePath, 'utf8'));
for (const refPath of refPaths) {
  const schema = load(refPath);
  ajv.addSchema(schema);
}

const schema = load(schemaPath);
const validate = ajv.compile(schema);
const data = load(dataPath);
const ok = validate(data);
if (!ok) {
  const errorText = ajv.errorsText(validate.errors, { separator: '; ' });
  console.error(errorText);
  process.exit(1);
}
console.log('valid');
NODE
  ); then
    report_ok "$logical_path"
  else
    output="$(echo "$output" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g; s/^ //; s/ $//')"
    report_fail "$logical_path" "$output"
  fi
}

validate_with_ajv "$logical_hub_config" "$hub_config_path" "$HUB_DIR/schemas/hub-config.schema.json"
validate_with_ajv "$logical_registry_catalog" "$registry_catalog_path" "$HUB_DIR/schemas/registry-catalog.schema.json" "$JSONLD_SCHEMA"
validate_with_ajv "$logical_hub_index" "$hub_index_path" "$HUB_DIR/schemas/hub-index.schema.json"
validate_with_ajv "$logical_skill_index" "$skill_index_path" "$WORKSPACE_ROOT/skill-registry/schemas/index.schema.json" "$JSONLD_SCHEMA"
validate_with_ajv "$logical_cao_index" "$cao_index_path" "$WORKSPACE_ROOT/cao-profile-registry/schemas/index.schema.json" "$JSONLD_SCHEMA"
validate_with_ajv "$logical_reprogate_index" "$reprogate_index_path" "$WORKSPACE_ROOT/reprogate-registry/schemas/index.schema.json" "$JSONLD_SCHEMA"

mapping_ok=$(jq -n \
  --slurpfile cfg "$hub_config_path" \
  --slurpfile cat "$registry_catalog_path" \
  '($cfg[0].sources | map({
      registryType,
      url: (.repoUrl | sub("^https://github.com/"; "https://raw.githubusercontent.com/")) + "/" + .branch + "/" + .catalogPath
    }) | sort_by(.registryType))
   ==
   ($cat[0].hasPart | map({
      registryType: .["skillinterop:registryType"],
      url
    }) | sort_by(.registryType))')

if [ "$mapping_ok" = "true" ]; then
  report_ok "$logical_registry_catalog"
else
  report_fail "$logical_registry_catalog" "hasPart does not match hub-config.json.sources"
fi

temp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$temp_dir"
  rm -rf "$schema_temp_dir"
}
trap cleanup EXIT

cp -R "$HUB_DIR/." "$temp_dir/"

set +e
generator_output="$(cd "$temp_dir" && REGISTRY_USE_LOCAL_SOURCES="$enabled_local_sources" REGISTRY_WORKSPACE_ROOT="$WORKSPACE_ROOT" bash ./scripts/generate-index.sh 2>&1)"
generator_status=$?
set -e

if [ "$generator_status" -ne 0 ]; then
  generator_output="$(echo "$generator_output" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g; s/^ //; s/ $//')"
  report_fail "registry-hub-repo/scripts/generate-index.sh" "$generator_output"
else
  report_ok "registry-hub-repo/scripts/generate-index.sh"
fi

generated_normalized="$(jq 'del(.generatedAt, .registries[].lastUpdated)' "$temp_dir/hub-index.json" 2>/dev/null || echo "__NORMALIZE_FAILED__")"
committed_normalized="$(jq 'del(.generatedAt, .registries[].lastUpdated)' "$hub_index_path" 2>/dev/null || echo "__NORMALIZE_FAILED__")"

if [ "$generated_normalized" = "__NORMALIZE_FAILED__" ] || [ "$committed_normalized" = "__NORMALIZE_FAILED__" ]; then
  report_fail "$logical_hub_index" "failed to normalize hub-index.json for comparison"
elif [ "$generated_normalized" = "$committed_normalized" ]; then
  report_ok "$logical_hub_index"
else
  report_fail "$logical_hub_index" "regenerated hub-index.json does not match committed artifact after timestamp normalization"
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
