# ci-actions

Final Factory's portable CI steps. A job written with these runs unchanged on the FFBox build
server's runners (`ffgithubrunners`), on GitHub's hosted runners, or on any other self-hosted
machine. Which one is the `runs-on` line alone.

```yaml
jobs:
  checks:
    runs-on: ${{ vars.FF_LINUX_RUNNER || 'ffgithubrunners' }}
    steps:
      - uses: Final-Factory/ci-actions/checkout@<commit>
      - uses: Final-Factory/ci-actions/setup@<commit>
        with: { node: '24', gitleaks: 8.30.1 }
      - run: npm ci && npm test
      - uses: Final-Factory/ci-actions/upload@<commit>
        if: failure()
        with: { name: report, path: report }
```

| Action | On FFBox | Anywhere else |
|---|---|---|
| `checkout` (`fetch-depth`, `ref`) | asks the host to bring its mirror of the repository up to this commit and points git at it, then `actions/checkout` | `actions/checkout` |
| `setup` (`node`, `gitleaks`, `shellcheck`) | checks the image has each at the version asked for; a missing one fails, naming the line of ffbox `scripts/Dockerfile` to bump | uses what the runner has at that version, installs the rest: `actions/setup-node`, gitleaks from its release (checked against the release's checksums file), shellcheck from apt or brew |
| `playwright` (`browsers`, `working-directory`, `with-deps`) | checks the baked browsers are for this `@playwright/test`; a mismatch fails, naming the line to bump | `npx playwright install [--with-deps] <browsers>` |
| `upload` (`name`, `path`, `retention-days`) | `ffbox-handoff`: hands the zip and the job's own credential to the host, which uploads it | `actions/upload-artifact` |

An FFBox runner is recognised by `FFGHR_GIT_MIRROR`, which only the FFBox host sets when it starts
the container. Each action has an output `ffbox` saying which branch it took.

## Rules for changing this repository

- **Pin every `uses:` by full commit id, from an owner on the FFBox host's `action_cache_owners`
  (`actions`, `Final-Factory`).** An FFBox container cannot download actions. The host archives every
  branch and tag commit of this repository, and every third-party action its `action.yml` files pin by
  commit, into the cache the runner reads (ffbox `scripts/actioncache.py`). A tag or another owner is
  refused there and fails the job at "Set up job". `scripts/check-pins.sh` checks both, in CI.
- **Callers pin this repository by commit too**, for the same reason. The host polls about once a
  minute, so a commit pushed here is usable on FFBox within a minute.
- **`ffbox-handoff` is pinned by commit inside `upload`.** In a composite action `./` means the job's
  workspace, not this repository, so changing it takes two commits: the change, then the pin.
- **This repository is public.** A public repository's workflows can use its actions; nothing here is
  secret.
- A repository whose jobs run on FFBox must be on the host's `extra_mirrors` (ffbox `config.md`), or
  the host refuses to mirror it and `checkout` fails there.

## Choosing where a job runs

| | FFBox (`ffgithubrunners`) | GitHub-hosted (`ubuntu-latest`, ...) | Another self-hosted machine |
|---|---|---|---|
| **Cost** | no per-minute charge; the box's power and its capacity, shared with the game's builds and agent runs (`githubrunner.pool.max` jobs at once, 8 today) | **free for public repositories** on standard runners. Private: per minute from January 2026, Linux $0.006, Windows $0.010, macOS $0.062, after the plan's included minutes | no per-minute charge (GitHub postponed its announced $0.002/min self-hosted fee indefinitely; public repositories were always exempt); the machine and its upkeep |
| **Egress** | fenced: the npm registry, Unity and GitHub's Actions service only; never `github.com` or `api.github.com` | open | whatever the machine allows |
| **Isolation** | a fresh container per job, every capability dropped, single-use registration | a fresh VM per job | **persistent unless you make it otherwise**: one job's files, processes and credentials are there for the next |
| **Tools** | baked into the image (`setup` checks the versions); no `sudo` | installed per job; `sudo` | as installed |
| **Who can land a job** | any org repository naming `ffgithubrunners` (or `self-hosted`, which these runners also carry today); fork pull requests are refused by a job-started hook | anyone, in their own VM | any org repository naming its labels, **including fork pull requests on a public repository** unless the repository requires approval |

**Security, for a self-hosted runner and a public repository.** GitHub recommends against self-hosted
runners for public repositories: a fork's pull request can run arbitrary code on the machine. FFBox
is built for it (single-use containers, the fence, the fork guard, no secret in any job). Before
pointing a public repository's jobs at any other self-hosted machine: require approval for outside
contributors (Settings, Actions, General), use single-use (`--ephemeral` or JIT) registrations, give
the runner its own labels (a bare `self-hosted` reaches every runner in the organisation that kept
the default labels), and keep secrets out of jobs that a pull request can trigger.

**Visual baselines differ by runner.** Screenshot tests compare against images rendered on one
machine's fonts. A job moved between FFBox and GitHub's runners needs its baselines rendered again.
