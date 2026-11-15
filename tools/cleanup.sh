#!/usr/bin/env bash
# Closes an e2e run's pull requests and deletes its branches. Finds them by name, so it also cleans
# up after a fixtures job that failed partway.
# Needs RUN_ID, GH_REPO and GH_TOKEN (contents and pull-requests write).
set -euo pipefail

prefix="e2e/${RUN_ID:?}/"
for number in $(gh pr list --state open --limit 100 --json number,headRefName \
	--jq ".[] | select(.headRefName | startswith(\"$prefix\")) | .number"); do
	gh pr close "$number"
done
for ref in $(gh api "repos/$GH_REPO/git/matching-refs/heads/$prefix" --jq '.[].ref'); do
	gh api --method DELETE "repos/$GH_REPO/git/$ref"
	echo "deleted $ref"
done
