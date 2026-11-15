#!/usr/bin/env python3
"""Deploy exact verified BE/AI releases to fixed branch/environment profiles.

Install root-owned outside all source workspaces at /opt/star23-direct-cd.
Only image.tag/image.digest Application parameters are patched. Root-owned schema
approvals gate every release before patch. Multi-App writes are not atomic:
durable environment/family receipts survive partial failure; never auto rollback.
The approval is a migration-file compatibility baseline, not a fresh DB read or
proof that arbitrary application code/configuration cannot issue DDL. Future
source behavior changes still require human review. CI gets no database secrets
or Pod-exec permissions from this helper. The existing shared CI role is retained;
named-App RBAC is not field isolation.
"""

import argparse
from collections import namedtuple
from contextlib import ExitStack, contextmanager
from datetime import datetime, timezone
import fcntl
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid


ACCOUNT = "975779326240"
REGION = "ap-northeast-2"
SEMVER_TAG = r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
PROFILES = {
    "staging": {"branch": "dev", "cluster": "star-EKS-v3-staging", "values": "values/staging/"},
    "prod": {"branch": "main", "cluster": "star-EKS-v3", "values": "values/"},
}
CONTRACT_ROOT = Path("/opt/star23-direct-cd/contracts")
CLOUD = "https://github.com/100-hours-a-week/KTB4-17th-CLOUD.git"
CHART = "manifest/helm/star23-service"
APPS = {
    "be": {"auth-api": "auth", "user-api": "user", "onboarding-api": "user",
           "chat-api": "chat", "chat-socket": "chat", "recommend-api": "recommend"},
    "ai": {"onboarding-persona-ai": "user", "onboarding-face-certify-ai": "user", "image-worker": "user",
           "chat-ai-practice": "chat", "chat-ai-simulation": "chat", "chat-ai-cleanup": "chat"},
}
SOURCE_REPOS = {"be": "100-hours-a-week/KTB4-17th-BE", "ai": "100-hours-a-week/KTB4-17th-AI"}
STATE_ROOT = Path("/var/lib/jenkins/deployments")
Request = namedtuple("Request", "family environment source_branch source_commit digest image_tag timeout_seconds release", defaults=[900, None])


class DeployError(RuntimeError):
    """A failed deployment contract; no implicit recovery is performed."""


class AtomicWriteError(DeployError):
    """An atomic JSON write failed; replacement may already be visible."""

    def __init__(self, path, replaced):
        self.path = Path(path)
        self.replaced = replaced
        super().__init__("atomic JSON durability failed after replacement" if replaced else "atomic JSON write failed")


class CommitDurabilityUnknown(DeployError):
    """Success was installed; storage durability needs operator recovery."""


class TransientError(DeployError):
    """A bounded network failure that may be retried during observation."""


def image_repository(family):
    return ACCOUNT + ".dkr.ecr." + REGION + ".amazonaws.com/star23/" + family


def require(condition, message):
    if not condition:
        raise DeployError(message)


def validate_request(request):
    require(request.family in APPS, "family must be be or ai")
    require(request.environment in PROFILES and request.source_branch == PROFILES[request.environment]["branch"],
            "source branch/environment profile mismatch")
    require(not os.environ.get("CHANGE_ID") and not os.environ.get("CHANGE_FORK"), "PR/fork builds cannot deploy")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", request.source_commit)), "source commit must be a full SHA")
    require(bool(re.fullmatch(r"sha256:[0-9a-f]{64}", request.digest)), "invalid image digest")
    if request.environment == "staging":
        require(request.image_tag == "dev-" + request.source_commit, "image tag must be dev-<full source SHA>")
    else:
        require(bool(re.fullmatch(SEMVER_TAG, request.image_tag))
                or request.image_tag == "sha-" + request.source_commit, "invalid production version tag")
    require(0 < request.timeout_seconds <= 3600, "timeout must be 1..3600 seconds")


RELEASE_FIELDS = {'schema_version', 'family', 'source_repository', 'source_branch', 'environment',
                  'source_commit', 'image_tag', 'image_digest', 'source_job', 'build_number', 'run_id', 'result'}
OPTIONAL_RELEASE_FIELDS = {'image', 'publisher_version', 'release_outcome'}
PUBLISHER_FIELDS = {'workflow_run_id', 'workflow_run_attempt', 'workflow_path', 'workflow_url', 'git_release_tag'}
CONTRACT_FIELDS = {'schema_version', 'environment', 'family', 'source_repository', 'database_identity_sha256',
                   'schema_revision', 'verified_at_utc', 'migration_files'}
JSON_LIMIT = 1024 * 1024


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON field')
        result[key] = value
    return result


def read_release_file(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= JSON_LIMIT, 'unsafe release JSON file')
        with os.fdopen(descriptor, 'r', encoding='utf-8', closefd=False) as stream:
            text = stream.read(JSON_LIMIT + 1)
        require(len(text) <= JSON_LIMIT and '\x00' not in text, 'release JSON exceeds limit')
        result = json.loads(text, object_pairs_hook=unique_object)
        require(isinstance(result, dict), 'release JSON must be object')
        return result
    finally:
        os.close(descriptor)


def read_protected_json(path):
    """Open every component relative to trusted root fds, without following links."""
    path = Path(path)
    require(path.is_absolute() and '..' not in path.parts, 'contract path must be absolute')
    directory = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    descriptor = None
    try:
        for part in path.parts[1:-1]:
            next_directory = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = next_directory
            info = os.fstat(directory)
            require(info.st_uid == 0 and info.st_mode & 0o022 == 0, 'unsafe contract directory owner/mode')
        descriptor = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_mode & 0o022 == 0
                and info.st_nlink == 1 and 0 < info.st_size <= JSON_LIMIT, 'unsafe contract file owner/mode')
        with os.fdopen(descriptor, 'r', encoding='utf-8', closefd=False) as stream:
            text = stream.read(JSON_LIMIT + 1)
        require(len(text) <= JSON_LIMIT, 'schema approval exceeds size limit')
        value = json.loads(text, object_pairs_hook=unique_object)
        require(isinstance(value, dict), 'schema approval must be object')
        return value
    except (OSError, ValueError, UnicodeError):
        raise DeployError('cannot read protected schema approval') from None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(directory)


