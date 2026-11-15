"""Direct release acceptance tests. Only external boundaries are faked."""
import copy
import contextlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import test_deploy_staging as legacy

PATH = Path(__file__).with_name('deploy_release.py')
if PATH.exists():
    spec = importlib.util.spec_from_file_location('deploy_release', PATH)
    cd = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cd)
else:
    cd = None


def release(family='ai', environment='staging'):
    branch = 'dev' if environment == 'staging' else 'main'
    job = ('ci/backend/' if family == 'be' else 'ci/ai/') + branch
    data = dict(schema_version=2, family=family, source_repository=legacy.cd.SOURCE_REPOS[family],
                source_branch=branch, environment=environment, source_commit=legacy.SHA,
                image_tag='dev-' + legacy.SHA if branch == 'dev' else 'v1.2.3',
                image_digest=legacy.DIGEST, source_job=job, build_number=17, run_id=job+'#17', result='SUCCESS')
    if environment == 'prod':
        data.update(release_outcome='released', publisher_version=dict(workflow_run_id=91, workflow_run_attempt=2,
            workflow_path='.github/workflows/release.yml', workflow_url='https://github.com/' + data['source_repository'] + '/actions/runs/91',
            git_release_tag='v1.2.3'))
    return data


def contract(family='ai', environment='staging'):
    path = 'alembic/versions/z6_example.py' if family == 'ai' else 'src/main/resources/db/migration/V1__schema.sql'
    return dict(schema_version=1, family=family, environment=environment,
                source_repository=legacy.cd.SOURCE_REPOS[family], database_identity_sha256='d'*64,
                schema_revision='z6' if family == 'ai' else '1', verified_at_utc='2026-11-15T12:00:00Z',
                migration_files=[dict(path=path, blob_sha='e'*40)])


class External(legacy.ExternalSystems):
    def __init__(self, family='ai', environment='staging'):
        super().__init__(family)
        self.environment = environment
        self.branch_reads = []
        self.candidate = contract(family, environment)['migration_files']
        self.tree = {'sha': 'f'*40, 'truncated': False, 'tree': [dict(path=x['path'], sha=x['blob_sha'], type='blob', mode='100644') for x in self.candidate]}
        self.tree_reads = []
        self.workflow_override = {}
        self.tag_commit = legacy.SHA
        self.semantic_tags = ['v1.2.3'] if environment == 'prod' else []
        self.latest_override = {}
        self.semantic_job_override = {}
        self.semantic_step_override = {}
        self.job_absent = False
        self.extra_jobs = []
        self.tags_verified = []
        if environment == 'prod':
            for name, app in self.apps.items():
                app['spec']['source']['helm']['valueFiles'] = ['values/' + name + '.yaml']

    def __enter__(self): return self

    def __exit__(self, *unused): pass

    def ecr_tag_digest(self, family, tag):
        self.tags_verified.append(tag)
        return super().ecr_tag_digest(family, tag)

    def source_head(self, family, branch):
        self.branch_reads.append(branch)
        return super().source_head(family)

    def source_tree(self, family, commit):
        self.tree_reads.append((family, commit))
        return copy.deepcopy(self.tree)

    def workflow_run(self, family, run_id, attempt):
        result = dict(id=run_id, run_attempt=attempt, path='.github/workflows/release.yml', head_sha=legacy.SHA,
                    head_branch='main', event='push', status='completed', conclusion='success',
                    html_url='https://github.com/' + legacy.cd.SOURCE_REPOS[family] + '/actions/runs/' + str(run_id),
                    repository=dict(full_name=legacy.cd.SOURCE_REPOS[family]),
                    head_repository=dict(full_name=legacy.cd.SOURCE_REPOS[family]), run_number=12)
        result.update(self.workflow_override)
        return result

    def latest_release_workflow_run(self, family, commit):
        item = self.workflow_run(family, 91, 2)
        item.update(self.latest_override)
        return item

    def workflow_attempt_jobs(self, family, run_id, attempt):
        if self.job_absent: return []
        step = dict(name='Semantic Release', status='completed', conclusion='success', number=4)
        step.update(self.semantic_step_override)
        job = dict(id=311, run_id=run_id, run_attempt=attempt, head_sha=legacy.SHA,
                   name='Semantic Release', status='completed', conclusion='success', steps=[step])
        job.update(self.semantic_job_override)
        return [job] + self.extra_jobs

    def release_tag_commit(self, family, tag):
        return self.tag_commit

    def semantic_tags_at_commit(self, family, commit):
        return self.semantic_tags


class DirectTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(cd, 'direct release helper must exist')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = External()
        self.data = release()
        self.approval = contract()
        self.read = patch.object(cd, 'read_schema_contract', side_effect=lambda *args: copy.deepcopy(self.approval))
        self.read.start()
        self.addCleanup(self.read.stop)

    def request(self):
        return cd.request_from_release(self.data, self.data['family'], self.data['environment'], self.data['source_branch'], self.data['source_commit'], 1)

    def deploy(self):
        return cd.deploy(self.request(), self.runtime, self.root/'state', self.root/'result.json', clock=self.runtime.clock, sleep=self.runtime.sleep)

    def test_all_four_profiles_deploy_with_isolated_environment_receipts(self):
        for env in ('staging', 'prod'):
            for family in ('ai', 'be'):
                with self.subTest(env=env, family=family):
                    self.data = release(family, env)
                    self.approval = contract(family, env)
                    self.runtime = External(family, env)
                    result = self.deploy()
                    self.assertEqual(result['status'], 'succeeded')
                    self.assertEqual(result['environment'], env)
                    self.assertEqual(result['cluster'], 'star-EKS-v3-staging' if env == 'staging' else 'star-EKS-v3')
                    self.assertEqual(result['run_id'], self.data['run_id'])
                    self.assertEqual(set(self.runtime.branch_reads), {self.data['source_branch']})
                    self.assertTrue((self.root/'state'/env/family/'last-good.json').exists())
                    self.assertEqual(self.runtime.tree_reads, [(family, legacy.SHA)])
                    self.assertEqual(self.runtime.tags_verified, [legacy.SHA, self.data['image_tag']])

    def test_release_schema_rejects_identity_field_drift_and_extra_fields(self):
        for field, value in [('schema_version', True), ('result', 'FAILURE'), ('source_branch', 'main'), ('environment', 'prod'), ('source_job', 'ci/ai/main'), ('build_number', True), ('run_id', 'ci/ai/dev#18'), ('image_tag', 'latest'), ('image_digest', legacy.OLD_DIGEST), ('surprise', 'x')]:
            data = dict(self.data)
            data[field] = value
            if field == 'image_digest':
                # Digest shape is valid; ECR equality is checked separately.
                continue
            with self.subTest(field=field), self.assertRaises(cd.DeployError):
                cd.request_from_release(data, 'ai', 'staging', 'dev', legacy.SHA, 1)

    def test_production_independent_workflow_and_release_tag_proof_blocks_before_patch(self):
        for field, value in [('head_sha', legacy.OTHER_SHA), ('head_branch', 'dev'), ('event', 'workflow_dispatch'),
                             ('conclusion', 'failure'), ('path', '.github/workflows/foreign.yml'), ('run_attempt', 1),
                             ('repository', {'full_name': 'foreign/repo'})]:
            self.data = release('ai', 'prod'); self.approval = contract('ai', 'prod'); self.runtime = External('ai', 'prod')
            self.runtime.workflow_override[field] = value
            with self.subTest(field=field), self.assertRaises(cd.DeployError): self.deploy()
            self.assertEqual(self.runtime.patched, [])
        self.runtime = External('ai', 'prod'); self.runtime.tag_commit = legacy.OTHER_SHA
        with self.assertRaises(cd.DeployError): self.deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_production_no_release_requires_successful_workflow_and_no_semantic_tag(self):
        self.data = release('ai', 'prod'); self.approval = contract('ai', 'prod'); self.runtime = External('ai', 'prod')
        self.data.update(image_tag='sha-' + legacy.SHA, release_outcome='no-release')
        self.data['publisher_version']['git_release_tag'] = None
        self.runtime.semantic_tags = []
        self.assertEqual(self.deploy()['status'], 'succeeded')
        self.runtime = External('ai', 'prod'); self.runtime.semantic_tags = ['v1.2.3']
        with self.assertRaises(cd.DeployError): self.deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_publisher_rejects_historical_success_and_skipped_semantic_job_or_step(self):
        for outcome in ('released', 'no-release'):
            for mutation in ('later_failed_attempt', 'later_failed_run', 'missing_job', 'skipped_job', 'skipped_step', 'wrong_job_attempt'):
                self.data = release('ai', 'prod'); self.approval = contract('ai', 'prod'); self.runtime = External('ai', 'prod')
                if outcome == 'no-release':
                    self.data.update(image_tag='sha-' + legacy.SHA, release_outcome=outcome)
                    self.data['publisher_version']['git_release_tag'] = None
                    self.runtime.semantic_tags = []
                if mutation == 'later_failed_attempt': self.runtime.latest_override.update(run_attempt=3, conclusion='failure')
                elif mutation == 'later_failed_run': self.runtime.latest_override.update(id=92, run_number=13, conclusion='failure')
                elif mutation == 'missing_job': self.runtime.job_absent = True
                elif mutation == 'skipped_job': self.runtime.semantic_job_override['conclusion'] = 'skipped'
                elif mutation == 'skipped_step': self.runtime.semantic_step_override['conclusion'] = 'skipped'
                else: self.runtime.semantic_job_override['run_attempt'] = 1
                with self.subTest(outcome=outcome, mutation=mutation), self.assertRaises(cd.DeployError): self.deploy()
                self.assertEqual(self.runtime.patched, [])

    def test_released_semantic_tag_set_must_be_exactly_the_declared_tag(self):
        for tags in ([], ['v1.2.4'], ['v1.2.3', 'v1.2.4']):
            self.data = release('be', 'prod'); self.approval = contract('be', 'prod'); self.runtime = External('be', 'prod')
            self.runtime.semantic_tags = tags
            with self.subTest(tags=tags), self.assertRaises(cd.DeployError): self.deploy()
            self.assertEqual(self.runtime.patched, [])

    def test_last_good_rename_then_directory_fsync_failure_never_relabels_success_partial(self):
        original_replace, original_fsync = cd.os.replace, cd.os.fsync
        renamed = [False]
        def replace(source, target):
            original_replace(source, target)
            if Path(target).name == 'last-good.json': renamed[0] = True
        def fsync(descriptor):
            if renamed[0] and stat.S_ISDIR(cd.os.fstat(descriptor).st_mode):
                renamed[0] = False
                raise OSError('simulated directory durability failure')
            return original_fsync(descriptor)
        with patch.object(cd.os, 'replace', replace), patch.object(cd.os, 'fsync', fsync):
            with self.assertRaises(cd.DeployError): self.deploy()
        directory = self.root/'state/staging/ai'
        good = json.loads((directory/'last-good.json').read_text())
        self.assertEqual(good['status'], 'succeeded')
        self.assertEqual(json.loads((directory/'current.json').read_text()), good)
        self.assertEqual(json.loads((directory/'history'/(good['release_id']+'.json')).read_text()), good)
        self.assertEqual(json.loads((self.root/'result.json').read_text()), good)
        observation = json.loads((self.root/'result.commit.json').read_text())
        self.assertEqual(observation['status'], 'commit-durability-unknown')
        self.assertTrue(observation['last_good_matches'])

    def test_cli_runtime_activation_failure_records_rejected_run_without_active_pointer_changes(self):
        good = self.deploy()
        directory = self.root/'state/staging/ai'
        before = {name: (directory/name).read_bytes() for name in ('current.json', 'last-good.json')}
        release_path = self.root/'verified-release.json'; release_path.write_text(json.dumps(self.data))
        arguments = ['--family', 'ai', '--environment', 'staging', '--source-branch', 'dev',
                     '--source-commit', legacy.SHA, '--release-file', str(release_path),
                     '--output-file', str(self.root/'activation.json'), '--execute']
        identity = {'Account': '975779326240', 'Arn': 'arn:aws:sts::975779326240:assumed-role/star23-ci-controller/ci'}
        cluster = {'cluster': {'name': 'star-EKS-v3-staging', 'status': 'ACTIVE',
                   'arn': 'arn:aws:eks:ap-northeast-2:975779326240:cluster/star-EKS-v3-staging'}}
        for commands in ([cd.DeployError('secret identity error')],
                         [identity, cluster, cd.DeployError('secret kubeconfig error')]):
            with self.subTest(failure_command=len(commands)):
                with patch.object(cd, 'STATE_ROOT', self.root/'state'), patch.object(cd.Runtime, 'command', side_effect=commands):
                    with contextlib.redirect_stderr(io.StringIO()): self.assertEqual(cd.main(arguments), 1)
                rejection = json.loads((self.root/'activation.json').read_text())
                self.assertEqual(rejection['status'], 'rejected')
                self.assertEqual(rejection['preflight_stage'], 'activation')
                self.assertEqual(rejection['mutations_attempted'], 0)
                self.assertNotIn('secret', json.dumps(rejection))
                self.assertNotEqual(rejection['release_id'], good['release_id'])
                self.assertEqual({name: (directory/name).read_bytes() for name in before}, before)

    def test_ai_legacy_production_cd_must_be_skipped_in_exact_publisher_attempt(self):
        for name in ('Production CD', 'Production CD / Deploy to ECS'):
            for conclusion in ('success', 'failure', 'cancelled', None, 'skipped'):
                self.data = release('ai', 'prod'); self.approval = contract('ai', 'prod'); self.runtime = External('ai', 'prod')
                self.runtime.extra_jobs = [dict(id=900, name=name, status='completed' if conclusion else 'in_progress',
                    conclusion=conclusion, run_id=91, run_attempt=2)]
                with self.subTest(name=name, conclusion=conclusion):
                    if conclusion == 'skipped': self.assertEqual(self.deploy()['status'], 'succeeded')
                    else:
                        with self.assertRaises(cd.DeployError): self.deploy()
                        self.assertEqual(self.runtime.patched, [])

    def test_pending_cleanup_failure_keeps_committed_success_and_allows_bootstrap(self):
        original = Path.unlink
        def fail_pending(path, *args, **kwargs):
            if path.name == 'pending.json': raise OSError('simulated cleanup failure')
            return original(path, *args, **kwargs)
        with patch.object(Path, 'unlink', fail_pending):
            result = self.deploy()
            self.assertEqual(result['status'], 'succeeded')
            directory = self.root/'state/staging/ai'
            good = json.loads((directory/'last-good.json').read_text())
            current = json.loads((directory/'current.json').read_text())
            self.assertEqual(current, good)
            self.assertEqual(json.loads((self.root/'result.json').read_text()), good)
            self.assertEqual(cd.bootstrap_overrides(self.root/'state', 'ai', 'staging')['image-worker']['image.digest'], legacy.DIGEST)

    def test_preflight_rejections_preserve_all_active_state_and_emit_run_scoped_receipt(self):
        good = self.deploy()
        directory = self.root/'state/staging/ai'
        pending = directory/'pending.json'; pending.write_text('{"operator_pending":"keep"}')
        before = {name: (directory/name).read_bytes() for name in ('current.json', 'last-good.json', 'pending.json')}
        for stage in ('source_head', 'ecr', 'publisher', 'schema'):
            self.runtime = External()
            self.read.side_effect = lambda *args: copy.deepcopy(self.approval)
            if stage == 'source_head': self.runtime.source = legacy.OTHER_SHA
            elif stage == 'ecr': self.runtime.mutable = True
            elif stage == 'publisher':
                self.data = release('ai', 'prod'); self.approval = contract('ai', 'prod'); self.runtime = External('ai', 'prod')
                self.runtime.latest_override['run_attempt'] = 3
                directory = self.root/'state/prod/ai'; directory.mkdir(parents=True)
                for name, contents in before.items(): (directory/name).write_bytes(contents)
            else:
                self.data = release(); self.approval = contract()
                self.runtime = External(); self.runtime.tree['truncated'] = True
                directory = self.root/'state/staging/ai'
            with self.subTest(stage=stage), self.assertRaises(cd.DeployError): self.deploy()
            receipt = json.loads((self.root/'result.json').read_text())
            self.assertEqual(receipt['status'], 'rejected')
            self.assertEqual(receipt['preflight_stage'], stage)
            self.assertEqual(receipt['applied'], [])
            self.assertEqual(receipt['mutations_attempted'], 0)
            self.assertIn('reason_code', receipt)
            self.assertNotEqual(receipt['release_id'], good['release_id'])
            self.assertEqual(json.loads((directory/'history'/(receipt['release_id']+'.json')).read_text()), receipt)
            self.assertEqual({name: (directory/name).read_bytes() for name in before}, before)
            self.assertEqual(self.runtime.patched, [])

    def test_cli_has_fixed_profiles_and_no_state_or_cluster_override(self):
        args = cd.parse_args(['--family', 'be', '--environment', 'prod', '--check-access'])
        self.assertEqual(args.environment, 'prod')
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            cd.parse_args(['--family', 'ai', '--environment', 'prod', '--check-access', '--state-root', '/tmp/other'])
        with self.assertRaises(cd.DeployError):
            cd.request_from_release(release('ai', 'prod'), 'ai', 'prod', 'dev', legacy.SHA)

    def test_wrong_environment_values_cannot_be_patched(self):
        self.data = release('ai', 'prod')
        self.approval = contract('ai', 'prod')
        with self.assertRaises(cd.DeployError):
            self.deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_schema_gate_blocks_changed_added_removed_missing_and_unsafe_migrations_before_patch(self):
        variants = []
        changed = copy.deepcopy(self.runtime.tree); changed['tree'][0]['sha'] = '9'*40; variants.append(changed)
        added = copy.deepcopy(self.runtime.tree); added['tree'].append(dict(path='alembic/versions/new.py', sha='9'*40, type='blob', mode='100644')); variants.append(added)
        variants.append(dict(sha='f'*40, truncated=False, tree=[]))
        truncated = copy.deepcopy(self.runtime.tree); truncated['truncated'] = True; variants.append(truncated)
        symlink = copy.deepcopy(self.runtime.tree); symlink['tree'][0]['mode'] = '120000'; variants.append(symlink)
        for candidate in variants:
            self.runtime = External(); self.runtime.tree = candidate
            with self.subTest(tree=candidate), self.assertRaises(cd.DeployError): self.deploy()
            self.assertEqual(self.runtime.patched, [])
        self.read.side_effect = cd.DeployError('missing approval')
        with self.assertRaises(cd.DeployError): self.deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_schema_contract_identity_and_fingerprints_are_strict(self):
        for field, value in [('schema_version', True), ('environment', 'prod'), ('family', 'be'), ('source_repository', 'foreign/repo'), ('database_identity_sha256', ''), ('schema_revision', ''), ('verified_at_utc', 'yesterday'), ('migration_files', []), ('unknown', 2)]:
            self.approval = contract(); self.approval[field] = value
            with self.subTest(field=field), self.assertRaises(cd.DeployError): self.deploy()
            self.assertEqual(self.runtime.patched, [])

    def test_ordinary_code_change_keeps_migration_gate_open(self):
        self.runtime.tree['tree'].append(dict(path='app/new.py', sha='1'*40, type='blob', mode='100644'))
        self.assertEqual(self.deploy()['status'], 'succeeded')

    def test_partial_failure_preserves_last_good_and_blocks_bootstrap(self):
        good = self.deploy()
        self.runtime.fail_patch = 'image-worker'
        with self.assertRaises(cd.DeployError): self.deploy()
        directory = self.root/'state/staging/ai'
        receipt = json.loads((directory/'current.json').read_text())
        self.assertEqual(receipt['status'], 'partial')
        self.assertEqual(len(receipt['applied']), 2)
        self.assertEqual(json.loads((directory/'last-good.json').read_text())['release_id'], good['release_id'])
        with self.assertRaises(cd.DeployError): cd.bootstrap_overrides(self.root/'state', 'ai', 'staging')
        with self.assertRaises((cd.DeployError, OSError)): cd.bootstrap_overrides(self.root/'state', 'ai', 'prod')

    def test_source_head_race_and_mutable_or_wrong_ecr_tags_block(self):
        self.runtime.supersede_on_read = 3
        with self.assertRaises(cd.DeployError): self.deploy()
        self.assertEqual(len(self.runtime.patched), 1)
        for mode in ('mutable', 'wrong'):
            self.runtime = External()
            if mode == 'mutable': self.runtime.mutable = True
            else: self.runtime.tag_digest = legacy.OLD_DIGEST
            with self.assertRaises(cd.DeployError): self.deploy()
            self.assertEqual(self.runtime.patched, [])

    def test_real_primary_pod_repository_and_digest_are_required(self):
        for mode in ('wrong_pod_digest', 'sidecar_only', 'zero_replicas'):
            self.runtime = External(); setattr(self.runtime, mode, True)
            with self.subTest(mode=mode), self.assertRaises(cd.DeployError): self.deploy()

    def test_explicit_same_environment_rollback_returns_only_conditional_patch(self):
        good = self.deploy()
        previous = copy.deepcopy(good)
        previous.update(source_commit=legacy.OTHER_SHA, image_tag='dev-' + legacy.OTHER_SHA, digest=legacy.OLD_DIGEST)
        live = self.runtime.get_app('image-worker')
        changed = legacy.apply_json_patch(live, cd.rollback_patch(live, good, previous))
        self.assertEqual(cd.parameter_images(changed)['image.digest'], legacy.OLD_DIGEST)
        self.assertEqual(len(self.runtime.patched), 6)
        live['metadata']['uid'] = 'foreign'
        with self.assertRaises(cd.DeployError): cd.rollback_patch(live, good, previous)

    def test_prod_bootstrap_and_rollback_cannot_consume_staging_receipts(self):
        good = self.deploy()
        previous = copy.deepcopy(good); previous['environment'] = 'prod'
        with self.assertRaises(cd.DeployError): cd.rollback_patch(self.runtime.get_app('image-worker'), good, previous)

    def test_production_version_contract_matches_producers_stable_semver_only(self):
        data = release('ai', 'prod')
        data['image_tag'] = 'v1.2.3-rc.1'
        data['publisher_version']['git_release_tag'] = data['image_tag']
        with self.assertRaises(cd.DeployError):
            cd.request_from_release(data, 'ai', 'prod', 'main', legacy.SHA)
        runtime = cd.Runtime('prod')
        with patch.object(runtime, 'github', return_value=[{'name': 'v1.2.3-rc.1', 'commit': {'sha': legacy.SHA}}]):
            self.assertEqual(runtime.semantic_tags_at_commit('ai', legacy.SHA), [])

    def test_runtime_latest_workflow_uses_newest_matching_run_and_attempt(self):
        runtime = cd.Runtime('prod')
        old = External('be', 'prod').workflow_run('be', 91, 2)
        latest = dict(old, id=92, run_number=13, run_attempt=3, conclusion='failure')
        foreign = dict(old, id=99, run_number=99, head_sha=legacy.OTHER_SHA)
        with patch.object(runtime, 'github', return_value={'total_count': 3, 'workflow_runs': [old, foreign, latest]}):
            result = runtime.latest_release_workflow_run('be', legacy.SHA)
            self.assertEqual((result['id'], result['run_attempt'], result['conclusion']), (92, 3, 'failure'))
        with patch.object(runtime, 'github', return_value={'total_count': 101, 'workflow_runs': [old]}):
            with self.assertRaises(cd.DeployError): runtime.latest_release_workflow_run('be', legacy.SHA)

    def test_runtime_jobs_are_attempt_specific_and_reject_truncated_count(self):
        runtime = cd.Runtime('prod')
        job = External('ai', 'prod').workflow_attempt_jobs('ai', 91, 2)[0]
        calls = []
        def api(family, path):
            calls.append((family, path))
            return {'total_count': 1, 'jobs': [job]}
        with patch.object(runtime, 'github', side_effect=api):
            self.assertEqual(runtime.workflow_attempt_jobs('ai', 91, 2), [job])
        self.assertEqual(calls, [('ai', '/actions/runs/91/attempts/2/jobs?per_page=100&page=1')])
        with patch.object(runtime, 'github', return_value={'total_count': 2, 'jobs': [job]}):
            with self.assertRaises(cd.DeployError): runtime.workflow_attempt_jobs('ai', 91, 2)

    def test_runtime_reads_exact_commit_tree_and_rejects_wrong_or_truncated_tree(self):
        runtime = cd.Runtime('prod')
        commit_reply = {'sha': legacy.SHA, 'tree': {'sha': 'f'*40}}
        tree_reply = {'sha': 'f'*40, 'truncated': False, 'tree': []}
        calls = []
        def api(family, path):
            calls.append((family, path))
            return commit_reply if '/commits/' in path else tree_reply
        with patch.object(runtime, 'github', side_effect=api):
            self.assertEqual(runtime.source_tree('ai', legacy.SHA), tree_reply)
            self.assertEqual(calls, [('ai', '/git/commits/' + legacy.SHA), ('ai', '/git/trees/' + 'f'*40 + '?recursive=1')])
            tree_reply['sha'] = '9'*40
            with self.assertRaises(cd.DeployError): runtime.source_tree('ai', legacy.SHA)
            commit_reply['sha'] = legacy.OTHER_SHA
            with self.assertRaises(cd.DeployError): runtime.source_tree('ai', legacy.SHA)

    def test_no_release_tag_listing_rejects_duplicate_pages_and_checks_later_pages(self):
        runtime = cd.Runtime('prod')
        first = [{'name': 'nonsemantic-' + str(i), 'commit': {'sha': legacy.OTHER_SHA}} for i in range(100)]
        with patch.object(runtime, 'github', side_effect=[first, [{'name': 'v1.2.3', 'commit': {'sha': legacy.SHA}}]]):
            self.assertEqual(runtime.semantic_tags_at_commit('ai', legacy.SHA), ['v1.2.3'])
        with patch.object(runtime, 'github', side_effect=[first, first]):
            with self.assertRaises(cd.DeployError): runtime.semantic_tags_at_commit('ai', legacy.SHA)

    def test_foreign_pod_repository_with_same_digest_cannot_be_ready(self):
        original = self.runtime.list_pods
        def foreign(namespace, labels):
            pods = original(namespace, labels)
            pods[0]['status']['containerStatuses'][0]['imageID'] = 'foreign/image@' + legacy.DIGEST
            return pods
        self.runtime.list_pods = foreign
        with self.assertRaises(cd.DeployError): self.deploy()

    def test_immutable_exclusion_filter_for_version_tag_blocks_before_patch(self):
        original = self.runtime.ecr_repository
        def repository(family):
            value = original(family)
            value.update(imageTagMutability='IMMUTABLE_WITH_EXCLUSION',
                         imageTagMutabilityExclusionFilters=[{'filterType': 'WILDCARD', 'filter': 'dev-*'}])
            return value
        self.runtime.ecr_repository = repository
        with self.assertRaises(cd.DeployError): self.deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_contract_reader_rejects_symlink_writable_and_nonroot_files(self):
        self.read.stop()
        path = self.root/'contract.json'; path.write_text(json.dumps(contract()))
        with self.assertRaises(cd.DeployError): cd.read_protected_json(path)
        path.chmod(0o666)
        with self.assertRaises(cd.DeployError): cd.read_protected_json(path)
        link = self.root/'link.json'; link.symlink_to(path)
        with self.assertRaises(cd.DeployError): cd.read_protected_json(link)

    def test_json_duplicate_fields_and_optimized_python_cannot_bypass_gates(self):
        source = self.root/'release.json'; source.write_text('{"schema_version":2,"schema_version":2}')
        with self.assertRaises(cd.DeployError): cd.read_release_file(source)
        code = "import deploy_release as d; d.request_from_release({}, 'ai', 'prod', 'dev', 'a'*40)"
        done = subprocess.run([sys.executable, '-O', '-c', code], cwd=PATH.parent, capture_output=True, text=True)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn('DeployError', done.stderr)


if __name__ == '__main__': unittest.main()
