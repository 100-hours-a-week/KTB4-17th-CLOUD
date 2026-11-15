# Four fixed direct-Argo coordinators

The protected trusted inline Pipeline maps exactly these jobs:

| Coordinator | Existing source CI | Branch | Environment |
|---|---|---|---|
| `cd/backend-dev` | `ci/backend/dev` | `dev` | staging |
| `cd/ai-dev` | `ci/ai/dev` | `dev` | staging |
| `cd/backend-main` | `ci/backend/main` | `main` | prod |
| `cd/ai-main` | `ci/ai/main` | `main` | prod |

A SUCCESS notification must contain an exact source Run cause. The controller
validates repository/branch SCM configuration, completed SUCCESS result, typed
CI-only parameters, recorded derived deployment flags, SCMRevisionAction and
matching BuildData. SCMRevisionAction must belong to the configured SCM source
ID; a legacy null source ID additionally requires independent repository and
branch-bound BuildData. Foreign/ambiguous SCM evidence fails closed. No application
checkout or source script runs in the trusted coordinator.

If that Run already requested `PUSH_IMAGE=true`, its exact artifacts are reused.
Otherwise the controller examines at most the newest **50 Runs of the same fixed
source job**, newest first, for an existing completed SUCCESS publisher with
`PUSH_IMAGE=true`, all legacy paths disabled, valid repository/branch/SCM source
provenance, and **exactly the fresh trigger's full source SHA**. It checks the
required exact-Run artifact files exist and fit the size bound before choosing.
Foreign/incomplete/unpublished candidates are ineligible. No moving build URL,
`lastSuccessfulBuild`, arbitrary older SHA, synthetic trigger or source execution
is involved in this search.

If no eligible archived publisher exists within that bound, the same source CI
is invoked with `PUSH_IMAGE=true` and every legacy deployment/PR switch false.
Waiting uses `agent none`, so the source CI can use the single executor. A newly
requested producer must be SUCCESS, carry the coordinator cause for this exact
CD build number and pass the same checks. The build step and reverse trigger use
absolute `/ci/...` paths; returned RunWrapper job identity is checked before
reopening its number. If this newly requested producer tested a newer SHA than
the trigger, its exact validated Run becomes the candidate. Reuse always binds
the trigger and publisher SHA identically.

`publisher-selection.json` records the actual trigger and publisher Run IDs,
full SHAs, selection mode and bounded scan count. For example, a fresh
`ci/ai/main#10` ordinary CI success may use exact publisher `ci/ai/main#8` at the
same SHA without rebuilding an already immutable image tag. The normalized
release retains producer Run #8 identity and its original archived publisher
proof; the shared release interface is unchanged.

Archived artifact age is not itself a deployment approval. The agent normalizer
rejects forged/disagreeing evidence, and the deployment helper independently
requires current source HEAD, immutable source/version ECR digest agreement,
current exact release workflow/tag proof and the environment's schema approval
before any patch. A moved HEAD or removed/changed tag therefore blocks reuse.
Semantically invalid chosen artifacts fail closed; the coordinator does not
silently rebuild or weaken the publisher's immutable-tag guard. Missing retained
evidence or a publisher outside the 50-Run bound falls back to the existing full
CI publication path, whose existing immutable-tag guard may itself refuse a
nonidentical rebuild. No tag is overwritten or deleted.
The producer's own SUCCESS also notifies CD. Runs caused by that coordinator
exit NOT_BUILT; coalesced notifications retain the newest legitimate success.
Each coordinator serializes its own deployments with `disableConcurrentBuilds()`.
No moving build URL or `lastSuccessfulBuild` is used.

Only then does a `linux && docker` agent transport allowlisted artifacts from the
exact Run's ArtifactManager. Files are bounded at 128 KiB and never executed.
`validate_upstream.py` rejects extra/missing/symlink inputs and duplicate JSON
keys, checks all source/version/tag/digest/image agreements, and emits the
schema_version=2 interface in `design.md`. Dev uses `dev-FULL_SHA`. Main preserves
the existing publisher's `released` (`vX.Y.Z`) or `no-release` (`sha-FULL_SHA`)
semantics. Known BE/AI publisher fields become only this sanitized projection:

```
publisher_version = {
  workflow_run_id, workflow_run_attempt,
  workflow_path: ".github/workflows/release.yml",
  workflow_url: "https://github.com/EXPECTED_REPOSITORY/actions/runs/ID",
  git_release_tag: "vX.Y.Z" | null
}
```

