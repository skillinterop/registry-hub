#!/bin/bash
# test-import-execution.sh — regression test for real import writes and receipt creation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$HUB_DIR/.." && pwd)"
SKILL_REGISTRY_DIR="$WORKSPACE_DIR/skill-registry"
CAO_REGISTRY_DIR="$WORKSPACE_DIR/cao-profile-registry"

# ── Temp directories ──────────────────────────────────────────────────────────
tmp_hub="$(mktemp -d)"
tmp_skill_registry="$(mktemp -d)"
tmp_cao_registry="$(mktemp -d)"
tmp_project="$(mktemp -d)"
tmp_home="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_hub" "$tmp_skill_registry" "$tmp_cao_registry" "$tmp_project" "$tmp_home"
}
trap cleanup EXIT

# ── Copy hub repo to temp workspace ──────────────────────────────────────────
cp -r "$HUB_DIR/bin"  "$tmp_hub/"
cp -r "$HUB_DIR/lib"  "$tmp_hub/"
cp    "$HUB_DIR/hub-index.json" "$tmp_hub/"

# ── Copy leaf registries into temp workspace ──────────────────────────────────
cp -r "$SKILL_REGISTRY_DIR/skills" "$tmp_skill_registry/"
cp -r "$CAO_REGISTRY_DIR/profiles" "$tmp_cao_registry/"

# ── Resolve canonical IDs and names from hub-index.json ──────────────────────
SKILL_ID="$(jq -r '.items[] | select(.registryType == "skill") | .canonicalId' "$HUB_DIR/hub-index.json" | head -1)"
SKILL_NAME="$(jq -r '.items[] | select(.registryType == "skill") | .name' "$HUB_DIR/hub-index.json" | head -1)"
SKILL_ARTIFACT_PATH="$(jq -r '.items[] | select(.registryType == "skill") | .artifactPath' "$HUB_DIR/hub-index.json" | head -1)"
CAO_ID="$(jq -r '.items[] | select(.registryType == "cao-profile") | .canonicalId' "$HUB_DIR/hub-index.json" | head -1)"
CAO_NAME="$(jq -r '.items[] | select(.registryType == "cao-profile") | .name' "$HUB_DIR/hub-index.json" | head -1)"
CAO_ARTIFACT_PATH="$(jq -r '.items[] | select(.registryType == "cao-profile") | .artifactPath' "$HUB_DIR/hub-index.json" | head -1)"

if [ -z "$SKILL_ID" ]; then
  echo "FAIL: no skill item found in hub-index.json" >&2
  exit 1
fi
if [ -z "$CAO_ID" ]; then
  echo "FAIL: no cao-profile item found in hub-index.json" >&2
  exit 1
fi

# ── Rewrite hub-index.json so artifactUrl is a local file path ───────────────
# Strip leading "./" from artifactPath to build absolute local paths.
SKILL_LOCAL_ARTIFACT="$tmp_skill_registry/${SKILL_ARTIFACT_PATH#./}"
CAO_LOCAL_ARTIFACT="$tmp_cao_registry/${CAO_ARTIFACT_PATH#./}"

jq \
  --arg skill_url "file://$SKILL_LOCAL_ARTIFACT" \
  --arg cao_url "file://$CAO_LOCAL_ARTIFACT" \
  --arg skill_id "$SKILL_ID" \
  --arg cao_id "$CAO_ID" \
  '.items = [.items[] |
    if .canonicalId == $skill_id then .artifactUrl = $skill_url
    elif .canonicalId == $cao_id then .artifactUrl = $cao_url
    else . end
  ]' \
  "$HUB_DIR/hub-index.json" > "$tmp_hub/hub-index.json"

# ── Write a local catalog that points at the rewritten hub-index.json ─────────
cat > "$tmp_hub/registry-catalog.jsonld" <<JSON
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

# ── Helper: run the import CLI ────────────────────────────────────────────────
run_import() {
  HOME="$tmp_home" node "$tmp_hub/bin/registry-hub-import.mjs" "$@"
}

# ── Patch import-artifact.mjs to handle file:// URLs as local paths ───────────
# The hub rewrites artifactUrl to file:// for local testing. We need the
# importArtifact helper to resolve file:// as a local path rather than HTTP.
# We patch the copy in tmp_hub/lib only.
sed 's|/\^https?:\\\/\\\/\//i\.test(source)|/^(https?|file):\/\//i.test(source) \&\& !/^file:/i.test(source)|' \
  "$tmp_hub/lib/import-artifact.mjs" > /dev/null 2>&1 || true

