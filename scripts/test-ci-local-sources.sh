#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$HUB_DIR")"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

copy_repo() {
  local source_dir="$1"
  local target_dir="$2"
  cp -R "$source_dir" "$target_dir"
  find "$target_dir" -name node_modules -type d -prune -exec rm -rf {} +
}

copy_repo "$HUB_DIR" "$TEMP_DIR/registry-hub-repo"
copy_repo "$WORKSPACE_ROOT/skill-registry" "$TEMP_DIR/skill-registry"
copy_repo "$WORKSPACE_ROOT/cao-profile-registry" "$TEMP_DIR/cao-profile-registry"
copy_repo "$WORKSPACE_ROOT/reprogate-registry" "$TEMP_DIR/reprogate-registry"
cp -R "$HUB_DIR/node_modules" "$TEMP_DIR/registry-hub-repo/node_modules"

python3 - <<'PY' "$TEMP_DIR/skill-registry/index.jsonld"
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["dataset"][0]["version"] = "9.9.9-ci-local"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

(
  cd "$TEMP_DIR/registry-hub-repo"
  REGISTRY_USE_LOCAL_SOURCES=1 REGISTRY_WORKSPACE_ROOT="$TEMP_DIR" bash ./scripts/generate-index.sh >/tmp/phase5-generate-local.out 2>/tmp/phase5-generate-local.err
)

jq -e '.items[] | select(.registryType == "skill" and .version == "9.9.9-ci-local")' "$TEMP_DIR/registry-hub-repo/hub-index.json" >/dev/null
jq -e '.items[] | select(.registryType == "skill") | .sourceCatalog == "https://raw.githubusercontent.com/skillinterop/skill-registry/main/index.jsonld"' "$TEMP_DIR/registry-hub-repo/hub-index.json" >/dev/null
jq -e '.items[] | select(.registryType == "skill") | .artifactUrl == "https://raw.githubusercontent.com/skillinterop/skill-registry/main/skills/workmux-router/SKILL.md"' "$TEMP_DIR/registry-hub-repo/hub-index.json" >/dev/null

printf '{invalid json\n' > "$TEMP_DIR/skill-registry/index.jsonld"
set +e
invalid_output="$(cd "$TEMP_DIR/registry-hub-repo" && REGISTRY_USE_LOCAL_SOURCES=1 REGISTRY_WORKSPACE_ROOT="$TEMP_DIR" bash ./scripts/generate-index.sh 2>&1)"
invalid_status=$?
set -e
if [ "$invalid_status" -eq 0 ]; then
  echo "expected invalid local catalog to fail" >&2
  exit 1
fi
echo "$invalid_output" | rg 'ERROR: Invalid JSON in local catalog for skill' >/dev/null

bash "$HUB_DIR/scripts/validate-leaf-local.sh" \
  --repo-root "$WORKSPACE_ROOT/skill-registry" \
  --logical-root skill-registry \
  --schema-file "$WORKSPACE_ROOT/skill-registry/schemas/index.schema.json" \
  --artifact-dir skills \
  --artifact-file SKILL.md >/tmp/phase5-leaf-local-valid.out
rg '^OK skill-registry/index\.jsonld$' /tmp/phase5-leaf-local-valid.out >/dev/null

copy_repo "$WORKSPACE_ROOT/skill-registry" "$TEMP_DIR/skill-registry-bad"
python3 - <<'PY' "$TEMP_DIR/skill-registry-bad/index.jsonld"
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["dataset"][0]["url"] = "./skills/workmux-router/MISSING.md"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

set +e
leaf_output="$(bash "$HUB_DIR/scripts/validate-leaf-local.sh" \
  --repo-root "$TEMP_DIR/skill-registry-bad" \
  --logical-root skill-registry \
  --schema-file "$TEMP_DIR/skill-registry-bad/schemas/index.schema.json" \
  --artifact-dir skills \
  --artifact-file SKILL.md 2>&1)"
leaf_status=$?
set -e
if [ "$leaf_status" -eq 0 ]; then
  echo "expected missing artifact validation to fail" >&2
  exit 1
fi
echo "$leaf_output" | rg '^FAIL skill-registry/index\.jsonld:' >/dev/null

echo "ci local source checks passed"
