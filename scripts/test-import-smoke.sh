#!/bin/bash
# test-import-smoke.sh — end-to-end regression for preview/import and default no-persistence
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$HUB_DIR/.." && pwd)"
SKILL_REGISTRY_DIR="$WORKSPACE_DIR/skill-registry"
CAO_REGISTRY_DIR="$WORKSPACE_DIR/cao-profile-registry"

tmp_hub="$(mktemp -d)"
tmp_skill_registry="$(mktemp -d)"
tmp_cao_registry="$(mktemp -d)"
tmp_project="$(mktemp -d)"
tmp_home="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_hub" "$tmp_skill_registry" "$tmp_cao_registry" "$tmp_project" "$tmp_home"
}
trap cleanup EXIT

cp -R "$HUB_DIR/bin" "$tmp_hub/"
cp -R "$HUB_DIR/lib" "$tmp_hub/"
cp "$HUB_DIR/hub-index.json" "$tmp_hub/hub-index.json"
cp -R "$SKILL_REGISTRY_DIR/skills" "$tmp_skill_registry/"
cp -R "$CAO_REGISTRY_DIR/profiles" "$tmp_cao_registry/"

skill_id="skill/org/workmux-router@1.0.0"
skill_dest="$tmp_home/.codex/skills/workmux-router/SKILL.md"
skill_artifact="$tmp_skill_registry/skills/workmux-router/SKILL.md"
cao_artifact="$tmp_cao_registry/profiles/default-cao/PROFILE.md"

if [ ! -f "$skill_artifact" ]; then
  echo "FAIL: missing copied skill artifact at $skill_artifact" >&2
  exit 1
fi

if [ ! -f "$cao_artifact" ]; then
  echo "FAIL: missing copied CAO profile artifact at $cao_artifact" >&2
  exit 1
fi

jq \
  --arg skill_id "$skill_id" \
  --arg skill_artifact "$skill_artifact" \
  --arg cao_id "cao-profile/org/default-cao@0.1.0" \
  --arg cao_artifact "$cao_artifact" \
  '.items = [.items[] |
    if .canonicalId == $skill_id then .artifactUrl = $skill_artifact
    elif .canonicalId == $cao_id then .artifactUrl = $cao_artifact
    else . end
  ]' \
  "$HUB_DIR/hub-index.json" > "$tmp_hub/hub-index.json"

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

run_import() {
  HOME="$tmp_home" node "$tmp_hub/bin/registry-hub-import.mjs" "$@"
}

preview_output="$(run_import preview "$skill_id" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --runtime codex \
  --project-root "$tmp_project")"

if ! echo "$preview_output" | grep -Fq "Destination:   $skill_dest"; then
  echo "FAIL: preview output did not include expected destination" >&2
  echo "$preview_output" >&2
  exit 1
fi

if [ -e "$skill_dest" ]; then
  echo "FAIL: preview created artifact before import at $skill_dest" >&2
  exit 1
fi

import_output="$(run_import import "$skill_id" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --runtime codex \
  --project-root "$tmp_project" \
  --yes)"

if [ ! -f "$skill_dest" ]; then
  echo "FAIL: import did not create $skill_dest" >&2
  echo "$import_output" >&2
  exit 1
fi

if ! echo "$import_output" | grep -Fq "Receipt: skipped (default)"; then
  echo "FAIL: import did not report default receipt skip" >&2
  echo "$import_output" >&2
  exit 1
fi

for forbidden in \
  "$tmp_project/registry-lock.json" \
  "$tmp_project/.registry/imports.json" \
  "$tmp_project/.registry/lockfile.json" \
  "$tmp_project/.registry/imports"
do
  if [ -e "$forbidden" ]; then
    echo "FAIL: default import created forbidden persistence path: $forbidden" >&2
    exit 1
  fi
done

echo "import smoke passed"