def read_schema_contract(environment, family):
    require(environment in PROFILES and family in APPS, 'invalid schema approval profile')
    return read_protected_json(CONTRACT_ROOT / (environment + '-' + family + '.json'))


def request_from_release(data, family, environment, branch, commit, timeout_seconds=900):
    require(isinstance(data, dict) and RELEASE_FIELDS <= set(data) <= RELEASE_FIELDS | OPTIONAL_RELEASE_FIELDS,
            'normalized release field set mismatch')
    require(type(data['schema_version']) is int and data['schema_version'] == 2, 'unsupported normalized release version')
    require(family in APPS and environment in PROFILES and branch == PROFILES[environment]['branch'], 'invalid deployment profile')
    number = data['build_number']
    require(type(number) is int and 0 < number <= 2147483647, 'invalid source build number')
    job = ('ci/backend/' if family == 'be' else 'ci/ai/') + branch
    expected = dict(family=family, environment=environment, source_repository=SOURCE_REPOS[family], source_branch=branch,
                    source_commit=commit, source_job=job, run_id=job + '#' + str(number), result='SUCCESS')
    require(all(data[key] == value for key, value in expected.items()), 'normalized release identity mismatch')
    require(all(isinstance(data[key], str) for key in ('image_tag', 'image_digest', 'source_commit')), 'release identity must be text')
    request = Request(family, environment, branch, commit, data['image_digest'], data['image_tag'], timeout_seconds, dict(data))
    validate_request(request)
    require(data.get('image', image_repository(family) + '@' + request.digest) == image_repository(family) + '@' + request.digest,
            'normalized image repository/digest mismatch')
    if environment == 'staging':
        require('publisher_version' not in data and 'release_outcome' not in data, 'staging cannot consume main publisher proof')
    else:
        proof = data.get('publisher_version')
        require(isinstance(proof, dict) and set(proof) == PUBLISHER_FIELDS, 'missing sanitized publisher proof')
        for field in ('workflow_run_id', 'workflow_run_attempt'):
            require(type(proof[field]) is int and 0 < proof[field] <= 2**63 - 1, 'invalid publisher Run identity')
        require(proof['workflow_path'] == '.github/workflows/release.yml', 'unexpected publisher workflow')
        url = 'https://github.com/' + SOURCE_REPOS[family] + '/actions/runs/' + str(proof['workflow_run_id'])
        require(proof['workflow_url'] == url, 'publisher Run URL mismatch')
        outcome = data.get('release_outcome')
        require(outcome in ('released', 'no-release'), 'invalid release outcome')
        if outcome == 'released':
            require(request.image_tag.startswith('v') and proof['git_release_tag'] == request.image_tag, 'released tag proof mismatch')
        else:
            require(request.image_tag == 'sha-' + commit and proof['git_release_tag'] is None, 'no-release proof mismatch')
    return request


def migration_path(family, path):
    if family == 'be':
        return path.startswith('src/main/resources/db/migration/')
    return path.startswith('alembic/versions/') and len(path.split('/')) == 3 and path.endswith('.py')


def validate_migration_path(family, path):
    return (isinstance(path, str) and not path.startswith('/') and '\\' not in path
            and all(part not in ('', '.', '..') for part in path.split('/'))
            and migration_path(family, path))


def verify_schema(runtime, request):
    approval = read_schema_contract(request.environment, request.family)
    require(isinstance(approval, dict) and set(approval) == CONTRACT_FIELDS, 'schema approval field set mismatch')
    require(type(approval['schema_version']) is int and approval['schema_version'] == 1, 'schema approval version mismatch')
    require(all(approval[key] == value for key, value in dict(environment=request.environment, family=request.family,
            source_repository=SOURCE_REPOS[request.family]).items()), 'schema approval profile mismatch')
    require(isinstance(approval['database_identity_sha256'], str) and re.fullmatch(r'[0-9a-f]{64}', approval['database_identity_sha256']),
            'missing database identity fingerprint')
    require(isinstance(approval['schema_revision'], str) and re.fullmatch(r'[0-9A-Za-z_.-]{1,128}', approval['schema_revision']),
            'invalid approved schema revision')
    verified = approval['verified_at_utc']
    require(isinstance(verified, str) and re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', verified), 'invalid schema verification timestamp')
    try:
        timestamp = datetime.strptime(verified, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        raise DeployError('invalid schema verification timestamp') from None
    require(timestamp <= datetime.now(timezone.utc), 'schema approval timestamp is in the future')
    files = approval['migration_files']
    require(isinstance(files, list) and 0 < len(files) <= 10000, 'missing migration approval manifest')
    approved = {}
    for item in files:
        require(isinstance(item, dict) and set(item) == {'path', 'blob_sha'}, 'invalid approved migration entry')
        path, sha = item['path'], item['blob_sha']
        require(validate_migration_path(request.family, path) and path not in approved, 'unsafe/duplicate approved migration path')
        require(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha), 'invalid approved migration blob SHA')
        approved[path] = sha
    tree = runtime.source_tree(request.family, request.source_commit)
    require(isinstance(tree, dict) and tree.get('truncated') is False and isinstance(tree.get('tree'), list),
            'source migration tree missing/truncated')
    require(isinstance(tree.get('sha'), str) and re.fullmatch(r'[0-9a-f]{40}', tree['sha']), 'source tree identity missing')
    candidate = {}
    seen = set()
    for item in tree['tree']:
        require(isinstance(item, dict) and isinstance(item.get('path'), str), 'malformed source tree entry')
        path = item['path']
        require(path not in seen and not path.startswith('/') and '\\' not in path
                and all(part not in ('', '.', '..') for part in path.split('/')), 'unsafe/duplicate source tree path')
        seen.add(path)
        if migration_path(request.family, path):
            if item.get('type') == 'tree' and item.get('mode') == '040000':
                continue
            require(validate_migration_path(request.family, path) and item.get('type') == 'blob' and item.get('mode') in ('100644', '100755'),
                    'migration must be a regular Git blob')
            sha = item.get('sha')
            require(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha), 'invalid source migration blob SHA')
            candidate[path] = sha
    require(candidate == approved, 'candidate migrations differ from operator-approved schema; separate schema operation required')
    return dict(status='approved_migration_files_match', fresh_database_read=False, database_identity_sha256=approval['database_identity_sha256'], schema_revision=approval['schema_revision'],
                verified_at_utc=verified, migration_files=files,
                contract_sha256=hashlib.sha256(json.dumps(approval, sort_keys=True, separators=(',', ':')).encode()).hexdigest())