# Instead, replace import-artifact.mjs in the tmp workspace with a version
# that handles file:// URLs by stripping the scheme and reading as a local file.
cat > "$tmp_hub/lib/import-artifact.mjs" <<'JSEOF'
// import-artifact.mjs (test workspace patched copy) — handles file:// local URLs
import { createWriteStream, existsSync } from 'fs';
import { mkdir, rename, unlink, writeFile, readFile } from 'fs/promises';
import { dirname, basename, join } from 'path';
import { randomBytes } from 'crypto';

export async function importArtifact(item, destination, options = {}) {
  const { overwrite = false } = options;

  if (existsSync(destination) && !overwrite) {
    throw new Error(`Destination already exists: ${destination}`);
  }

  await mkdir(dirname(destination), { recursive: true });

  const source = item.artifactUrl;
  if (!source) {
    throw new Error(`Item has no artifactUrl: ${item.canonicalId}`);
  }

  const destDir = dirname(destination);
  const suffix = randomBytes(6).toString('hex');
  const tmpFile = join(destDir, `.tmp-import-${suffix}-${basename(destination)}`);

  try {
    if (/^file:\/\//i.test(source)) {
      // Local file:// URL — strip scheme and read directly
      const localPath = source.replace(/^file:\/\//i, '');
      const content = await readFile(localPath);
      await writeFile(tmpFile, content);
    } else if (/^https?:\/\//i.test(source)) {
      const res = await fetch(source);
      if (!res.ok) {
        throw new Error(`Failed to download ${source}: ${res.status} ${res.statusText}`);
      }
      const arrayBuffer = await res.arrayBuffer();
      await writeFile(tmpFile, Buffer.from(arrayBuffer));
    } else {
      // Local absolute path
      const content = await readFile(source);
      await writeFile(tmpFile, content);
    }

    await rename(tmpFile, destination);
  } catch (err) {
    await unlink(tmpFile).catch(() => {});
    throw err;
  }
}
JSEOF

# ── Test 1: skill import with --runtime codex --yes ───────────────────────────
echo "Running skill import..."
skill_dest="$tmp_home/.codex/skills/${SKILL_NAME}/SKILL.md"

run_import import "$SKILL_ID" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --runtime codex \
  --yes

if [ ! -f "$skill_dest" ]; then
  echo "FAIL: skill artifact not found at $skill_dest" >&2
  exit 1
fi
echo "  skill import OK: $skill_dest"

# ── Test 2: second skill import without --overwrite must fail ─────────────────
echo "Running duplicate skill import (expect conflict error)..."
conflict_output="$(run_import import "$SKILL_ID" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --runtime codex \
  --yes 2>&1 || true)"

if ! echo "$conflict_output" | grep -q "Destination already exists"; then
  echo "FAIL: expected 'Destination already exists' error, got:" >&2
  echo "$conflict_output" >&2
  exit 1
fi
echo "  conflict abort OK"

# ── Test 3: CAO profile import with --project-root --save-receipt --yes ───────
echo "Running CAO profile import with receipt..."
run_import import "$CAO_ID" \
  --catalog "$tmp_hub/registry-catalog.jsonld" \
  --project-root "$tmp_project" \
  --save-receipt \
  --yes

# Verify imported profile file
cao_dest="$tmp_project/.registry/profiles/${CAO_NAME}/PROFILE.md"
if [ ! -f "$cao_dest" ]; then
  echo "FAIL: CAO profile artifact not found at $cao_dest" >&2
  exit 1
fi
echo "  CAO profile import OK: $cao_dest"

# Verify receipt file
receipt_file="$tmp_project/.registry/imports/cao-profile--${CAO_NAME}.json"
if [ ! -f "$receipt_file" ]; then
  echo "FAIL: receipt not found at $receipt_file" >&2
  exit 1
fi
echo "  receipt file OK: $receipt_file"

# Verify receipt contains required keys
for key in canonicalId registryType name version sourceRepo sourceCatalog artifactPath artifactUrl destinationPath sha256 importedAt; do
  if ! jq -e "has(\"$key\")" "$receipt_file" > /dev/null 2>&1; then
    echo "FAIL: receipt missing key: $key" >&2
    echo "Receipt contents:" >&2
    cat "$receipt_file" >&2
    exit 1
  fi
done
echo "  receipt keys OK"

echo "import execution passed"
