#!/usr/bin/env bash
# Exercises the backflow-current exemption predicate embedded in the reusable
# workflow. The predicate must stay inline there: pull_request checkouts the
# caller repo, so a script file in that checkout is not the pinned policy.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
wf="$root/.github/workflows/backflow-reusable.yml"

if grep -F 'backflow PR itself' "$wf" >/dev/null; then
  echo "old branch-name exemption is still present" >&2
  exit 1
fi

predicate=$(mktemp)
trap 'rm -f "$predicate"' EXIT
awk '
  /^[[:space:]]*# BEGIN backflow exemption predicate$/,/^[[:space:]]*# END backflow exemption predicate$/ {
    sub(/^[[:space:]]*/, "")
    print
  }
' "$wf" > "$predicate"

if ! grep -q 'is_backflow_exemption()' "$predicate"; then
  echo "exemption predicate markers missing from workflow" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$predicate"

python3 - "$wf" "$predicate" <<'PY'
import sys
import yaml

path, predicate_path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
predicate = open(predicate_path, encoding="utf-8").read()
# Older comments in this workflow already use em dashes. Scan only the new
# predicate and the new input description.
start = text.find("      backflow_bot_login:")
end = text.find("    secrets:", start)
chunk = text[start:end] + predicate
for ch, name in (("\u2014", "em dash"), ("\u2013", "en dash")):
    if ch in chunk:
        raise SystemExit(f"new exemption text contains an {name}")

# PyYAML 1.1 treats the workflow key "on" as boolean true.
doc = yaml.safe_load(text)
inputs = doc[True]["workflow_call"]["inputs"]
bot = inputs["backflow_bot_login"]
if bot.get("required") is not False:
    raise SystemExit("backflow_bot_login must stay optional")
if bot.get("default") != "":
    raise SystemExit("backflow_bot_login default must stay empty")
if bot.get("type") != "string":
    raise SystemExit("backflow_bot_login type must stay string")

secrets = doc[True]["workflow_call"]["secrets"]
for name in ("BACKFLOW_APP_ID", "BACKFLOW_APP_PRIVATE_KEY"):
    if name not in secrets or secrets[name].get("required") is not True:
        raise SystemExit(f"secret {name} must stay required")

jobs = doc["jobs"]
if "backflow" not in jobs or "backflow-current" not in jobs:
    raise SystemExit("job ids changed")
gate = jobs["backflow-current"]
if gate.get("name") != "backflow-current":
    raise SystemExit("backflow-current name changed")
if gate.get("if") != "github.event_name == 'pull_request'":
    raise SystemExit("backflow-current if changed")
print("workflow contract ok")
PY

fail=0
check() {
  local expect="$1"
  shift
  local actual="no"
  if is_backflow_exemption "$@"; then
    actual="yes"
  fi
  if [ "$actual" != "$expect" ]; then
    echo "FAIL expected $expect got $actual :: $*" >&2
    fail=1
  else
    echo "ok $expect :: $1"
  fi
}

branch="chore/backflow-main-into-test"

# Branch name alone, including a populated bot-shaped author, does not skip.
check no "$branch" "" "app-slug[bot]" "Bot" "1" "1" "o/r" "o/r"
check no "$branch" "   " "app-slug[bot]" "Bot" "1" "1" "o/r" "o/r"

# App slug and bot login both match the bot account, case-insensitively.
check yes "$branch" "app-slug" "app-slug[bot]" "Bot" "1" "1" "o/r" "o/r"
check yes "$branch" "  app-slug  " "app-slug[bot]" "Bot" "1" "1" "o/r" "o/r"
check yes "$branch" "App-Slug" "app-slug[bot]" "Bot" "1" "1" "Org/Repo" "org/repo"
check yes "$branch" "app-slug[bot]" "App-Slug[bot]" "Bot" "42" "42" "o/r" "o/r"

# Fork, mismatched name, missing id, or a non-numeric id.
check no "$branch" "app-slug" "app-slug[bot]" "Bot" "7" "8" "o/r" "o/r"
check no "$branch" "app-slug" "app-slug[bot]" "Bot" "1" "1" "o/r" "other/r"
check no "$branch" "app-slug" "app-slug[bot]" "Bot" "" "" "o/r" "o/r"
check no "$branch" "app-slug" "app-slug[bot]" "Bot" "null" "null" "o/r" "o/r"
check no "$branch" "app-slug" "app-slug[bot]" "Bot" "1" "1" "" ""
check no "$branch" "app-slug" "app-slug[bot]" "Bot" "1" "1" "null" "null"

# Author must be that bot account. A person, a different bot, or a non-Bot type does not skip.
check no "$branch" "app-slug" "person" "User" "1" "1" "o/r" "o/r"
check no "$branch" "person" "person" "User" "1" "1" "o/r" "o/r"
# A slug means slug[bot]. It does not match a human, or a bot whose login lacks [bot].
check no "$branch" "person" "person" "Bot" "1" "1" "o/r" "o/r"
check no "$branch" "app-slug" "app-slug[bot]" "User" "1" "1" "o/r" "o/r"
check no "$branch" "app-slug" "other-app[bot]" "Bot" "1" "1" "o/r" "o/r"
check no "$branch" "app-slug[bot]" "app-slug" "Bot" "1" "1" "o/r" "o/r"

# Any other branch still runs the normal check, even for the in-repo bot.
check no "feature" "app-slug" "app-slug[bot]" "Bot" "1" "1" "o/r" "o/r"
check no "chore/backflow-main-into-test-evil" "app-slug" "app-slug[bot]" "Bot" "1" "1" "o/r" "o/r"

# Reject logins the pattern does not describe.
check no "$branch" "app_slug" "app_slug[bot]" "Bot" "1" "1" "o/r" "o/r"
check no "$branch" "app slug" "app slug[bot]" "Bot" "1" "1" "o/r" "o/r"
check no "$branch" "[bot]" "[bot]" "Bot" "1" "1" "o/r" "o/r"
check no "$branch" '$(id)' '$(id)[bot]' "Bot" "1" "1" "o/r" "o/r"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "exemption predicate ok"
