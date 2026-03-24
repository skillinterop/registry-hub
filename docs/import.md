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
npx @skillinterop/registry-hub-import preview skill/org/[MASKED_EMAIL] --runtime codex
```

Expected output:

```
Canonical ID:  skill/org/[MASKED_EMAIL]
Registry Type: skill
Version:       1.0.0
Source Repo:   https://github.com/skillinterop/skill-registry
Artifact Path: ./skills/workmux-router/SKILL.md
Artifact URL:  https://raw.githubusercontent.com/skillinterop/skill-registry/main/skills/workmux-router/SKILL.md
Destination:   /home/user/.codex/skills/workmux-router/SKILL.md
```

### Skill preview — claude-code runtime

```bash
npx @skillinterop/registry-hub-import preview skill/org/[MASKED_EMAIL] --runtime claude-code
```

Destination will be `$HOME/.claude/skills/workmux-router/SKILL.md`.

### CAO profile preview

```bash
npx @skillinterop/registry-hub-import preview cao-profile/org/[MASKED_EMAIL] --project-root "$PWD"
```

Destination will be `<project-root>/.registry/profiles/default-cao/PROFILE.md`.

## Running an import

Use the `import` command to resolve, confirm, and write the artifact to its destination.

### Skill import — codex runtime

```bash
npx @skillinterop/registry-hub-import import skill/org/[MASKED_EMAIL] --runtime codex --yes
```

The `--yes` flag skips the interactive confirmation prompt. Omit it to review the preview and answer `Proceed with import? [y/N]` before anything is written.

### CAO profile import with receipt

```bash
npx @skillinterop/registry-hub-import import cao-profile/org/[MASKED_EMAIL] --project-root "$PWD" --save-receipt --yes
```

`--save-receipt` writes a project-local receipt to `.registry/imports/<registryType>--<name>.json` (see [Receipt persistence](#receipt-persistence)).

## Options

| Option | Description |
|--------|-------------|
| `--catalog <path-or-url>` | Path or URL to `registry-catalog.jsonld`. Defaults to the published hub catalog. |
| `--runtime <codex\|claude-code>` | Target AI runtime for skill destination mapping. |
| `--project-root <path>` | Project root for CAO profile and other project-local destinations. |
| `--target-path <path>` | Explicit destination path. Overrides automatic destination mapping for any item type. |
| `--overwrite` | Replace an existing destination file. Default behavior is to abort. |
| `--yes` | Skip the confirmation prompt and proceed automatically. |
| `--save-receipt` | Write a project-local receipt under `.registry/imports/`. Default: no metadata written. |

## Phase 4 destination policy

### Skills

| Runtime | Destination |
|---------|-------------|
| `codex` | `$HOME/.codex/skills/<name>/SKILL.md` |
| `claude-code` | `$HOME/.claude/skills/<name>/SKILL.md` |
| unknown or missing | Requires `--target-path` |

If `--runtime` is not recognized, the CLI prints `Unknown runtime; provide --target-path or --runtime (codex|claude-code)` and exits non-zero. Pass `--target-path` to place the file explicitly:

```bash
npx @skillinterop/registry-hub-import import skill/org/[MASKED_EMAIL] \
  --target-path ./vendor/skills/workmux-router/SKILL.md \
  --yes
```

### CAO profiles

CAO profiles land in a project-local hidden staging path:

```
<project-root>/.registry/profiles/<name>/PROFILE.md
```

This location is intentionally hidden and project-local so downstream CAO-style install flows can consume it. Provide `--project-root` to control which project directory is used. Defaults to `$PWD`.

### ReproGate

reprogate imports remain deferred in this phase. Attempting to preview or import a `reprogate` item will fail with a clear error message. No sync/update/remove workflow exists yet for any registry type.

## Conflict behavior

If the destination file already exists, the import aborts rather than silently overwriting:

```
Error: Destination already exists: <path>
```

Pass `--overwrite` to replace the existing file. The replacement is atomic: the CLI writes to a temporary file in the same directory and renames it into place, so a partial write never corrupts an existing artifact.

## Receipt persistence

Phase 4 default behavior writes **no project metadata**. Running `import` without `--save-receipt` produces:

```
Receipt: skipped (default)
```

When `--save-receipt` is present, a single JSON receipt is written to:

```
<project-root>/.registry/imports/<registryType>--<name>.json
```

The receipt contains exactly these keys:

| Key | Description |
|-----|-------------|
| `canonicalId` | Canonical registry identifier |
| `registryType` | `skill`, `cao-profile`, etc. |
| `name` | Item name |
| `version` | Item version |
| `sourceRepo` | Source repository URL |
| `sourceCatalog` | Leaf catalog URL |
| `artifactPath` | Relative artifact path within source repo |
| `artifactUrl` | Canonical artifact download URL |
| `destinationPath` | Absolute local path where artifact was written |
| `sha256` | SHA-256 hex digest of the written file |
| `importedAt` | ISO 8601 timestamp of the import |

There is no sync, update, or remove workflow associated with receipts. They exist solely for provenance tracking when a project needs to record what was imported and from where.

## Using a local catalog

For development or offline testing, point `--catalog` at a local copy of `registry-catalog.jsonld`:

```bash
npx @skillinterop/registry-hub-import import skill/org/[MASKED_EMAIL] \
  --catalog ./registry-hub-repo/registry-catalog.jsonld \
  --runtime codex \
  --yes
```

When the catalog file is local, relative `contentUrl` values in `distribution[0]` are resolved relative to that file's directory, so a local `hub-index.json` next to the catalog works without any URL changes.

## Resolution contract

- The catalog's `distribution[0].contentUrl` is the only supported pointer to `hub-index.json`.
- Items are looked up by exact `canonicalId` match.
- If no item matches: `Canonical ID not found: <id>`
- If multiple items match (should not happen in a well-formed index): `Canonical ID is ambiguous: <id>`

See `docs/resolution.md` for the full hub-to-leaf resolution model.
