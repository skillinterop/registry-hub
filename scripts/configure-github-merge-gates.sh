#!/bin/bash
set -euo pipefail

OWNER="skillinterop"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    *) echo "Usage: bash scripts/configure-github-merge-gates.sh [--owner <owner>]" >&2; exit 1 ;;
  esac
done

HUB_REPO="registry-hub"
LEAF_REPOS=("skill-registry" "cao-profile-registry" "reprogate-registry")
ALL_REPOS=("$HUB_REPO" "${LEAF_REPOS[@]}")

echo "=== Merge-gate rollout for $OWNER ==="
echo ""

# Preflight: gh auth
if ! gh auth status >/dev/null 2>&1; then
  echo "FAIL: gh auth status failed — authenticate with \`gh auth login\` first" >&2
  exit 1
fi
echo "OK gh auth status"

# Preflight: workflow files exist on default branch
echo ""
echo "--- Checking workflow files on default branches ---"

check_file_on_branch() {
  local repo="$1" path="$2"
  if gh api "repos/$OWNER/$repo/contents/$path" --jq '.name' >/dev/null 2>&1; then
    echo "OK $repo/$path"
  else
    echo "FAIL $repo/$path: not found on default branch — merge workflow PRs first" >&2
    exit 1
  fi
}

check_file_on_branch "$HUB_REPO" ".github/workflows/pr-validate.yml"
check_file_on_branch "$HUB_REPO" ".github/workflows/generate-index.yml"
for leaf in "${LEAF_REPOS[@]}"; do
  check_file_on_branch "$leaf" ".github/workflows/pr-validate.yml"
  check_file_on_branch "$leaf" ".github/workflows/dispatch-hub-regen.yml"
done

# Preflight: check that required contexts have appeared at least once
echo ""
echo "--- Checking live check contexts ---"

MISSING_CONTEXTS=0

check_context() {
  local repo="$1" workflow_name="$2" expected_job="$3"
  local context="$workflow_name / $expected_job"

  local run_id
  run_id=$(gh run list --repo "$OWNER/$repo" --workflow "$workflow_name" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")

  if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
    echo "WAITING_FOR_CHECK_CONTEXT $repo \"$context\""
    MISSING_CONTEXTS=1
    return
  fi

  local job_found
  job_found=$(gh run view "$run_id" --repo "$OWNER/$repo" --json jobs --jq "[.jobs[].name] | index(\"$expected_job\") != null" 2>/dev/null || echo "false")

  if [ "$job_found" = "true" ]; then
    echo "OK $repo: \"$context\""
  else
    echo "WAITING_FOR_CHECK_CONTEXT $repo \"$context\""
    MISSING_CONTEXTS=1
  fi
}

check_context "$HUB_REPO" "Hub PR Validate" "validate"
for leaf in "${LEAF_REPOS[@]}"; do
  check_context "$leaf" "Leaf PR Validate" "leaf-local"
  check_context "$leaf" "Leaf PR Validate" "hub-cross-check"
done

if [ "$MISSING_CONTEXTS" -ne 0 ]; then
  echo "" >&2
  echo "FAIL: Some required check contexts have not appeared yet." >&2
  echo "Open a sample PR in each affected repo to trigger the workflows first." >&2
  exit 1
fi

# Apply branch protection
echo ""
echo "--- Applying branch protection ---"

apply_protection() {
  local repo="$1"
  shift
  local checks=("$@")

  local checks_json="["
  local first=true
  for ctx in "${checks[@]}"; do
    if [ "$first" = true ]; then first=false; else checks_json+=","; fi
    checks_json+="{\"context\":\"$ctx\",\"app_id\":15368}"
  done
  checks_json+="]"

  gh api --method PUT "repos/$OWNER/$repo/branches/main/protection" \
    --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "checks": $checks_json
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

  if [ $? -eq 0 ]; then
    echo "APPLIED $repo"
  else
    echo "FAIL $repo: branch protection API call failed" >&2
    exit 1
  fi
}

apply_protection "$HUB_REPO" "Hub PR Validate / validate"

for leaf in "${LEAF_REPOS[@]}"; do
  apply_protection "$leaf" "Leaf PR Validate / leaf-local" "Leaf PR Validate / hub-cross-check"
done

echo ""
echo "=== All repos protected ==="
echo ""
echo "Verify with:"
for repo in "${ALL_REPOS[@]}"; do
  echo "  gh api repos/$OWNER/$repo/branches/main/protection"
done
