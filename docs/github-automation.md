# GitHub Automation Rollout

This guide covers the GitHub Actions workflow topology, required checks, secret configuration, and the staged rollout process for enforcing merge gates across all four repos.

## 1. Workflow Inventory

| Repository | Workflow File | Purpose |
|------------|--------------|---------|
| `registry-hub` | `.github/workflows/pr-validate.yml` | Hub PR gate — validates contracts on PR |
| `registry-hub` | `.github/workflows/generate-index.yml` | Post-merge hub-index.json regeneration |
| `skill-registry` | `.github/workflows/pr-validate.yml` | Leaf PR gate — local + hub-cross validation |
| `skill-registry` | `.github/workflows/dispatch-hub-regen.yml` | Post-merge hub dispatch |
| `cao-profile-registry` | `.github/workflows/pr-validate.yml` | Leaf PR gate — local + hub-cross validation |
| `cao-profile-registry` | `.github/workflows/dispatch-hub-regen.yml` | Post-merge hub dispatch |
| `reprogate-registry` | `.github/workflows/pr-validate.yml` | Leaf PR gate — local + hub-cross validation |
| `reprogate-registry` | `.github/workflows/dispatch-hub-regen.yml` | Post-merge hub dispatch |

## 2. Required Check Names

These are the exact status check contexts configured as required on `main`:

| Repository | Required Context |
|------------|-----------------|
| `registry-hub` | `Hub PR Validate / validate` |
| `skill-registry` | `Leaf PR Validate / leaf-local` |
| `skill-registry` | `Leaf PR Validate / hub-cross-check` |
| `cao-profile-registry` | `Leaf PR Validate / leaf-local` |
| `cao-profile-registry` | `Leaf PR Validate / hub-cross-check` |
| `reprogate-registry` | `Leaf PR Validate / leaf-local` |
| `reprogate-registry` | `Leaf PR Validate / hub-cross-check` |

## 3. Leaf Dispatch Secret: HUB_DISPATCH_TOKEN

Each leaf repo's `dispatch-hub-regen.yml` workflow requires a `HUB_DISPATCH_TOKEN` secret that can call the `repository_dispatch` endpoint on `skillinterop/registry-hub`.

**Where to store:** Each leaf repository → Settings → Secrets and variables → Actions → `HUB_DISPATCH_TOKEN`

**Token requirements:** Fine-grained GitHub PAT or GitHub App token with `repository_dispatch` write permission on `skillinterop/registry-hub`.

**Repos that need this secret:**
- `skill-registry`
- `cao-profile-registry`
- `reprogate-registry`

## 4. Dedicated Hub Bot Setup

The `Regenerate Hub Index` workflow pushes `hub-index.json` directly to protected `main` in `registry-hub`. This requires a dedicated bot actor with bypass permission on protected `main`.

### Required secrets in `registry-hub`

| Secret | Purpose |
|--------|---------|
| `HUB_REGEN_BOT_TOKEN` | Bot credential for direct push to protected `main` |
| `HUB_REGEN_BOT_NAME` | Bot actor display name for commit authorship |
| `HUB_REGEN_BOT_EMAIL` | Bot actor email for commit authorship |

**Where to store:** `registry-hub` → Settings → Secrets and variables → Actions

### Bypass permission

The dedicated bot actor (the GitHub user or app behind `HUB_REGEN_BOT_TOKEN`) **must have bypass permission on protected `main`** in `skillinterop/registry-hub`. Without this, the regeneration workflow will fail with a push rejection.

Configure bypass via:
- **Branch protection rules:** Settings → Branches → `main` rule → Allow specified actors to bypass → add the bot
- **Repository rulesets:** Settings → Rules → Rulesets → add bypass actor for the `main` ruleset

## 5. Rollout Order

Follow this exact sequence:

1. **Merge workflow changes** from Plans 05-02 and 05-03 to the default branches of all affected repos.

2. **Let check contexts appear once.** Open sample PRs or otherwise trigger each workflow so GitHub registers the check context names:
   - `Hub PR Validate / validate` in `registry-hub`
   - `Leaf PR Validate / leaf-local` in each leaf repo
   - `Leaf PR Validate / hub-cross-check` in each leaf repo

3. **Configure `HUB_DISPATCH_TOKEN`** in the three leaf repos (see section 3).

4. **Configure the dedicated hub bot** (see section 4):
   - Store `HUB_REGEN_BOT_TOKEN`, `HUB_REGEN_BOT_NAME`, and `HUB_REGEN_BOT_EMAIL` in `registry-hub`
   - Grant the bot actor bypass permission on protected `main`

5. **Run the rollout script:**
   ```bash
   bash scripts/configure-github-merge-gates.sh --owner skillinterop
   ```

6. **Verify live branch protection** (see Live enforcement audit below).

7. **Verify the bot direct-push path:** Merge a harmless leaf metadata change and confirm `Regenerate Hub Index` runs in `registry-hub` and pushes a direct commit to protected `main` authored by the dedicated bot actor with only `hub-index.json` changed. If the push is rejected, check the bot's bypass permission.

## 6. Live Enforcement Audit

### Check branch protection

```bash
gh api repos/skillinterop/registry-hub/branches/main/protection
gh api repos/skillinterop/skill-registry/branches/main/protection
gh api repos/skillinterop/cao-profile-registry/branches/main/protection
gh api repos/skillinterop/reprogate-registry/branches/main/protection
```

Verify each response includes `required_status_checks.checks` with the correct context names from section 2.

### Verify hub regeneration direct-push

```bash
# Trigger a manual regeneration
gh workflow run generate-index.yml --repo skillinterop/registry-hub

# Wait for the run to complete, then inspect
gh run list --repo skillinterop/registry-hub --workflow generate-index.yml --limit 1
# Use the run ID from above:
gh run view <run-id> --repo skillinterop/registry-hub --log
```

Confirm the commit is authored by the dedicated bot actor and pushed directly to `main` (not via PR). If the run fails with a push rejection, the bot actor lacks bypass permission on protected `main`.

### Failure triage

- **Validation failures** (OK/FAIL format): See [docs/validation.md](validation.md) for contract interpretation and troubleshooting.
- **Auth failures on direct push:** The bot actor does not have bypass permission on protected `main`. Add the bot to the branch protection bypass list or ruleset bypass actors.
- **Missing check contexts:** The required workflows have not run yet. Open a sample PR to trigger them before re-running the rollout script.
- **Dispatch failures:** The `HUB_DISPATCH_TOKEN` secret is missing or lacks `repository_dispatch` permission on `skillinterop/registry-hub`.
