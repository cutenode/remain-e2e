# remain-e2e

End-to-end tests for [remain](https://github.com/cutenode/remain) against real GitHub: real pull requests, real mergeability, and pushes from remain's App.

## What a run does

`e2e.yml` takes the remain commit to test and:

1. Makes a base branch `e2e/<run id>/main` from main and opens pull requests into it, one per case: a union list (`list.txt`), a regenerated file (`items.index`), a code conflict (`code.txt`), a file a rule names without a fix (`budgets/size.json`), a stack of two, and a clean one. Then it moves the base so all but the clean one and the stack's child conflict.
2. Runs remain twice: the first round merges the base in, the second merges the stack's parent into its child. By default each round runs the action at `ref` (`round.yml`); with `via=workflow` it calls remain's reusable workflow on main instead, as a caller would.
3. Checks the results with `tools/assert.sh`: the merge commits and their contents, whether GitHub verified them, the `needs-owner` label and comment, the clean pull request left alone, and that the App's push started `ci` on the pull request.
4. Closes the pull requests and deletes the run's branches, pass or fail.

## Running it

```bash
gh workflow run e2e.yml -R cutenode/remain-e2e -f ref=<remain commit sha>
```

Add `-f require-verified=true` to fail when the merge commits aren't signed. By default it only warns. `-f via=workflow` tests the reusable workflow on remain's main and ignores `ref`.

## What it needs

- remain's App installed on this repository, as in [remain's setup](https://github.com/cutenode/remain#the-app), with an environment `remain` holding the secret `REMAIN_PRIVATE_KEY` and the Actions variable `REMAIN_CLIENT_ID`.
- Settings, Actions, General, Workflow permissions: "Allow GitHub Actions to create and approve pull requests" ticked, so the fixtures job can open pull requests with `GITHUB_TOKEN`.

## License

MIT
