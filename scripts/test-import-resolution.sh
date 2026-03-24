#!/bin/bash
# test-import-resolution.sh — regression test for local catalog/index resolution and preview output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Temp directories ─────────────────────────────────────────────────────────
tmp_hub="$(mktemp -d)"
tmp_project="$(mktemp -d)"
cleanup() { rm -rf "$tmp_hub" "$tmp_project"; }
trap cleanup EXIT

# ── Copy hub repo to temp (preserve structure) ────────────────────────────────
cp -r "$HUB_DIR/bin"            "$tmp_hub/"
cp -r "$HUB_DIR/lib"            "$tmp_hub/"
cp    "$HUB_DIR/hub-index.json" "$tmp_hub/"

# ── Rewrite registry-catalog.jsonld so distribution[0].contentUrl is local ───
cat > "$tmp_hub/registry-catalog.jsonld" <<'JSON'
{
  "@context": {
    "@vocab": "http://schema.org/",
    "skillinterop": "https://skillinterop.org/ns#"
  },
  "@type": "DataCatalog",
  "name": "SkillInterop Registry Hub",
  "description": "Central entrypoint for SkillInterop registries",
  "distribution": [
    {
      "@type": "DataDownload",
      "name": "SkillInterop Hub Index",
      "contentUrl": "./hub-index.json",
      "encodingFormat": "application/json"
    }
  ],
  "hasPart": []
}
JSON

# ── Resolve canonical IDs dynamically from hub-index.json ────────────────────
SKILL_ID="$(jq -r '.items[] | select(.registryType == "skill") | .canonicalId' "$HUB_DIR/hub-index.json" | head -1)"
SKILL_NAME="$(jq -r '.items[] | select(.registryType == "skill") | .name' "$HUB_DIR/hub-index.json" | head -1)"
CAO_ID="$(jq -r '.items[] | select(.registryType == "cao-profile") | .canonicalId' "$HUB_DIR/hub-index.json" | head -1)"
CAO_NAME="$(jq -r '.items[] | select(.registryType == "cao-profile") | .name' "$HUB_DIR/hub-index.json" | head -1)"

if [ -z "$SKILL_ID" ]; then
  echo "FAIL: no skill item found in hub-index.json" >&2
  exit 1
fi
if [ -z "$CAO_ID" ]; then
  echo "FAIL: no cao-profile item found in hub-index.json" >&2
  exit 1
fi

# ── Helper: run preview and capture output ────────────────────────────────────
run_preview() {
  node "$tmp_hub/bin/registry-hub-import.mjs" "$@"
}

# ── Test 1: skill item with --runtime codex ───────────────────────────────────
echo "Running skill preview..."
skill_output="$(run_preview preview "$SKILL_ID" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --runtime codex \
  --project-root "$tmp_project")"

# Verify required fields are present
for field in "Canonical ID:" "Registry Type:" "Version:" "Source Repo:" "Artifact Path:" "Artifact URL:" "Destination:"; do
  if ! echo "$skill_output" | grep -q "$field"; then
    echo "FAIL: skill preview missing field: $field" >&2
    echo "Output was:" >&2
    echo "$skill_output" >&2
    exit 1
  fi
done

# Verify destination ends with /.codex/skills/<name>/SKILL.md
skill_dest="$(echo "$skill_output" | grep '^Destination:' | sed 's/^Destination:[[:space:]]*//')"
expected_skill_suffix="/.codex/skills/${SKILL_NAME}/SKILL.md"
if [[ "$skill_dest" != *"$expected_skill_suffix" ]]; then
  echo "FAIL: skill destination does not end with $expected_skill_suffix" >&2
  echo "Got: $skill_dest" >&2
  exit 1
fi

# ── Test 2: cao-profile item ──────────────────────────────────────────────────
echo "Running cao-profile preview..."
cao_output="$(run_preview preview "$CAO_ID" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --project-root "$tmp_project")"

# Verify required fields are present
for field in "Canonical ID:" "Registry Type:" "Version:" "Source Repo:" "Artifact Path:" "Artifact URL:" "Destination:"; do
  if ! echo "$cao_output" | grep -q "$field"; then
    echo "FAIL: cao-profile preview missing field: $field" >&2
    echo "Output was:" >&2
    echo "$cao_output" >&2
    exit 1
  fi
done

# Verify destination ends with /.registry/profiles/<name>/PROFILE.md
cao_dest="$(echo "$cao_output" | grep '^Destination:' | sed 's/^Destination:[[:space:]]*//')"
expected_cao_suffix="/.registry/profiles/${CAO_NAME}/PROFILE.md"
if [[ "$cao_dest" != *"$expected_cao_suffix" ]]; then
  echo "FAIL: cao-profile destination does not end with $expected_cao_suffix" >&2
  echo "Got: $cao_dest" >&2
  exit 1
fi

echo "preview resolution passed"
