# Shared GitHub Actions (RevealUIStudio)

Composite actions and reusable workflows for the fleet. Callers pin to an
**immutable commit SHA** (same rule as `backflow-reusable.yml`).

## promotion-gate (composite)

Enforces `test` → `main` promotion policy (head branch, same-repo origin,
merge-commit ancestry).

**Why a composite action (not a reusable workflow):** repository rulesets
require the check context name `promotion-gate`. A `workflow_call` job would
surface as `promotion-gate / <job-id>` and break those rulesets without a
settings migration. Composite keeps the job id in each caller.

### Caller (thin)

```yaml
name: promotion-gate
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  promotion-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: RevealUIStudio/.github/.github/actions/promotion-gate@<pin-sha>
        with:
          head_ref: ${{ github.head_ref }}
          head_repo: ${{ github.event.pull_request.head.repo.full_name }}
          base_repo: ${{ github.repository }}
          head_sha: ${{ github.event.pull_request.head.sha }}
          base_ref: ${{ github.event.pull_request.base.ref }}
```

Bump the pin via Dependabot `github-actions` or a deliberate fleet PR.

## CLIENT_LEAK_PATTERNS

One organization Actions secret. Do not commit the pattern list, and do not
create a separate repository secret per repo.

Set it under Organization secrets for `revealui-studio`:
[Secrets and variables → Actions](https://github.com/organizations/revealui-studio/settings/secrets/actions).
Name: `CLIENT_LEAK_PATTERNS`. Repository access: Selected repositories.
Grant `agency`, `revcon`, `revdev`, `revkit`, `revmind`, `revskills`,
`revvault`, and `status`.

Value: one `tag|literal|reason` line per pattern. Jobs read
`secrets.CLIENT_LEAK_PATTERNS` and pass it as the workflow secret
`client_leak_patterns`. An empty value fails closed. An environment secret
or a Dependabot secret is invisible here: these jobs do not set
`environment:`, and they are not Dependabot.

## check-client-leaks (composite)

Runs `scripts/check-client-leaks.sh` in the consumer repo. Keep job **name**
`Client / prospect name leak scan` on the caller (ruleset-required on some repos).
CI must pass the org secret. The scanner fails closed when it is empty.

```yaml
jobs:
  scan:
    name: Client / prospect name leak scan
    runs-on: ubuntu-latest
    timeout-minutes: 3
    steps:
      - uses: RevealUIStudio/.github/.github/actions/check-client-leaks@<pin-sha>
        with:
          client_leak_patterns: ${{ secrets.CLIENT_LEAK_PATTERNS }}
```

## duplicate-open-pr (composite)

Closes a newly opened PR when its changed-path set overlaps an **older**
open PR against the same base at Jaccard ≥ 0.8. Check context name is
exactly `duplicate-open-pr`. Runs via `pull_request_target` on the
**base** branch so Cursor snowflake heads still hit the lock.

Does not require a GAP id in the branch name. Path overlap is the key.
A 1-file follow-up against a larger sibling PR stays open (Jaccard stays
low). Add `not-a-duplicate` to skip.

### Caller (thin)

```yaml
name: duplicate-open-pr
on:
  pull_request_target:
    types: [opened, reopened, synchronize]
permissions:
  contents: read
  pull-requests: write
jobs:
  duplicate-open-pr:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: RevealUIStudio/.github/.github/actions/duplicate-open-pr@<pin-sha>
```

Do not checkout the PR head in this job.

## issue-leak-scan (reusable workflow)

Scans issue/PR/comment bodies via gitleaks + `.gitleaks.issues.toml` on the
consumer default branch. Not a required status check → `workflow_call` is fine.

```yaml
name: Issue + PR Body Leak Scan
on:
  issues: { types: [opened, edited] }
  pull_request_target: { types: [opened, edited] }
  issue_comment: { types: [created, edited] }
permissions:
  issues: write
  pull-requests: write
  contents: read
concurrency:
  group: leak-scan-${{ github.event.issue.number || github.event.pull_request.number }}-${{ github.event.action }}
  cancel-in-progress: false
jobs:
  scan:
    uses: RevealUIStudio/.github/.github/workflows/issue-leak-scan-reusable.yml@<pin-sha>
    secrets:
      client_leak_patterns: ${{ secrets.CLIENT_LEAK_PATTERNS }}
```

Pass that one secret only. `secrets: inherit` on `pull_request_target` would
forward every caller secret into the reusable workflow.