def verify_publisher(runtime, request):
    if request.environment == 'staging':
        return None
    proof = request.release['publisher_version']
    expected = {'id': proof['workflow_run_id'], 'run_attempt': proof['workflow_run_attempt'], 'path': proof['workflow_path'],
                'head_sha': request.source_commit, 'head_branch': 'main', 'event': 'push', 'status': 'completed',
                'conclusion': 'success', 'html_url': proof['workflow_url']}

    def verify_run(actual):
        actual_path = actual.get('path') if isinstance(actual, dict) else None
        if request.family == 'ai' and isinstance(actual_path, str):
            actual_path = actual_path.split('@')[0]
        require(isinstance(actual, dict) and actual_path == proof['workflow_path']
                and all(actual.get(key) == value for key, value in expected.items() if key != 'path')
                and actual.get('repository', {}).get('full_name') == SOURCE_REPOS[request.family]
                and actual.get('head_repository', {}).get('full_name') == SOURCE_REPOS[request.family],
                'independent latest publisher workflow proof mismatch')

    verify_run(runtime.latest_release_workflow_run(request.family, request.source_commit))
    verify_run(runtime.workflow_run(request.family, proof['workflow_run_id'], proof['workflow_run_attempt']))
    jobs = runtime.workflow_attempt_jobs(request.family, proof['workflow_run_id'], proof['workflow_run_attempt'])
    require(isinstance(jobs, list), 'publisher attempt jobs missing')
    if request.family == 'ai':
        legacy = [job for job in jobs if isinstance(job, dict) and isinstance(job.get('name'), str)
                  and (job['name'] == 'Production CD' or job['name'].startswith('Production CD /'))]
        require(all(job.get('status') == 'completed' and job.get('conclusion') == 'skipped' for job in legacy),
                'AI legacy Production CD executed in publisher attempt; direct deployment blocked')
    semantic = [job for job in jobs if isinstance(job, dict) and job.get('name') == 'Semantic Release']
    require(len(semantic) == 1, 'publisher Semantic Release job must be unique')
    job = semantic[0]
    require(job.get('run_id') == proof['workflow_run_id'] and job.get('run_attempt') == proof['workflow_run_attempt']
            and job.get('head_sha') == request.source_commit and job.get('status') == 'completed'
            and job.get('conclusion') == 'success', 'publisher Semantic Release job did not succeed for this attempt')
    steps = job.get('steps')
    require(isinstance(steps, list), 'publisher Semantic Release steps missing')
    semantic_steps = [step for step in steps if isinstance(step, dict) and step.get('name') == 'Semantic Release']
    require(len(semantic_steps) == 1 and semantic_steps[0].get('status') == 'completed'
            and semantic_steps[0].get('conclusion') == 'success', 'publisher Semantic Release step did not succeed')
    tags = runtime.semantic_tags_at_commit(request.family, request.source_commit)
    expected_tags = [request.image_tag] if request.release['release_outcome'] == 'released' else []
    require(tags == expected_tags, 'candidate semantic release tags differ from declared release outcome')
    if expected_tags:
        require(runtime.release_tag_commit(request.family, request.image_tag) == request.source_commit,
                'release tag does not resolve to candidate commit')
    # Reject a rerun or newer failed/pending run appearing while evidence was read.
    verify_run(runtime.latest_release_workflow_run(request.family, request.source_commit))
    return dict(proof, release_outcome=request.release['release_outcome'], source_commit=request.source_commit,
                semantic_job_id=job.get('id'), semantic_step_number=semantic_steps[0].get('number'),
                semantic_release_verified=True, semantic_tags=tags)


def parameters(app):
    values = app["spec"]["source"]["helm"].get("parameters", [])
    require(isinstance(values, list), "Helm parameters must be a list")
    names = []
    for item in values:
        require(isinstance(item, dict) and isinstance(item.get("name"), str)
                and isinstance(item.get("value"), str), "malformed Helm parameter")
        names.append(item["name"])
    require(len(names) == len(set(names)), "duplicate Helm parameter names are unsafe")
    return values


def parameter_images(app):
    return {p["name"]: p["value"] for p in parameters(app) if p["name"] in ("image.tag", "image.digest")}


def validate_app(app, family, name, environment):
    require(name in APPS[family], "unexpected Application name")
    metadata, spec = app.get("metadata", {}), app.get("spec", {})
    require(metadata.get("name") == name and metadata.get("namespace") == "argocd", "Application identity mismatch")
    require(bool(metadata.get("uid")) and bool(metadata.get("resourceVersion")), "Application UID/resourceVersion missing")
    require(not metadata.get("deletionTimestamp"), "Application is being deleted")
    require(not any(ref.get("controller") for ref in metadata.get("ownerReferences", [])),
            "Application is managed by another controller")
    require(spec.get("project") == "star23-apps", "Application project mismatch")
    require(spec.get("destination") == {"namespace": APPS[family][name], "server": "https://kubernetes.default.svc"},
            "Application destination mismatch")
    require(not spec.get("sources"), "multi-source Applications are not supported")
    source = spec.get("source", {})
    require(source.get("repoURL") == CLOUD and source.get("path") == CHART
            and source.get("targetRevision") == "main" and not source.get("chart"), "Application chart/source mismatch")
    require(all(source.get(field) is None for field in ("plugin", "directory", "kustomize")),
            "Application must use only the contracted Helm renderer")
    helm = source.get("helm", {})
    require(helm.get("releaseName") == name and helm.get("valueFiles") == [PROFILES[environment]["values"] + name + ".yaml"],
            "Application environment values/release identity mismatch")
    require(not helm.get("fileParameters"), "Helm fileParameters may override image parameters")
    repository = helm.get("valuesObject", {}).get("image", {}).get("repository")
    require(repository in (None, image_repository(family)), "Application inline image repository mismatch")
    require(not any(p["name"] == "image.repository" and p["value"] != image_repository(family) for p in parameters(app)),
            "Application image.repository parameter mismatch")
    automated = spec.get("syncPolicy", {}).get("automated")
    require(isinstance(automated, dict) and automated.get("enabled") is not False, "Application automated sync is disabled")


