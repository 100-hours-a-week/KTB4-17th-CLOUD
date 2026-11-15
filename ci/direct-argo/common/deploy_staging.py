#!/usr/bin/env python3
"""Deploy trusted, already-validated dev artifacts to the fixed staging cluster.

Install this helper outside source workspaces, e.g. /opt/star23-staging-cd.
The caller must verify the exact upstream Jenkins run and its artifacts. This
helper independently verifies source HEAD and immutable ECR identities. It does
not execute source code, write GitHub/CLOUD, or touch production.

The existing CI instance-role trust model is retained. Protecting this file is
not credential isolation: source CI using the same instance role has that role's
permissions. Kubernetes named-Application RBAC is NOT field-level enforcement;
this program voluntarily changes only image.tag/image.digest parameters.

Multi-Application deployment is not atomic. pending/history/current receipts
survive workspace deletion; only a completely observed group becomes last-good.
Never automatically undo a partial deployment: a newer release may own an App.

Recovery: bootstrap_overrides(state_root, family) returns image overrides for
Application manifests BEFORE creation/auto-sync. It refuses an incomplete current
release; do not recreate Apps and subsequently restore stale values. An explicit
operator rollback can use rollback_patch(live_app, current_receipt, previous_good)
under the same family lock, after verifying the old ECR digest and current dev
HEAD. That function refuses recreated Apps or changed desired images and emits
conditional JSON patches only. Apply each patch explicitly, observe the entire
group using the same rollout checks, and record a new release; do not overwrite
last-good merely because patching succeeded. A dev revert followed by normal CI
is the preferred rollback when application/schema compatibility permits it.
"""

import argparse
from collections import namedtuple
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid


ACCOUNT = "975779326240"
REGION = "ap-northeast-2"
CLUSTER = "star-EKS-v3-staging"
CLUSTER_ARN = "arn:aws:eks:ap-northeast-2:975779326240:cluster/star-EKS-v3-staging"
CLOUD = "https://github.com/100-hours-a-week/KTB4-17th-CLOUD.git"
CHART = "manifest/helm/star23-service"
APPS = {
    "be": {"auth-api": "auth", "user-api": "user", "onboarding-api": "user",
           "chat-api": "chat", "chat-socket": "chat", "recommend-api": "recommend"},
    "ai": {"onboarding-persona-ai": "user", "onboarding-face-certify-ai": "user", "image-worker": "user",
           "chat-ai-practice": "chat", "chat-ai-simulation": "chat", "chat-ai-cleanup": "chat"},
}
SOURCE_REPOS = {"be": "100-hours-a-week/KTB4-17th-BE", "ai": "100-hours-a-week/KTB4-17th-AI"}
STATE_ROOT = Path("/var/lib/jenkins/deployments/staging")
Request = namedtuple("Request", "family source_branch source_commit digest image_tag timeout_seconds", defaults=[900])


class DeployError(RuntimeError):
    """A failed deployment contract; no implicit recovery is performed."""


class TransientError(DeployError):
    """A bounded network failure that may be retried during observation."""


def image_repository(family):
    return ACCOUNT + ".dkr.ecr." + REGION + ".amazonaws.com/star23/" + family


def require(condition, message):
    if not condition:
        raise DeployError(message)


def validate_request(request):
    require(request.family in APPS, "family must be be or ai")
    require(request.source_branch == "dev", "only the original dev branch can deploy")
    require(not os.environ.get("CHANGE_ID") and not os.environ.get("CHANGE_FORK"), "PR/fork builds cannot deploy")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", request.source_commit)), "source commit must be a full SHA")
    require(bool(re.fullmatch(r"sha256:[0-9a-f]{64}", request.digest)), "invalid image digest")
    require(request.image_tag == "dev-" + request.source_commit, "image tag must be dev-<full source SHA>")
    require(0 < request.timeout_seconds <= 3600, "timeout must be 1..3600 seconds")


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


