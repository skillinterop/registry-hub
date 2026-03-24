# Importing Registry Items

This guide covers the consumer-facing import workflow for Phase 4. Projects can import a registry item directly from hub metadata without cloning any registry repository.

## How it works

Import resolution always starts at `registry-catalog.jsonld`, the public hub entry point. From there the CLI reads `hub-index.json` (the aggregated item index) and looks up the item by its canonical identifier. No registry repository clone is required.

```
registry-catalog.jsonld
        │
        └─► distribution[0].contentUrl ─► hub-index.json
                                                  │
                                                  └─► item by canonicalId
```

## Preview before importing

Every import flow starts with a preview. The preview shows exactly what will be imported and where it will land before any file is written.

### Skill preview — codex runtime

```bash
npx @skillinterop/registry-hub-import preview skill/org/workmux-router@1.0.0 --runtime codex
```

Expected output:

```
Canonical ID:  skill/org/workmux-router@1.0.0
Registry Type: skill
Version:       1.0.0
Source Repo:   https://github.com/skillinterop/skill-registry
Artifact Path: ./skills/workmux-router/SKILL.md
Artifact URL:  https://raw.githubusercontent.com/skillinterop/skill-registry/main/skills/workmux-router/SKILL.md
Destination:   /home/user/.codex/skills/workmux-router/SKILL.md
```

### Skill preview — claude-code runtime

```bash
npx @skillinterop/registry-hub-import preview skill/org/workmux-router@1.0.0 --runtime claude-code
```

Destination will be `$HOME/.claude/skills/workmux-router/SKILL.md`.

### CAO profile preview

```bash
npx @skillinterop/registry-hub-import preview cao-profile/org/default-cao@0.1.0 --project-root "$PWD"
```

Destination will be `<project-root>/.registry/profiles/default-cao/PROFILE.md`.

## Options

| Option | Description |
|--------|-------------|
| `--catalog <path-or-url>` | Path or URL to `registry-catalog.jsonld`. Defaults to the published hub catalog. |
| `--runtime <codex\|claude-code>` | Target AI runtime for skill destination mapping. |
| `--project-root <path>` | Project root for CAO profile and other project-local destinations. |
| `--target-path <path>` | Explicit destination path. Overrides automatic destination mapping for any item type. |

## Phase 4 destination policy

### Skills

| Runtime | Destination |
|---------|-------------|
| `codex` | `$HOME/.codex/skills/<name>/SKILL.md` |
| `claude-code` | `$HOME/.claude/skills/<name>/SKILL.md` |
| unknown or missing | Requires `--target-path` |

If `--runtime` is not recognized, the CLI prints `Unknown runtime; provide --target-path or --runtime (codex|claude-code)` and exits non-zero. Pass `--target-path` to place the file explicitly:

```bash
npx @skillinterop/registry-hub-import preview skill/org/workmux-router@1.0.0 \
  --target-path ./vendor/skills/workmux-router/SKILL.md
```

### CAO profiles

CAO profiles land in a project-local hidden staging path:

```
<project-root>/.registry/profiles/<name>/PROFILE.md
```

This location is intentionally hidden and project-local so downstream CAO-style install flows can consume it. Provide `--project-root` to control which project directory is used. Defaults to `$PWD`.

### ReproGate

reprogate consumer imports are deferred for Phase 4. Attempting to preview or import a `reprogate` item will fail with a clear error message.

## Using a local catalog

For development or offline testing, point `--catalog` at a local copy of `registry-catalog.jsonld`:

```bash
npx @skillinterop/registry-hub-import preview skill/org/workmux-router@1.0.0 \
  --catalog ./registry-hub-repo/registry-catalog.jsonld \
  --runtime codex
```

When the catalog file is local, relative `contentUrl` values in `distribution[0]` are resolved relative to that file's directory, so a local `hub-index.json` next to the catalog works without any URL changes.

## Conflict behavior

If the destination file already exists, the import aborts rather than silently overwriting. Pass `--target-path` pointing to a different location, or remove the existing file, before re-running.

## Resolution contract

- The catalog's `distribution[0].contentUrl` is the only supported pointer to `hub-index.json`.
- Items are looked up by exact `canonicalId` match.
- If no item matches: `Canonical ID not found: <id>`
- If multiple items match (should not happen in a well-formed index): `Canonical ID is ambiguous: <id>`

See `docs/resolution.md` for the full hub-to-leaf resolution model.
