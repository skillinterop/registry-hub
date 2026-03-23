# Registry Resolution

This document explains how the registry-hub resolves and aggregates leaf registries.

## Hub to Leaf Resolution Flow

```
                    ┌─────────────────┐
                    │  registry-hub   │
                    │ hub-config.json │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ skill-registry  │ │ cao-profile-reg │ │reprogate-registry│
│  manifest.json  │ │  manifest.json  │ │  manifest.json  │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

1. **Read hub-config.json** — The wrapper reads the hub's configuration file
2. **Iterate sources** — For each source in the `sources` array:
   - Fetch the leaf registry's `manifest.json` from the specified `repoUrl`, `branch`, and `manifestPath`
   - Filter items by `channel` (stable-only or all)
3. **Aggregate items** — Combine all items into the unified `hub-index.json`
4. **Handle conflicts** — If two sources have items with the same `canonicalId`, the source declared earlier in `hub-config.json` takes priority

## Include Entries Reference Repos and Refs Only

The hub's `hub-config.json` only stores **references** to leaf registries:

```json
{
  "registryType": "skill",
  "repoUrl": "https://github.com/skillinterop/skill-registry",
  "manifestPath": "manifest.json",
  "branch": "main",
  "channel": "stable"
}
```

It does NOT copy or vendor the actual package content. The hub is an **index/aggregation repository**, not a content repository.

## Why Submodules Were Not Chosen

| Approach | Pros | Cons |
|----------|------|------|
| **Manifest-only (chosen)** | Simple, no git complexity, easy CI/CD, clear separation | Requires fetch at resolution time |
| **Git submodules** | Content available locally | Complex updates, nested git state, difficult CI |
| **Git subtree** | Flat history, content inline | Bloated repo, sync complexity, merge conflicts |

The manifest-only approach keeps each repository independent and simple. Wrapper tools fetch leaf manifests on-demand during sync operations.

## Vendoring Leaf Content is Forbidden

The hub MUST NOT:
- Copy `skills/`, `profiles/`, or `gates/` directories from leaf registries
- Store actual package content in the hub repository
- Inline leaf manifest items directly into hub files

The hub SHOULD:
- Only reference leaf registries by URL
- Generate `hub-index.json` dynamically from fetched manifests
- Store cached manifest snapshots in `sources/` (regenerated on each sync)

## Priority and Conflict Handling

When multiple leaf registries are included, conflicts are resolved by **source declaration order**:

1. Sources are processed in the order they appear in `hub-config.json`
2. If an item with the same `canonicalId` appears in multiple sources, the first source wins
3. Since `canonicalId` includes `registryType` as a prefix, cross-type conflicts are impossible

Example priority:
```json
"sources": [
  { "registryType": "skill", ... },      // Priority 1
  { "registryType": "cao-profile", ... }, // Priority 2
  { "registryType": "reprogate", ... }    // Priority 3
]
```

## Channel Filtering

Each source can specify which channel to include:

| Channel | Behavior |
|---------|----------|
| `"stable"` | Only include items where `item.channel === "stable"` |
| `"all"` | Include all items regardless of channel |

Default is `"stable"` for production use.
