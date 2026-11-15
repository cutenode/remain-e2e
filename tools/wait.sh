#!/usr/bin/env bash
# Waits until each pull request's mergeStateStatus matches, given as `12=DIRTY` or `13!=UNKNOWN`.
# GitHub computes it in the background after a push, so a read straight after one can be stale.
# Needs GH_REPO and GH_TOKEN. Gives up after WAIT_SECONDS (default 180).
set -euo pipefail

deadline=$((SECONDS + ${WAIT_SECONDS:-180}))
while :; do
	unmet=()
	for spec in "$@"; do
		if [[ $spec == *'!='* ]]; then
			number=${spec%%!=*} want=${spec#*!=} negate=true
		else
			number=${spec%%=*} want=${spec#*=} negate=false
		fi
		state=$(gh pr view "$number" --json mergeStateStatus --jq .mergeStateStatus)
		matched=false
		[[ $state == "$want" ]] && matched=true
		[[ $matched != "$negate" ]] || unmet+=("#$number is $state, wanted $spec")
	done
	if ((${#unmet[@]} == 0)); then
		echo "every pull request's state matches: $*"
		exit 0
	fi
	if ((SECONDS >= deadline)); then
		printf '::error::%s\n' "${unmet[@]}"
		exit 1
	fi
	printf '%s\n' "${unmet[@]}"
	sleep 5
done