def validate_app(app, family, name):
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
    require(helm.get("releaseName") == name and helm.get("valueFiles") == ["values/staging/" + name + ".yaml"],
            "Application staging values/release identity mismatch")
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
    require(runtime.source_head(request.family) == request.source_commit, "source dev HEAD advanced; refusing superseded build")


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
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
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
    with deployment_lock(state_root, request.family) as directory:
        runtime.verify_identity()
        require_latest(runtime, request)
        allowed = verify_ecr(runtime, request)
        initial = {}
        for name in APPS[request.family]:
            app = runtime.get_app(name)
            validate_app(app, request.family, name)
            initial[name] = {"uid": app["metadata"]["uid"], "before_images": parameter_images(app)}
        receipt = {"release_id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex,
                   "status": "pending", "atomic": False, "family": request.family, "cluster": CLUSTER,
                   "source_repository": SOURCE_REPOS[request.family], "source_branch": "dev",
                   "source_commit": request.source_commit, "digest": request.digest, "image_tag": request.image_tag,
                   "image": image_repository(request.family) + "@" + request.digest,
                   "jenkins_build_url": os.environ.get("BUILD_URL", ""), "apps": initial, "applied": [], "ready": []}
        persist(directory, receipt, output_file)
        attempted = False
        try:
            for name in APPS[request.family]:
                app = runtime.get_app(name)
                validate_app(app, request.family, name)
                require(app["metadata"]["uid"] == initial[name]["uid"], "Application was recreated before patch")
                require(parameter_images(app) == initial[name]["before_images"],
                        "desired image changed after preflight; refusing to overwrite another release")
                patch = image_patch(app, request.image_tag, request.digest)
                receipt["attempting"] = name
                persist(directory, receipt, output_file)
                # This is deliberately the final external read before EACH patch, under the lock.
                require_latest(runtime, request)
                attempted = True
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
                        validate_app(app, request.family, name)
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
                        validate_app(app, request.family, name)
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
                    atomic_json(directory / "last-good.json", receipt)
                    (directory / "pending.json").unlink()
                    return receipt
                remaining = deadline - clock()
                require(remaining > 0, "timed out waiting for fresh Argo comparison and actual ready image digests")
                sleep(min(5, remaining))
        except BaseException as failure:
            receipt["status"] = "partial" if attempted else "failed"
            receipt["error"] = str(failure) if isinstance(failure, DeployError) else type(failure).__name__
            persist(directory, receipt, output_file)
            if isinstance(failure, (KeyboardInterrupt, SystemExit)):
                raise
            raise DeployError(receipt["error"]) from None


def validate_good_receipt(receipt, family):
    require(receipt.get("status") == "succeeded" and receipt.get("family") == family
            and receipt.get("cluster") == CLUSTER and receipt.get("source_repository") == SOURCE_REPOS[family],
            "receipt is not a successful release for this family/cluster")
    validate_request(Request(family, receipt.get("source_branch", ""), receipt.get("source_commit", ""),
                             receipt.get("digest", ""), receipt.get("image_tag", ""), 900))
    require(set(receipt.get("ready", [])) == set(APPS[family]) and set(receipt.get("applied", [])) == set(APPS[family]),
            "receipt does not prove a complete Application group")


def bootstrap_overrides(state_root, family):
    require(family in APPS, "invalid family")
    with deployment_lock(state_root, family) as directory:
        current = json.loads((directory / "current.json").read_text())
        good = json.loads((directory / "last-good.json").read_text())
        validate_good_receipt(good, family)
        require(current.get("status") == "succeeded" and current.get("release_id") == good.get("release_id")
                and not (directory / "pending.json").exists(), "incomplete/newer desired release blocks stale bootstrap restoration")
        return {name: {"image.tag": good["image_tag"], "image.digest": good["digest"]} for name in APPS[family]}


def rollback_patch(live_app, current_receipt, previous_good):
    """Prepare, never execute, a deliberately requested conditional rollback."""
    family = current_receipt.get("family")
    require(family in APPS, "invalid rollback family")
    validate_good_receipt(previous_good, family)
    name = live_app.get("metadata", {}).get("name")
    validate_app(live_app, family, name)
    require(current_receipt.get("cluster") == CLUSTER and current_receipt.get("apps", {}).get(name, {}).get("uid")
            == live_app["metadata"]["uid"], "Application was recreated; rollback requires new review")
    require(parameter_images(live_app) == {"image.tag": current_receipt.get("image_tag"),
                                          "image.digest": current_receipt.get("digest")},
            "another release owns this Application; refusing stale rollback")
    return image_patch(live_app, previous_good["image_tag"], previous_good["digest"])


def check_access(family, runtime):
    runtime.verify_identity()
    for name, namespace in APPS[family].items():
        for verb in ("get", "patch"):
            require(runtime.can_i(verb, "applications.argoproj.io/" + name, "argocd"), "named Application access denied")
        require(runtime.can_i("get", "deployments.apps/" + name, namespace), "named Deployment read denied")
        require(runtime.can_i("list", "pods", namespace), "Pod observation access denied")
        app = runtime.get_app(name)
        validate_app(app, family, name)
        # Admission/RBAC check only. Server dry-run never changes Application state.
        runtime.patch_app(name, image_patch(app, parameter_images(app).get("image.tag", ""),
                                          parameter_images(app).get("image.digest", ""))[:2], dry_run=True)
    return {"status": "access-verified", "family": family, "cluster": CLUSTER}


