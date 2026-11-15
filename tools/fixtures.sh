#!/usr/bin/env bash
# Builds the pull requests an e2e run tests remain against, on branches under e2e/<RUN_ID>/, from
# the commit checked out. Writes each pull request's number and head to GITHUB_OUTPUT as JSON
# (`fixtures`), and waits until GitHub has worked out which ones conflict.
# Needs RUN_ID, GH_REPO, GH_TOKEN (contents and pull-requests write), GITHUB_SERVER_URL.
set -euo pipefail

prefix="e2e/${RUN_ID:?}"
base="$prefix/main"
start=$(git rev-parse HEAD)
# The token goes in a header for each push, never into .git/config, as remain itself fetches.
auth=$(printf 'x-access-token:%s' "${GH_TOKEN:?}" | base64 -w0)
push() { git -c "http.${GITHUB_SERVER_URL:?}/.extraheader=AUTHORIZATION: basic $auth" push --quiet origin "$@"; }
commit() {
	git add --all
	git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
		-c commit.gpgsign=false commit --quiet --message "$1"
}
# The regen command in .github/remain.json, so the fixtures hold what remain would rebuild.
# shellcheck disable=SC2012
regen() { ls items | sort > items.index; }
branch() { git switch --quiet --create "$prefix/$1" "${2:-$start}"; }
# What later jobs need, kept as JSON for the `fixtures` output.
fixtures='{}'
output() {
	echo "$1: $2"
	fixtures=$(jq --compact-output --arg key "$1" --arg value "$2" '.[$key] = $value' <<< "$fixtures")
}

# Each pull request's side of a conflict. The base's side comes last, below.
branch union
echo union >> list.txt
commit 'union: append to list.txt'

branch regen
echo c > items/c
regen
commit 'regen: add items/c'

branch owner
sed -i 's/^two$/two (pr)/' code.txt
commit 'owner: change a line of code.txt'

branch never
echo '{ "bytes": 1200 }' > budgets/size.json
commit 'never: change budgets/size.json'

# A stack: child is based on parent's branch and appends after parent's line, so once parent has
# the base merged in, the child conflicts with parent's new head.
branch parent
echo p >> list.txt
commit 'parent: append p to list.txt'

branch child "$prefix/parent"
echo c >> list.txt
commit 'child: append c after p'

branch clean
echo clean > clean.txt
commit 'clean: add clean.txt'

cases=(union regen owner never parent child clean)
push "$start:refs/heads/$base" "${cases[@]/#/$prefix/}"
output base "$base"

declare -A numbers
for name in "${cases[@]}"; do
	target=$base
	[[ $name == child ]] && target=$prefix/parent
	url=$(gh pr create --base "$target" --head "$prefix/$name" --title "e2e $RUN_ID: $name" \
		--body "remain e2e fixture for run $RUN_ID. Closed when the run ends.")
	numbers[$name]=${url##*/}
	output "$name" "${numbers[$name]}"
	output "${name}_head" "$(git rev-parse "$prefix/$name")"
done

# The base's side of every conflict, pushed once the pull requests exist.
branch main
echo base >> list.txt
echo b > items/b
regen
sed -i 's/^two$/two (base)/' code.txt
echo '{ "bytes": 1100 }' > budgets/size.json
commit 'base: change every conflicting file'
push "$base"
output base_head "$(git rev-parse HEAD)"
echo "fixtures=$fixtures" >> "${GITHUB_OUTPUT:?}"

# A plain "not UNKNOWN" could catch a state from before the base moved, so each waits for its own.
"$(dirname "$0")/wait.sh" \
	"${numbers[union]}=DIRTY" "${numbers[regen]}=DIRTY" "${numbers[owner]}=DIRTY" \
	"${numbers[never]}=DIRTY" "${numbers[parent]}=DIRTY" \
	"${numbers[child]}!=UNKNOWN" "${numbers[child]}!=DIRTY" \
	"${numbers[clean]}!=UNKNOWN" "${numbers[clean]}!=DIRTY"