def image_patch(app, tag, digest):
    """Upsert only image parameter values with optimistic concurrency guards."""
    current = parameters(app)
    patch = [{"op": "test", "path": "/metadata/uid", "value": app["metadata"]["uid"]},
             {"op": "test", "path": "/metadata/resourceVersion", "value": app["metadata"]["resourceVersion"]}]
    if "parameters" not in app["spec"]["source"]["helm"]:
        patch.append({"op": "add", "path": "/spec/source/helm/parameters", "value": []})
    for name, value in (("image.tag", tag), ("image.digest", digest)):
        matches = [i for i, item in enumerate(current) if item["name"] == name]
        if matches:
            index = matches[0]
            if current[index]["value"] != value:
                patch.append({"op": "replace", "path": "/spec/source/helm/parameters/" + str(index) + "/value", "value": value})
        else:
            patch.append({"op": "add", "path": "/spec/source/helm/parameters/-",
                          "value": {"name": name, "value": value, "forceString": True}})
    return patch


def require_latest(runtime, request):
    require(runtime.source_head(request.family, request.source_branch) == request.source_commit, "source HEAD advanced; refusing superseded build")


def verify_ecr(runtime, request):
    repository = runtime.ecr_repository(request.family)
    require(repository.get("registryId") == ACCOUNT and repository.get("repositoryName") == "star23/" + request.family
            and repository.get("repositoryUri") == image_repository(request.family), "ECR repository/account mismatch")
    mode = repository.get("imageTagMutability")
    filters = repository.get("imageTagMutabilityExclusionFilters", [])
    require(all(item.get("filterType") == "WILDCARD" and isinstance(item.get("filter"), str) for item in filters),
            "unknown ECR immutability filter")
    for tag in (request.source_commit, request.image_tag):
        excluded = any(fnmatch.fnmatchcase(tag, item["filter"]) for item in filters)
        immutable = mode == "IMMUTABLE" or mode == "IMMUTABLE_WITH_EXCLUSION" and not excluded
        immutable = immutable or mode == "MUTABLE_WITH_EXCLUSION" and excluded
        require(immutable, "both source/version ECR tags must be immutable")
        require(runtime.ecr_tag_digest(request.family, tag) == request.digest, "ECR tag differs from validated digest")
    manifest_text = runtime.image_manifest(request.family, request.digest)
    require("sha256:" + hashlib.sha256(manifest_text.encode()).hexdigest() == request.digest, "ECR manifest digest mismatch")
    manifest = json.loads(manifest_text)
    allowed = {request.digest}
    if "manifests" in manifest:
        children = [item.get("digest") for item in manifest["manifests"]
                    if item.get("platform", {}).get("os") == "linux"
                    and item.get("platform", {}).get("architecture") == "amd64"]
        require(children and all(isinstance(d, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", d) for d in children),
                "image index has no validated linux/amd64 manifest")
        allowed.update(children)
    return allowed


def rollout_ready(app, deployment, pods, request, name, allowed_digests):
    """Require fresh Argo comparison, complete generation, and actual primary image."""
    status = app.get("status", {})
    sync = status.get("sync", {})
    compared = sync.get("comparedTo", {})
    revision = sync.get("revision", "")
    if (app.get("operation") is not None
            or status.get("operationState", {}).get("phase") not in (None, "Succeeded")
            or not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision)
            or sync.get("status") != "Synced" or status.get("health", {}).get("status") != "Healthy"
            or compared.get("source") != app["spec"]["source"]
            or compared.get("destination") != app["spec"]["destination"]):
        return False
    metadata, spec, state = deployment.get("metadata", {}), deployment.get("spec", {}), deployment.get("status", {})
    require(metadata.get("name") == name and metadata.get("namespace") == APPS[request.family][name],
            "Deployment identity mismatch")
    desired = spec.get("replicas", 1)
    if not isinstance(desired, int) or desired < 1:
        return False
    if (state.get("observedGeneration", 0) < metadata.get("generation", 1)
            or any(state.get(key, 0) != desired for key in ("replicas", "updatedReplicas", "readyReplicas", "availableReplicas"))
            or state.get("unavailableReplicas", 0) != 0):
        return False
    image = image_repository(request.family) + "@" + request.digest
    containers = spec.get("template", {}).get("spec", {}).get("containers", [])
    if len([c for c in containers if c.get("name") == name and c.get("image") == image]) != 1:
        return False
    selector = spec.get("selector", {}).get("matchLabels", {})
    require(selector and not spec.get("selector", {}).get("matchExpressions"), "Deployment selector is unsupported")
    active = [pod for pod in pods if not pod.get("metadata", {}).get("deletionTimestamp")]
    if len(active) != desired:
        return False
    for pod in active:
        pmeta, pstatus = pod.get("metadata", {}), pod.get("status", {})
        if (pmeta.get("namespace") != APPS[request.family][name]
                or any(pmeta.get("labels", {}).get(key) != value for key, value in selector.items())
                or pstatus.get("phase") != "Running"
                or not any(c.get("type") == "Ready" and c.get("status") == "True" for c in pstatus.get("conditions", []))):
            return False
        primary = [c for c in pod.get("spec", {}).get("containers", []) if c.get("name") == name]
        actual = [c for c in pstatus.get("containerStatuses", []) if c.get("name") == name]
        if len(primary) != 1 or primary[0].get("image") != image or len(actual) != 1 or actual[0].get("ready") is not True:
            return False
        image_id = actual[0].get("imageID", "").removeprefix("docker-pullable://")
        # A digest suffix alone from a foreign repository is not accepted.
        if image_id not in {image_repository(request.family) + "@" + digest for digest in allowed_digests}:
            return False
    return True


def atomic_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    replaced = False
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        replaced = True
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except OSError:
        raise AtomicWriteError(path, replaced) from None
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextmanager
def deployment_lock(state_root, family):
    directory = Path(state_root) / family
    directory.mkdir(parents=True, exist_ok=True, mode=0o750)
    with (directory / ".lock").open("a+") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise DeployError("another deployment holds the family lock") from None
        try:
            yield directory
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def persist(directory, receipt, output_file):
    atomic_json(directory / "history" / (receipt["release_id"] + ".json"), receipt)
    atomic_json(directory / "current.json", receipt)
    atomic_json(directory / "pending.json", receipt)
    atomic_json(output_file, receipt)


def deploy(request, runtime, state_root, output_file, *, clock=time.monotonic, sleep=time.sleep):
    validate_request(request)
    with deployment_lock(Path(state_root) / request.environment, request.family) as directory, ExitStack() as lifecycle:
        receipt = {"release_id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex,
                   "status": "preflight", "atomic": False, "family": request.family, "environment": request.environment,
                   "cluster": PROFILES[request.environment]["cluster"],
                   "source_repository": SOURCE_REPOS[request.family], "source_branch": request.source_branch,
                   "source_commit": request.source_commit, "digest": request.digest, "image_tag": request.image_tag,
                   "image": image_repository(request.family) + "@" + request.digest,
                   "schema_approval": None, "publisher_proof": None,
                   "image_digest": request.digest, "source_job": request.release["source_job"],
                   "build_number": request.release["build_number"], "run_id": request.release["run_id"],
                   "jenkins_build_url": os.environ.get("BUILD_URL", ""), "apps": {}, "applied": [], "ready": [], "mutations_attempted": 0}
        stage = 'activation'
        try:
            runtime = lifecycle.enter_context(runtime)
            stage = 'identity'
            runtime.verify_identity()
            stage = 'source_head'
            require_latest(runtime, request)
            stage = 'ecr'
            allowed = verify_ecr(runtime, request)
            stage = 'publisher'
            receipt['publisher_proof'] = verify_publisher(runtime, request)
            stage = 'schema'
            receipt['schema_approval'] = verify_schema(runtime, request)
            stage = 'applications'
            initial = {}
            for name in APPS[request.family]:
                app = runtime.get_app(name)
                validate_app(app, request.family, name, request.environment)
                initial[name] = {"uid": app["metadata"]["uid"], "before_images": parameter_images(app)}
        except BaseException as failure:
            # A rejection is an audit event for this Run, never a new desired state.
            # Do not echo external errors, artifacts, credentials or candidate text.
            receipt.update(status='rejected', preflight_stage=stage, reason_code='preflight_' + stage + '_rejected')
            atomic_json(directory / 'history' / (receipt['release_id'] + '.json'), receipt)
            atomic_json(output_file, receipt)
            if isinstance(failure, (KeyboardInterrupt, SystemExit)):
                raise
            raise DeployError(receipt['reason_code']) from None
        receipt.update(status='pending', apps=initial)
        persist(directory, receipt, output_file)
        attempted = False
        committed = False
        commit_uncertain = False
        try:
            for name in APPS[request.family]:
                app = runtime.get_app(name)
                validate_app(app, request.family, name, request.environment)
                require(app["metadata"]["uid"] == initial[name]["uid"], "Application was recreated before patch")
                require(parameter_images(app) == initial[name]["before_images"],
                        "desired image changed after preflight; refusing to overwrite another release")
                patch = image_patch(app, request.image_tag, request.digest)
                receipt["attempting"] = name
                persist(directory, receipt, output_file)
                # This is deliberately the final external read before EACH patch, under the lock.
                require_latest(runtime, request)
                attempted = True
                receipt["mutations_attempted"] += 1
                patched = runtime.patch_app(name, patch)
                require(patched["metadata"]["uid"] == initial[name]["uid"], "patched Application UID changed")
                require(parameter_images(patched) == {"image.tag": request.image_tag, "image.digest": request.digest},
                        "Application patch result differs from desired image")
                receipt["applied"].append(name)
                persist(directory, receipt, output_file)
            deadline = clock() + request.timeout_seconds
            while True:
                ready = []
                snapshots = {}
                for name, namespace in APPS[request.family].items():
                    if clock() >= deadline:
                        break
                    try:
                        app = runtime.get_app(name)
                        validate_app(app, request.family, name, request.environment)
                        require(app["metadata"]["uid"] == initial[name]["uid"], "Application was recreated during rollout")
                        require(parameter_images(app) == {"image.tag": request.image_tag, "image.digest": request.digest},
                                "desired image changed during rollout; refusing to overwrite a newer release")
                        deployment = runtime.get_deployment(namespace, name)
                        selector = deployment.get("spec", {}).get("selector", {}).get("matchLabels", {})
                        require(selector, "Deployment selector missing")
                        pods = runtime.list_pods(namespace, selector)
                        if rollout_ready(app, deployment, pods, request, name, allowed):
                            ready.append(name)
                            snapshots[name] = app
                            receipt["apps"][name]["chart_revision"] = app["status"]["sync"]["revision"]
                    except TransientError:
                        continue
                receipt["ready"] = ready
                persist(directory, receipt, output_file)
                if len(ready) == len(APPS[request.family]):
                    # A group scan is sequential. Recheck earlier Apps and real
                    # workloads before publishing last-good; this still cannot
                    # make independent Kubernetes writes globally atomic.
                    for name, namespace in APPS[request.family].items():
                        require(clock() < deadline, "timed out during final deployment barrier")
                        app = runtime.get_app(name)
                        validate_app(app, request.family, name, request.environment)
                        require(app["metadata"]["uid"] == initial[name]["uid"],
                                "Application was recreated during final barrier")
                        require(parameter_images(app) == {"image.tag": request.image_tag, "image.digest": request.digest},
                                "desired image changed during final barrier")
                        observed = snapshots[name]
                        require(app["spec"]["source"] == observed["spec"]["source"]
                                and app.get("status", {}).get("sync", {}).get("comparedTo")
                                == observed["status"]["sync"]["comparedTo"]
                                and app.get("status", {}).get("sync", {}).get("revision")
                                == observed["status"]["sync"]["revision"],
                                "Application source/reconciliation changed during final barrier")
                        deployment = runtime.get_deployment(namespace, name)
                        selector = deployment.get("spec", {}).get("selector", {}).get("matchLabels", {})
                        require(selector, "Deployment selector missing during final barrier")
                        pods = runtime.list_pods(namespace, selector)
                        require(rollout_ready(app, deployment, pods, request, name, allowed),
                                "Application/workload changed during final barrier")
                    require_latest(runtime, request)
                    receipt["status"] = "succeeded"
                    receipt.pop("attempting", None)
                    persist(directory, receipt, output_file)
                    # Replacement installs a visible success record. Directory
                    # fsync confirms its crash durability. If fsync fails after
                    # replacement, never rewrite that success as a partial release.
                    try:
                        atomic_json(directory / "last-good.json", receipt)
                    except AtomicWriteError as failure:
                        if not failure.replaced:
                            raise
                        committed = True
                        commit_uncertain = True
                        try:
                            matches = json.loads((directory / "last-good.json").read_text()) == receipt
                        except (OSError, ValueError):
                            matches = None
                        observation = dict(status='commit-durability-unknown', release_id=receipt['release_id'],
                                           family=request.family, environment=request.environment,
                                           run_id=receipt['run_id'], last_good_replaced=True,
                                           last_good_matches=matches, reason_code='last_good_directory_fsync_failed')
                        atomic_json(directory / 'history' / (receipt['release_id'] + '.commit.json'), observation)
                        atomic_json(Path(output_file).with_suffix('.commit.json'), observation)
                        raise CommitDurabilityUnknown('success record replaced; storage durability is unknown') from None
                    committed = True
                    (directory / "pending.json").unlink()
                    return receipt
                remaining = deadline - clock()
                require(remaining > 0, "timed out waiting for fresh Argo comparison and actual ready image digests")
                sleep(min(5, remaining))
        except BaseException as failure:
            if committed:
                if commit_uncertain:
                    raise CommitDurabilityUnknown('success record replaced; storage durability is unknown') from None
                if isinstance(failure, (KeyboardInterrupt, SystemExit)):
                    raise
                return receipt
            receipt["status"] = "partial" if attempted else "failed"
            receipt["error"] = str(failure) if isinstance(failure, DeployError) else type(failure).__name__
            persist(directory, receipt, output_file)
            if isinstance(failure, (KeyboardInterrupt, SystemExit)):
                raise
            raise DeployError(receipt["error"]) from None


def validate_good_receipt(receipt, family, environment):
    require(receipt.get("status") == "succeeded" and receipt.get("family") == family
            and receipt.get("environment") == environment and receipt.get("cluster") == PROFILES[environment]["cluster"] and receipt.get("source_repository") == SOURCE_REPOS[family],
            "receipt is not a successful release for this family/cluster")
    validate_request(Request(family, environment, receipt.get("source_branch", ""), receipt.get("source_commit", ""),
                             receipt.get("digest", ""), receipt.get("image_tag", ""), 900))
    require(set(receipt.get("ready", [])) == set(APPS[family]) and set(receipt.get("applied", [])) == set(APPS[family]),
            "receipt does not prove a complete Application group")


def bootstrap_overrides(state_root, family, environment):
    require(family in APPS and environment in PROFILES, "invalid family/environment")
    with deployment_lock(Path(state_root) / environment, family) as directory:
        current = json.loads((directory / "current.json").read_text())
        good = json.loads((directory / "last-good.json").read_text())
        validate_good_receipt(good, family, environment)
        pending_path = directory / "pending.json"
        pending = json.loads(pending_path.read_text()) if pending_path.exists() else None
        require(current == good and (pending is None or pending == good), "incomplete/newer desired release blocks stale bootstrap restoration")
        return {name: {"image.tag": good["image_tag"], "image.digest": good["digest"]} for name in APPS[family]}


def rollback_patch(live_app, current_receipt, previous_good):
    """Prepare, never execute, a deliberately requested conditional rollback."""
    family = current_receipt.get("family")
    environment = current_receipt.get("environment")
    require(environment in PROFILES, "invalid rollback environment")
    require(family in APPS, "invalid rollback family")
    validate_good_receipt(previous_good, family, environment)
    name = live_app.get("metadata", {}).get("name")
    validate_app(live_app, family, name, environment)
    require(current_receipt.get("environment") == environment and current_receipt.get("cluster") == PROFILES[environment]["cluster"] and current_receipt.get("apps", {}).get(name, {}).get("uid")
            == live_app["metadata"]["uid"], "Application was recreated; rollback requires new review")
    require(parameter_images(live_app) == {"image.tag": current_receipt.get("image_tag"),
                                          "image.digest": current_receipt.get("digest")},
            "another release owns this Application; refusing stale rollback")
    return image_patch(live_app, previous_good["image_tag"], previous_good["digest"])


def check_access(family, environment, runtime):
    runtime.verify_identity()
    for name, namespace in APPS[family].items():
        for verb in ("get", "patch"):
            require(runtime.can_i(verb, "applications.argoproj.io/" + name, "argocd"), "named Application access denied")
        require(runtime.can_i("get", "deployments.apps/" + name, namespace), "named Deployment read denied")
        require(runtime.can_i("list", "pods", namespace), "Pod observation access denied")
        app = runtime.get_app(name)
        validate_app(app, family, name, environment)
        # Admission/RBAC check only. Server dry-run never changes Application state.
        runtime.patch_app(name, image_patch(app, parameter_images(app).get("image.tag", ""),
                                          parameter_images(app).get("image.digest", ""))[:2], dry_run=True)
    return {"status": "access-verified", "family": family, "environment": environment, "cluster": PROFILES[environment]["cluster"]}


class Runtime:
    """External AWS CLI, kubectl and GitHub boundary; no source SDK required."""

    def __init__(self, environment):
        require(environment in PROFILES, "invalid runtime environment")
        self.environment = environment
        self.cluster = PROFILES[environment]["cluster"]
        self.cluster_arn = "arn:aws:eks:" + REGION + ":" + ACCOUNT + ":cluster/" + self.cluster
        self.directory = None
        self.kubeconfig = None
        self.kubectl = os.environ.get("KUBECTL", "kubectl")

    def __enter__(self):
        self.directory = tempfile.TemporaryDirectory(prefix="star23-direct-")
        self.kubeconfig = str(Path(self.directory.name) / "kubeconfig")
        try:
            self.verify_identity()
            self.command(["aws", "eks", "update-kubeconfig", "--name", self.cluster, "--region", REGION,
                          "--kubeconfig", self.kubeconfig, "--alias", self.cluster], json_output=False)
            config = self.kube(["config", "view", "--minify", "-o", "json"])
            endpoint = self.command(["aws", "eks", "describe-cluster", "--name", self.cluster, "--region", REGION,
                                     "--output", "json"])["cluster"]["endpoint"]
            require(len(config.get("clusters", [])) == 1 and config["clusters"][0]["cluster"]["server"] == endpoint,
                    "generated kubeconfig does not target contracted cluster")
            return self
        except BaseException:
            self.directory.cleanup()
            raise

    def __exit__(self, *unused):
        self.directory.cleanup()

    def command(self, command, *, json_output=True):
        environment = os.environ.copy()
        environment.update(AWS_PAGER="", AWS_DEFAULT_REGION=REGION)
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=50, env=environment)
        except (OSError, subprocess.SubprocessError):
            raise TransientError("external command could not complete") from None
        if result.returncode:
            if any(marker in result.stderr.lower() for marker in ("i/o timeout", "connection refused", "unable to connect", "context deadline")):
                raise TransientError("Kubernetes network query failed")
            # Never echo arbitrary subprocess output (which can include credentials/config).
            raise DeployError("external command failed: " + Path(command[0]).name + " " + command[1])
        try:
            return json.loads(result.stdout) if json_output else result.stdout.strip()
        except ValueError:
            raise DeployError("external command returned invalid JSON") from None

    def kube(self, args):
        require(self.kubeconfig is not None, "deployment kubeconfig is not initialized")
        return self.command([self.kubectl, "--kubeconfig", self.kubeconfig, "--context", self.cluster,
                             "--request-timeout=20s"] + args)

    def verify_identity(self):
        identity = self.command(["aws", "sts", "get-caller-identity", "--region", REGION, "--output", "json"])
        require(identity.get("Account") == ACCOUNT and identity.get("Arn", "").startswith(
            "arn:aws:sts::" + ACCOUNT + ":assumed-role/star23-ci-controller/"), "unexpected CI AWS identity")
        cluster = self.command(["aws", "eks", "describe-cluster", "--name", self.cluster, "--region", REGION, "--output", "json"])["cluster"]
        require(cluster.get("name") == self.cluster and cluster.get("arn") == self.cluster_arn and cluster.get("status") == "ACTIVE",
                "unexpected contracted EKS identity/status")

    def github(self, family, path):
        token = os.environ.get("SOURCE_TOKEN") or os.environ.get("SOURCE_GITHUB_TOKEN")
        require(bool(token), "source read token is required")
        request = urllib.request.Request("https://api.github.com/repos/" + SOURCE_REPOS[family] + path,
                                         headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                                                  "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "star23-direct-cd"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.load(response, object_pairs_hook=unique_object)
        except (OSError, ValueError, urllib.error.HTTPError):
            raise DeployError("could not verify source GitHub evidence") from None
        require(isinstance(payload, (dict, list)), "unexpected source API response")
        return payload

    def source_head(self, family, branch):
        require(branch == PROFILES[self.environment]["branch"], "runtime source branch mismatch")
        payload = self.github(family, "/git/ref/heads/" + branch)
        require(payload.get("ref") == "refs/heads/" + branch and payload.get("object", {}).get("type") == "commit",
                "unexpected source ref response")
        return payload["object"].get("sha")

    def source_tree(self, family, commit):
        payload = self.github(family, "/git/commits/" + commit)
        tree = payload.get("tree", {}).get("sha")
        require(payload.get("sha") == commit and isinstance(tree, str) and re.fullmatch(r"[0-9a-f]{40}", tree),
                "source commit/tree identity mismatch")
        result = self.github(family, "/git/trees/" + tree + "?recursive=1")
        require(result.get("sha") == tree, "source recursive tree identity mismatch")
        return result

    def semantic_tags_at_commit(self, family, commit):
        matches = []
        seen = set()
        for page in range(1, 101):
            payload = self.github(family, "/tags?per_page=100&page=" + str(page))
            require(isinstance(payload, list) and len(payload) <= 100, "invalid GitHub tag page")
            for item in payload:
                require(isinstance(item, dict) and isinstance(item.get("name"), str)
                        and item["name"] not in seen and isinstance(item.get("commit", {}).get("sha"), str)
                        and re.fullmatch(r"[0-9a-f]{40}", item["commit"]["sha"]), "invalid/duplicate GitHub tag entry")
                seen.add(item["name"])
                if re.fullmatch(SEMVER_TAG, item["name"]) and item["commit"]["sha"] == commit:
                    matches.append(item["name"])
            if len(payload) < 100:
                return matches
        raise DeployError("GitHub tag pagination exceeds safe limit")

    def github_collection(self, family, path, key):
        """Read complete bounded Actions pages; never infer absence from truncation."""
        result = []
        seen = set()
        expected_count = None
        separator = '&' if '?' in path else '?'
        for page in range(1, 11):
            payload = self.github(family, path + separator + 'per_page=100&page=' + str(page))
            require(isinstance(payload, dict) and type(payload.get('total_count')) is int
                    and 0 <= payload['total_count'] <= 1000 and isinstance(payload.get(key), list)
                    and len(payload[key]) <= 100, 'invalid or excessive Actions collection')
            if expected_count is None:
                expected_count = payload['total_count']
            require(payload['total_count'] == expected_count, 'Actions collection changed while paging')
            for item in payload[key]:
                require(isinstance(item, dict) and type(item.get('id')) is int and item['id'] > 0
                        and item['id'] not in seen, 'invalid/duplicate Actions collection entry')
                seen.add(item['id'])
                result.append(item)
            require(len(result) <= expected_count, 'Actions collection exceeds declared count')
            if len(result) == expected_count:
                return result
            require(len(payload[key]) == 100, 'Actions collection was truncated')
        raise DeployError('Actions collection exceeds safe pagination limit')

    def latest_release_workflow_run(self, family, commit):
        path = '/actions/workflows/release.yml/runs?event=push&branch=main&head_sha=' + commit
        candidates = []
        for run in self.github_collection(family, path, 'workflow_runs'):
            run_path = run.get('path')
            if family == 'ai' and isinstance(run_path, str):
                run_path = run_path.split('@')[0]
            if (run.get('head_sha') == commit and run.get('head_branch') == 'main' and run.get('event') == 'push'
                    and run_path == '.github/workflows/release.yml'
                    and run.get('repository', {}).get('full_name') == SOURCE_REPOS[family]
                    and run.get('head_repository', {}).get('full_name') == SOURCE_REPOS[family]):
                require(type(run.get('run_attempt')) is int and run['run_attempt'] > 0
                        and type(run.get('run_number')) is int and run['run_number'] > 0,
                        'invalid publisher run sequence/attempt')
                candidates.append(run)
        require(bool(candidates), 'no matching source release workflow run')
        if family == 'ai':
            return max(candidates, key=lambda run: (run['run_number'], run['run_attempt'], run['id']))
        return max(candidates, key=lambda run: (run['id'], run['run_attempt']))

    def workflow_attempt_jobs(self, family, run_id, attempt):
        path = '/actions/runs/' + str(run_id) + '/attempts/' + str(attempt) + '/jobs'
        return self.github_collection(family, path, 'jobs')

    def workflow_run(self, family, run_id, attempt):
        return self.github(family, "/actions/runs/" + str(run_id) + "/attempts/" + str(attempt))

    def release_tag_commit(self, family, tag):
        payload = self.github(family, "/git/ref/tags/" + tag)
        require(payload.get("ref") == "refs/tags/" + tag, "release tag identity mismatch")
        obj = payload.get("object", {})
        for unused in range(4):
            require(isinstance(obj.get("sha"), str) and re.fullmatch(r"[0-9a-f]{40}", obj["sha"]), "invalid release tag object")
            if obj.get("type") == "commit":
                return obj["sha"]
            require(obj.get("type") == "tag", "release tag is not a commit/tag")
            item = self.github(family, "/git/tags/" + obj["sha"])
            require(item.get("sha") == obj["sha"], "annotated release tag identity mismatch")
            obj = item.get("object", {})
        raise DeployError("release tag chain exceeds limit")

    def ecr(self, operation, family, *options):
        return self.command(["aws", "ecr", operation, "--region", REGION, "--registry-id", ACCOUNT,
                             "--repository-name", "star23/" + family, "--output", "json"] + list(options))

    def ecr_repository(self, family):
        payload = self.command(["aws", "ecr", "describe-repositories", "--region", REGION, "--registry-id", ACCOUNT,
                                "--repository-names", "star23/" + family, "--output", "json"])
        require(len(payload.get("repositories", [])) == 1, "ECR repository lookup ambiguous")
        return payload["repositories"][0]

    def ecr_tag_digest(self, family, tag):
        payload = self.ecr("describe-images", family, "--image-ids", "imageTag=" + tag)
        details = payload.get("imageDetails", [])
        require(len(details) == 1 and details[0].get("registryId") == ACCOUNT
                and details[0].get("repositoryName") == "star23/" + family, "ECR image lookup identity mismatch")
        return details[0].get("imageDigest")

    def image_manifest(self, family, digest):
        payload = self.ecr("batch-get-image", family, "--image-ids", "imageDigest=" + digest)
        images = payload.get("images", [])
        # ECR can repeat the same stored manifest once per tag when queried by
        # digest. Accept duplicates only if their digest and exact bytes agree.
        require(not payload.get("failures") and isinstance(images, list) and bool(images)
                and all(isinstance(item, dict) and item.get("imageId", {}).get("imageDigest") == digest for item in images),
                "ECR manifest lookup mismatch")
        manifest = images[0].get("imageManifest")
        require(isinstance(manifest, str) and bool(manifest)
                and all(item.get("imageManifest") == manifest for item in images), "ECR manifest response is ambiguous")
        return manifest

    def get_app(self, name):
        return self.kube(["-n", "argocd", "get", "application", name, "-o", "json"])

    def patch_app(self, name, patch, dry_run=False):
        args = ["-n", "argocd", "patch", "application", name, "--type=json", "-p", json.dumps(patch), "-o", "json"]
        if dry_run:
            args.append("--dry-run=server")
        return self.kube(args)

    def get_deployment(self, namespace, name):
        return self.kube(["-n", namespace, "get", "deployment", name, "-o", "json"])

    def list_pods(self, namespace, labels):
        selector = ",".join(key + "=" + value for key, value in sorted(labels.items()))
        return self.kube(["-n", namespace, "get", "pods", "-l", selector, "-o", "json"])["items"]

    def can_i(self, verb, resource, namespace):
        answer = self.command([self.kubectl, "--kubeconfig", self.kubeconfig, "--context", self.cluster,
                               "--request-timeout=20s", "auth", "can-i", verb, resource, "-n", namespace], json_output=False)
        return answer == "yes"


def parse_args(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--family", choices=("be", "ai"), required=True)
    parser.add_argument("--environment", choices=tuple(PROFILES), required=True)
    parser.add_argument("--source-branch", choices=("dev", "main"))
    parser.add_argument("--source-commit")
    parser.add_argument("--release-file", type=Path)
    parser.add_argument("--output-file", type=Path)
    parser.add_argument("--timeout-seconds", type=int, default=900)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--execute", action="store_true")
    mode.add_argument("--check-access", action="store_true")
    args = parser.parse_args(arguments)
    if args.execute and any(getattr(args, name) is None for name in (
            "source_branch", "source_commit", "release_file", "output_file")):
        parser.error("--execute requires source branch/commit, release file and output file")
    return args


def main(arguments=None):
    args = parse_args(arguments)
    try:
        if args.check_access:
            with Runtime(args.environment) as runtime:
                result = check_access(args.family, args.environment, runtime)
            if args.output_file:
                atomic_json(args.output_file, result)
        else:
            data = read_release_file(args.release_file)
            request = request_from_release(data, args.family, args.environment, args.source_branch,
                                           args.source_commit, args.timeout_seconds)
            result = deploy(request, Runtime(args.environment), STATE_ROOT, args.output_file)
        print(json.dumps({"status": result["status"], "family": args.family,
                          "environment": args.environment, "cluster": PROFILES[args.environment]["cluster"]}))
        return 0
    except CommitDurabilityUnknown:
        print("Deployment success record was replaced; storage durability is unknown. Inspect the commit observation receipt.", file=sys.stderr)
        return 1
    except (DeployError, OSError, ValueError, KeyError, TypeError, UnicodeError):
        # Never include hostile source/artifact data or arbitrary external output.
        print("Direct deployment failed; inspect protected deployment receipt.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