class Runtime:
    """External AWS CLI, kubectl and GitHub boundary; no source SDK required."""

    def __init__(self):
        self.directory = None
        self.kubeconfig = None
        self.kubectl = os.environ.get("KUBECTL", "kubectl")

    def __enter__(self):
        self.directory = tempfile.TemporaryDirectory(prefix="star23-staging-")
        self.kubeconfig = str(Path(self.directory.name) / "kubeconfig")
        try:
            self.verify_identity()
            self.command(["aws", "eks", "update-kubeconfig", "--name", CLUSTER, "--region", REGION,
                          "--kubeconfig", self.kubeconfig, "--alias", CLUSTER], json_output=False)
            config = self.kube(["config", "view", "--minify", "-o", "json"])
            endpoint = self.command(["aws", "eks", "describe-cluster", "--name", CLUSTER, "--region", REGION,
                                     "--output", "json"])["cluster"]["endpoint"]
            require(len(config.get("clusters", [])) == 1 and config["clusters"][0]["cluster"]["server"] == endpoint,
                    "generated kubeconfig does not target staging")
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
        require(self.kubeconfig is not None, "staging kubeconfig is not initialized")
        return self.command([self.kubectl, "--kubeconfig", self.kubeconfig, "--context", CLUSTER,
                             "--request-timeout=20s"] + args)

    def verify_identity(self):
        identity = self.command(["aws", "sts", "get-caller-identity", "--region", REGION, "--output", "json"])
        require(identity.get("Account") == ACCOUNT and identity.get("Arn", "").startswith(
            "arn:aws:sts::" + ACCOUNT + ":assumed-role/star23-ci-controller/"), "unexpected CI AWS identity")
        cluster = self.command(["aws", "eks", "describe-cluster", "--name", CLUSTER, "--region", REGION, "--output", "json"])["cluster"]
        require(cluster.get("name") == CLUSTER and cluster.get("arn") == CLUSTER_ARN and cluster.get("status") == "ACTIVE",
                "unexpected staging EKS identity/status")

    def source_head(self, family):
        token = os.environ.get("SOURCE_TOKEN") or os.environ.get("SOURCE_GITHUB_TOKEN")
        require(bool(token), "source read token is required")
        request = urllib.request.Request("https://api.github.com/repos/" + SOURCE_REPOS[family] + "/git/ref/heads/dev",
                                         headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                                                  "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "star23-staging-cd"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.load(response)
        except (OSError, ValueError, urllib.error.HTTPError):
            raise DeployError("could not verify current source dev HEAD") from None
        require(payload.get("ref") == "refs/heads/dev" and payload.get("object", {}).get("type") == "commit",
                "unexpected source ref response")
        return payload["object"].get("sha")

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
        answer = self.command([self.kubectl, "--kubeconfig", self.kubeconfig, "--context", CLUSTER,
                               "--request-timeout=20s", "auth", "can-i", verb, resource, "-n", namespace], json_output=False)
        return answer == "yes"


def parse_args(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--family", choices=("be", "ai"), required=True)
    parser.add_argument("--source-branch")
    parser.add_argument("--source-commit")
    parser.add_argument("--digest-file", type=Path)
    parser.add_argument("--image-tag")
    parser.add_argument("--output-file", type=Path)
    parser.add_argument("--state-root", type=Path, default=STATE_ROOT)
    parser.add_argument("--timeout-seconds", type=int, default=900)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--execute", action="store_true")
    mode.add_argument("--check-access", action="store_true")
    args = parser.parse_args(arguments)
    if args.execute and any(getattr(args, name) is None for name in (
            "source_branch", "source_commit", "digest_file", "image_tag", "output_file")):
        parser.error("--execute requires source branch/commit, digest file, image tag and output file")
    return args


def main(arguments=None):
    args = parse_args(arguments)
    try:
        if args.check_access:
            with Runtime() as runtime:
                result = check_access(args.family, runtime)
            if args.output_file:
                atomic_json(args.output_file, result)
        else:
            request = Request(args.family, args.source_branch, args.source_commit, args.digest_file.read_text().strip(),
                              args.image_tag, args.timeout_seconds)
            validate_request(request)
            with Runtime() as runtime:
                result = deploy(request, runtime, args.state_root, args.output_file)
        print(json.dumps({"status": result["status"], "family": args.family, "cluster": CLUSTER}))
        return 0
    except (DeployError, OSError, ValueError, KeyError) as failure:
        print("Staging deployment failed: " + str(failure), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
