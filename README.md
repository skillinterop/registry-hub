# registry-hub

Top-level hub registry for the interop ecosystem.

## Overview

This repository is an **index/aggregation repository**, not a content repository. It includes leaf registries only by reference and does NOT store actual package content. Wrapper tools should be able to register this one repository and recursively resolve the rest.

## Directory Structure

```
registry-hub/
├── hub-config.json            # Hub configuration with source references
├── hub-index.json             # Generated index (empty until sync)
├── schemas/
│   ├── hub-config.schema.json # JSON Schema for hub-config.json
│   └── hub-index.schema.json  # JSON Schema for hub-index.json
├── sources/                   # Cached manifest snapshots (initially empty)
│   └── .gitkeep
├── docs/
│   └── resolution.md          # Resolution flow documentation
├── README.md
└── .gitignore
```

## Registered Sources

| Registry Type | Repository | Branch | Channel |
|---------------|------------|--------|---------|
| skill | [skillinterop/skill-registry](https://github.com/skillinterop/skill-registry) | main | all |
| cao-profile | [skillinterop/cao-profile-registry](https://github.com/skillinterop/cao-profile-registry) | main | all |
| reprogate | [skillinterop/reprogate-registry](https://github.com/skillinterop/reprogate-registry) | main | all |

## Hub Config Format

The `hub-config.json` file defines which leaf registries to include:

```json
{
  "hubVersion": "0.1.0",
  "sources": [
    {
      "registryType": "skill",
      "repoUrl": "https://github.com/skillinterop/skill-registry",
      "manifestPath": "manifest.json",
      "branch": "main",
      "channel": "stable"
    }
  ]
}
```

## How to Add a Source

1. Ensure the leaf registry has a valid `manifest.json`
2. Add a new entry to the `sources` array in `hub-config.json`
3. Specify `registryType`, `repoUrl`, `manifestPath`, `branch`, and `channel`
4. Open a PR with the changes

## Priority Rules

When multiple sources contain items with the same `canonicalId`:

1. **Declaration order wins** — The source listed first in `hub-config.json` takes priority
2. **Cross-type conflicts are impossible** — `canonicalId` includes `registryType` as a prefix

See [docs/resolution.md](./docs/resolution.md) for detailed resolution flow.

## Key Principles

- **Manifest-only linkage** — The hub references leaf repos by URL, not git submodules
- **No content vendoring** — Actual packages live in leaf registries only
- **Recursive resolution** — Wrapper tools fetch this hub, then resolve each leaf
- **Channel filtering** — Sources can filter by `stable` or `all` channels

## Related Repos

- [`skill-registry`](https://github.com/skillinterop/skill-registry) — Skill leaf registry
- [`cao-profile-registry`](https://github.com/skillinterop/cao-profile-registry) — CAO profile leaf registry
- [`reprogate-registry`](https://github.com/skillinterop/reprogate-registry) — ReproGate leaf registry

## TODO

- [ ] Schema extraction to dedicated repo (deferred — see design decision)
- [x] Implement hub-index generation logic (`scripts/generate-index.sh`)
- [x] Add CI workflow for automatic index regeneration (`.github/workflows/generate-index.yml`)

## License

MIT