`release_outcome` and `publisher_version` appear only for main. The normalizer
checks the archive's consistency; the deployment helper independently rechecks
GitHub workflow/ref identity and ECR evidence before mutation. The archived
record is not itself permission to deploy an unverified Git tag.

The helper invocation is fixed:

```sh
python3 -B /opt/star23-direct-cd/deploy_release.py --family "$CD_FAMILY" \
  --environment "$CD_ENVIRONMENT" --source-branch "$CD_SOURCE_BRANCH" \
  --source-commit "$CD_SOURCE_SHA" --release-file verified-release.json \
  --output-file deployment.json --execute
```

The existing fixed kubectl remains `/opt/star23-staging-cd/bin/kubectl`. The
new helper keeps isolated receipts under
`/var/lib/jenkins/deployments/{staging,prod}/{be,ai}` and checks protected
`/opt/star23-direct-cd/contracts/{environment}-{family}.json` migration approvals
before the first Argo patch. Missing/changed approvals stop deployment. No
migration execution or automatic rollback occurs.

All four **global** legacy flags must remain unset/empty/false:
`STAR23_AUTO_DEPLOY_STAGING`, `AI_STAGING_AUTO_DEPLOY_ENABLED`,
`STAR23_AUTO_DEPLOY_PROD`, `AI_PROD_AUTO_DEPLOY_ENABLED`. Duplicate definitions
fail closed. The preserved AI enable flag is **job-local**: AI dev sets only its
staging flag true; AI main sets only its production flag true. These local flags
are not source producer parameters. Source CI's own recorded legacy flags must
still prove CI/ECR-only behavior. The coordinator binds only the existing source
App read credential `github-app-star23`, and no CLOUD writer or personal token.

## Installation

`install-coordinators.groovy` defaults to preview. Install the reviewed policy,
Pipeline template, normalizer and `deploy_release.py` in root-owned,
non-symlink, non-group/world-writable `/opt/star23-direct-cd`. The installer checks
ownership/permissions/nonempty bounded files and prints SHA-256 fingerprints.
The historical kubectl root/bin/binary must also be root-owned, non-symlink,
non-writable to Jenkins, and the binary executable. Populate the four protected
migration approvals from actual schema/deployed-source evidence first.

Validate the assembled Pipeline on actual Jenkins 2.580.2 before enabling jobs.
The local Groovy tests use boundary stubs and cannot establish real plugin
compatibility. After reviewing preview, the authorized operator can set
`APPLY=true`. The installer upgrades only the two dev jobs with the known v1
managed marker and jobs bearing the v2 managed marker; it refuses unrelated
jobs or active/queued coordinators. Reapplication removes every previous trigger
and concurrency property before adding exactly one typed SUCCESS trigger and
concurrency property, preserving unrelated properties. New jobs are first persisted through
`createProjectFromXML` with the managed marker and exact definition in that
initial config, so interruption cannot leave an unowned orphan.

`bootstrap-staging-cd.groovy` retains its historical filename but installs the
new direct-CD payload and writes `direct-cd-bootstrap.json`. It validates the
real classpath/declarative model and exact script approval, then revalidates and
reapplies the installer each time while idle. It verifies each job is enabled
and buildable, with exactly one absolute SUCCESS trigger and one non-aborting
concurrency property. A disabled job fails with an actionable operator message;
its disabled state is preserved. It never queues builds, contains
no historical Run IDs, and never restarts Jenkins. Retire an earlier installed
staging bootstrap before enabling this version so an old seed timer cannot run.
`refresh-source-cache.groovy` is historical cache-repair tooling, not part of
installation or the deployment path; do not invoke it as a bootstrap step.

## Local verification and acceptance

```sh
python3 -B -m unittest discover -s tests -v
```

Python uses only the standard library. Groovy tests use a local Groovy jar (or
`GROOVY_JAR`) and Java. Tests execute real policy, normalizer, installer replacement
and Pipeline flow with Jenkins/step IO boundaries stubbed: four fixed profiles,
released/no-release semantics, exact typed triggers, loop/coalescing suppression,
producer failure/cause rejection, same-SHA archived-publisher reuse and bounded
real Run/ArtifactManager scanning, changed/forged artifact and stale-HEAD
rejection, no executor while
waiting, all legacy global flags disabled, sanitized evidence and repeated
installer application. No test contacts Jenkins, GitHub, AWS or a cluster.

Acceptance requires actual source SUCCESS triggering each of the four paths,
matching immutable source/version ECR digests, isolated durable receipts,
Synced/Healthy Argo Applications and Ready Pods using the verified digest. A
manual production release or a NOT_BUILT loop event is not proof of that path.
