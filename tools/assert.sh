#!/usr/bin/env bash
# Checks what remain did to an e2e run's pull requests. Runs every check, then fails if any did.
# Needs GH_REPO, GH_TOKEN (contents, pull-requests and checks read), FIXTURES (the fixtures job's
# outputs as JSON) and REQUIRE_VERIFIED (true to fail on an unsigned merge commit).
set -euo pipefail

failed=0
ok() { echo "ok: $*"; }
bad() {
	echo "::error::$*"
	failed=1
}
expect() { # what, got, wanted
	if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1: got $(printf %q "$2"), wanted $(printf %q "$3")"; fi
}
fixture() { jq --exit-status --raw-output --arg key "$1" '.[$key]' <<< "${FIXTURES:?}"; }
head_of() { gh api "repos/$GH_REPO/pulls/$(fixture "$1")" --jq .head.sha; }
file_at() { gh api --header 'Accept: application/vnd.github.raw+json' "repos/$GH_REPO/contents/$2?ref=$1"; }

# Checks that a pull request's head is now a merge of its old head and `second`, and prints the
# merge commit's signature. Sets `merge` to the new head.
merged() { # name, second parent
	merge=$(head_of "$1")
	local parents verification
	parents=$(gh api "repos/$GH_REPO/commits/$merge" --jq '[.parents[].sha] | join(" ")')
	expect "$1: $merge's parents are its old head and $2" "$parents" "$(fixture "$1_head") $2"
	verification=$(gh api "repos/$GH_REPO/commits/$merge" --jq '.commit.verification | "\(.verified) \(.reason)"')
	# Whether an App's API commits get signed is what this is finding out, so it only fails on request.
	if [[ $verification == true* ]]; then
		ok "$1: $merge is verified"
	elif [[ ${REQUIRE_VERIFIED:-false} == true ]]; then
		bad "$1: $merge isn't verified ($verification)"
	else
		echo "::warning::$1: $merge isn't verified ($verification)"
	fi
}

# Checks that a pull request kept its head and got the label and one comment naming `file`.
needs_owner() { # name, file
	local number bodies
	number=$(fixture "$1")
	expect "$1: head didn't move" "$(head_of "$1")" "$(fixture "$1_head")"
	expect "$1: labelled needs-owner" \
		"$(gh api "repos/$GH_REPO/issues/$number/labels" --jq 'any(.[]; .name == "needs-owner")')" true
	bodies=$(gh api "repos/$GH_REPO/issues/$number/comments?per_page=100" \
		--jq '[.[] | select(.body | startswith("<!-- remain -->")) | .body]')
	expect "$1: one remain comment" "$(jq length <<< "$bodies")" 1
	expect "$1: the comment names $2" "$(jq --arg file "\`$2\`" 'any(.[]; contains($file))' <<< "$bodies")" true
}

base_head=$(fixture base_head)

merged union "$base_head"
union_head=$merge
expect 'union: list.txt keeps both lines' "$(file_at "$merge" list.txt)" $'first\nunion\nbase'

merged regen "$base_head"
expect 'regen: items.index is rebuilt' "$(file_at "$merge" items.index)" $'a\nb\nc'

needs_owner owner code.txt
needs_owner never budgets/size.json

# Round one merges the base into the parent, round two the parent's new head into the child.
merged parent "$base_head"
parent_head=$merge
merged child "$parent_head"
expect 'child: list.txt has every line' "$(file_at "$merge" list.txt)" $'first\np\nc\nbase'

expect "clean: head didn't move" "$(head_of clean)" "$(fixture clean_head)"

# The App's push should start ci.yml on the pull request, which a GITHUB_TOKEN push wouldn't.
deadline=$((SECONDS + ${CI_WAIT_SECONDS:-300}))
while :; do
	url=$(gh api "repos/$GH_REPO/commits/$union_head/check-runs?check_name=ci" --jq '.check_runs[0].html_url // ""')
	if [[ -n $url ]]; then
		ok "union: the push started ci on $union_head: $url"
		break
	fi
	if ((SECONDS >= deadline)); then
		bad "union: no ci check run on $union_head"
		break
	fi
	sleep 10
done

exit "$failed"
