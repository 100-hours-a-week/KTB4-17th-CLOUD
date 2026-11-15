"""Deployment contract tests; only AWS, Kubernetes and GitHub are faked."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


MODULE = Path(__file__).with_name("deploy_staging.py")


def load_module():
    if not MODULE.exists():
        return None
    spec = importlib.util.spec_from_file_location("deploy_staging", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cd = load_module()
SHA = "a" * 40
OTHER_SHA = "b" * 40
CHART_SHA = "c" * 40
MANIFEST = '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{},"layers":[]}'
DIGEST = "sha256:" + hashlib.sha256(MANIFEST.encode()).hexdigest()
OLD_DIGEST = "sha256:" + "2" * 64
REPO = "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/star23/ai"
AI_APPS = {
    "onboarding-persona-ai": "user", "onboarding-face-certify-ai": "user",
    "image-worker": "user", "chat-ai-practice": "chat",
    "chat-ai-simulation": "chat", "chat-ai-cleanup": "chat",
}
BE_APPS = {"auth-api": "auth", "user-api": "user", "onboarding-api": "user",
           "chat-api": "chat", "chat-socket": "chat", "recommend-api": "recommend"}


def application(name, namespace, family="ai"):
    return {
        "metadata": {"name": name, "namespace": "argocd", "uid": "uid-" + name, "resourceVersion": "7"},
        "spec": {
            "project": "star23-apps",
            "destination": {"namespace": namespace, "server": "https://kubernetes.default.svc"},
            "source": {
                "repoURL": "https://github.com/100-hours-a-week/KTB4-17th-CLOUD.git",
                "targetRevision": "main", "path": "manifest/helm/star23-service",
                "helm": {"releaseName": name, "valueFiles": ["values/staging/" + name + ".yaml"],
                         "valuesObject": {"image": {"repository": REPO[:-2] + family, "digest": OLD_DIGEST}},
                         "parameters": [{"name": "unrelated.key", "value": "preserved", "forceString": True}]},
            },
            "syncPolicy": {"automated": {"enabled": True, "selfHeal": True}},
        },
    }


def apply_json_patch(document, operations):
    """Small independent fake API implementation, including conditional tests."""
    document = copy.deepcopy(document)
    for op in operations:
        parts = [p.replace("~1", "/").replace("~0", "~") for p in op["path"].strip("/").split("/")]
        parent = document
        for part in parts[:-1]:
            parent = parent[int(part)] if isinstance(parent, list) else parent[part]
        key = parts[-1]
        if op["op"] == "test":
            actual = parent[int(key)] if isinstance(parent, list) else parent[key]
            if actual != op["value"]:
                raise RuntimeError("API conflict")
        elif isinstance(parent, list):
            if key == "-":
                parent.append(copy.deepcopy(op["value"]))
            elif op["op"] == "remove":
                parent.pop(int(key))
            else:
                parent[int(key)] = copy.deepcopy(op["value"])
        elif op["op"] == "remove":
            del parent[key]
        else:
            parent[key] = copy.deepcopy(op["value"])
    return document


class ExternalSystems:
    def __init__(self, family="ai"):
        self.family = family
        self.names = AI_APPS if family == "ai" else BE_APPS
        self.repository = REPO[:-2] + family
        self.apps = {name: application(name, namespace, family) for name, namespace in self.names.items()}
        self.patched = []
        self.source = SHA
        self.head_reads = 0
        self.supersede_on_read = None
        self.fail_patch = None
        self.stale_status = False
        self.wrong_pod_digest = False
        self.zero_replicas = False
        self.sidecar_only = False
        self.recreate = False
        self.mutable = False
        self.tag_digest = DIGEST
        self.manifest = MANIFEST
        self.actual_digest = DIGEST
        self.seconds = 0
        self.app_reads = {}
        self.change_before_patch = None
        self.operation = None
        self.operation_phase = None
        self.chart_revision = CHART_SHA
        self.mutate_first_during_last_read = None

    def verify_identity(self):
        return None

    def source_head(self, family):
        self.head_reads += 1
        if self.supersede_on_read == self.head_reads:
            self.source = OTHER_SHA
        return self.source

    def ecr_repository(self, family):
        return {"registryId": "975779326240", "repositoryName": "star23/" + self.family, "repositoryUri": self.repository,
                "imageTagMutability": "MUTABLE" if self.mutable else "IMMUTABLE"}

    def ecr_tag_digest(self, family, tag):
        return self.tag_digest

    def image_manifest(self, family, digest):
        return self.manifest

    def get_app(self, name):
        self.app_reads[name] = self.app_reads.get(name, 0) + 1
        if (self.mutate_first_during_last_read and name == "chat-ai-cleanup"
                and self.app_reads[name] == 3):
            first = self.apps["onboarding-persona-ai"]
            if self.mutate_first_during_last_read == "uid":
                first["metadata"]["uid"] = "recreated-during-scan"
            else:
                first["spec"]["source"]["helm"]["parameters"][-1]["value"] = "sha256:" + "9" * 64
        if self.change_before_patch == name and self.app_reads[name] == 2:
            self.apps[name]["spec"]["source"]["helm"]["parameters"].append(
                {"name": "image.digest", "value": "sha256:" + "9" * 64})
        app = copy.deepcopy(self.apps[name])
        if self.recreate and name in self.patched:
            app["metadata"]["uid"] = "recreated"
        if name in self.patched and not self.stale_status:
            app["status"] = {"sync": {"status": "Synced", "revision": self.chart_revision, "comparedTo": {
                "source": copy.deepcopy(app["spec"]["source"]),
                "destination": copy.deepcopy(app["spec"]["destination"])}}, "health": {"status": "Healthy"}}
        else:
            app["status"] = {"sync": {"status": "Synced", "revision": self.chart_revision, "comparedTo": {
                "source": application(name, self.names[name], self.family)["spec"]["source"],
                "destination": copy.deepcopy(app["spec"]["destination"])}}, "health": {"status": "Healthy"}}
        if self.operation is not None:
            app["operation"] = self.operation
        if self.operation_phase is not None:
            app["status"]["operationState"] = {"phase": self.operation_phase}
        return app

    def patch_app(self, name, patch, dry_run=False):
        if self.fail_patch == name:
            raise RuntimeError("simulated API failure")
        changed = apply_json_patch(self.apps[name], patch)
        if not dry_run:
            changed["metadata"]["resourceVersion"] = "8"
            self.apps[name] = changed
            self.patched.append(name)
        return copy.deepcopy(changed)

    def get_deployment(self, namespace, name):
        replicas = 0 if self.zero_replicas else 1
        return {"metadata": {"name": name, "namespace": namespace, "generation": 4},
                "spec": {"replicas": replicas, "selector": {"matchLabels": {"app.kubernetes.io/instance": name}},
                         "template": {"spec": {"containers": [{"name": name, "image": self.repository + "@" + self.tag_digest}]}}},
                "status": {"observedGeneration": 4, "replicas": replicas, "updatedReplicas": replicas,
                           "readyReplicas": replicas, "availableReplicas": replicas, "unavailableReplicas": 0}}

    def list_pods(self, namespace, labels):
        name = labels["app.kubernetes.io/instance"]
        actual = OLD_DIGEST if self.wrong_pod_digest else self.actual_digest
        primary_id = OLD_DIGEST if self.sidecar_only else actual
        return [{"metadata": {"name": name + "-new", "namespace": namespace, "labels": labels},
                 "spec": {"containers": [{"name": name, "image": self.repository + "@" + self.tag_digest},
                                           {"name": "sidecar", "image": "example/sidecar:one"}]},
                 "status": {"phase": "Running", "conditions": [{"type": "Ready", "status": "True"}],
                            "containerStatuses": [{"name": name, "ready": True, "imageID": self.repository + "@" + primary_id},
                                                  {"name": "sidecar", "ready": True, "imageID": self.repository + "@" + actual}]}}]

    def can_i(self, verb, resource, namespace):
        return True

    def clock(self):
        return self.seconds

    def sleep(self, seconds):
        self.seconds += seconds


class ManifestBoundaryTests(unittest.TestCase):
    def payload(self):
        return {"failures": [], "images": [
            {"imageId": {"imageDigest": DIGEST, "imageTag": SHA}, "imageManifest": MANIFEST},
            {"imageId": {"imageDigest": DIGEST, "imageTag": "dev-" + SHA}, "imageManifest": MANIFEST}]}

    def test_same_digest_and_manifest_returned_once_per_tag_is_valid(self):
        with patch.object(cd.Runtime, "command", return_value=self.payload()):
            self.assertEqual(cd.Runtime().image_manifest("be", DIGEST), MANIFEST)

    def test_conflicting_digest_manifest_empty_response_and_failures_are_rejected(self):
        for fault in ("digest", "manifest", "empty", "failure"):
            with self.subTest(fault=fault):
                payload = self.payload()
                if fault == "digest":
                    payload["images"][1]["imageId"]["imageDigest"] = OLD_DIGEST
                elif fault == "manifest":
                    # Equivalent JSON with different bytes is still ambiguous.
                    payload["images"][1]["imageManifest"] = MANIFEST + "\n"
                elif fault == "empty":
                    payload["images"] = []
                else:
                    payload["failures"] = [{"failureCode": "ImageNotFound"}]
                with patch.object(cd.Runtime, "command", return_value=payload):
                    with self.assertRaises(cd.DeployError):
                        cd.Runtime().image_manifest("be", DIGEST)


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(cd, "deployment helper has not been implemented")
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.runtime = ExternalSystems()
        self.request = cd.Request("ai", "dev", SHA, DIGEST, "dev-" + SHA, 1)

    def run_deploy(self):
        return cd.deploy(self.request, self.runtime, self.root / "state", self.root / "output.json",
                         clock=self.runtime.clock, sleep=self.runtime.sleep)

    def test_success_updates_all_six_ai_apps_and_records_last_good(self):
        receipt = self.run_deploy()
        self.assertEqual(receipt["status"], "succeeded")
        self.assertFalse(receipt["atomic"])
        self.assertEqual(set(self.runtime.patched), set(AI_APPS))
        self.assertEqual(json.loads((self.root / "state/ai/last-good.json").read_text())["digest"], DIGEST)
        self.assertEqual(json.loads((self.root / "output.json").read_text())["status"], "succeeded")
        for app in self.runtime.apps.values():
            self.assertEqual(app["spec"]["source"]["helm"]["parameters"][0],
                             {"name": "unrelated.key", "value": "preserved", "forceString": True})
            self.assertEqual(app["spec"]["source"]["helm"]["valuesObject"]["image"]["digest"], OLD_DIGEST)

    def test_production_pr_and_malformed_identity_are_rejected_before_writes(self):
        for branch, tag in [("main", "dev-" + SHA), ("dev", "latest")]:
            with self.subTest(branch=branch, tag=tag):
                self.request = cd.Request("ai", branch, SHA, DIGEST, tag, 1)
                with self.assertRaises(cd.DeployError):
                    self.run_deploy()
        self.request = cd.Request("ai", "dev", SHA, DIGEST, "dev-" + SHA, 1)
        for name in ("CHANGE_ID", "CHANGE_FORK"):
            with patch.dict("os.environ", {name: "untrusted"}):
                with self.assertRaises(cd.DeployError):
                    self.run_deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_wrong_app_destination_fails_preflight_before_any_patch(self):
        self.runtime.apps["chat-ai-cleanup"]["spec"]["destination"]["namespace"] = "prod"
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_prod_values_chart_revision_and_controller_owned_apps_fail_closed(self):
        for change in ("values", "revision", "chart", "owner", "plugin"):
            with self.subTest(change=change):
                self.runtime = ExternalSystems()
                app = self.runtime.apps["image-worker"]
                if change == "values":
                    app["spec"]["source"]["helm"]["valueFiles"] = ["values/image-worker.yaml"]
                elif change == "revision":
                    app["spec"]["source"]["targetRevision"] = "old-pinned-commit"
                elif change == "chart":
                    app["spec"]["source"]["path"] = "another-chart"
                elif change == "owner":
                    app["metadata"]["ownerReferences"] = [{"kind": "ApplicationSet", "controller": True}]
                else:
                    app["spec"]["source"]["plugin"] = {"name": "unexpected-renderer"}
                with self.assertRaises(cd.DeployError):
                    self.run_deploy()
                self.assertEqual(self.runtime.patched, [])

    def test_newer_image_change_between_preflight_and_patch_is_not_overwritten(self):
        self.runtime.change_before_patch = "image-worker"
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertNotIn("image-worker", self.runtime.patched)
        images = {p["name"]: p["value"] for p in self.runtime.apps["image-worker"]["spec"]["source"]["helm"]["parameters"]}
        self.assertEqual(images["image.digest"], "sha256:" + "9" * 64)

    def test_be_family_deploys_six_correct_namespace_targets(self):
        self.runtime = ExternalSystems("be")
        self.request = cd.Request("be", "dev", SHA, DIGEST, "dev-" + SHA, 1)
        receipt = self.run_deploy()
        self.assertEqual(receipt["status"], "succeeded")
        self.assertEqual(set(receipt["ready"]), {"auth-api", "user-api", "onboarding-api", "chat-api", "chat-socket", "recommend-api"})
        self.assertEqual(receipt["image"], "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/star23/be@" + DIGEST)

    def test_family_flock_blocks_concurrent_mutation(self):
        with cd.deployment_lock(self.root / "state", "ai"):
            with self.assertRaises(cd.DeployError):
                self.run_deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_oci_index_accepts_only_linux_amd64_child_digest(self):
        child = "sha256:" + "3" * 64
        arm_child = "sha256:" + "4" * 64
        index = json.dumps({"schemaVersion": 2, "mediaType": "application/vnd.oci.image.index.v1+json", "manifests": [
            {"digest": child, "platform": {"os": "linux", "architecture": "amd64"}},
            {"digest": arm_child, "platform": {"os": "linux", "architecture": "arm64"}}]})
        index_digest = "sha256:" + hashlib.sha256(index.encode()).hexdigest()
        self.runtime.manifest = index
        self.runtime.tag_digest = index_digest
        self.runtime.actual_digest = child
        self.request = cd.Request("ai", "dev", SHA, index_digest, "dev-" + SHA, 1)
        self.assertEqual(self.run_deploy()["status"], "succeeded")
        self.runtime.actual_digest = arm_child
        with self.assertRaises(cd.DeployError):
            self.run_deploy()

    def test_failed_group_preserves_previous_last_good(self):
        good = self.run_deploy()
        self.runtime.fail_patch = "image-worker"
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        stored = json.loads((self.root / "state/ai/last-good.json").read_text())
        self.assertEqual(stored["release_id"], good["release_id"])
        with self.assertRaises(cd.DeployError):
            cd.bootstrap_overrides(self.root / "state", "ai")

    def test_superseded_commit_fails_under_lock_before_second_app_patch(self):
        self.runtime.supersede_on_read = 3
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertEqual(len(self.runtime.patched), 1)
        receipt = json.loads((self.root / "state/ai/current.json").read_text())
        self.assertEqual(receipt["status"], "partial")
        self.assertFalse((self.root / "state/ai/last-good.json").exists())

    def test_mutable_tags_and_digest_mismatch_cannot_deploy(self):
        self.runtime.mutable = True
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.runtime.mutable = False
        self.runtime.tag_digest = OLD_DIGEST
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_partial_api_failure_is_durable_and_does_not_auto_rollback(self):
        self.runtime.fail_patch = "image-worker"
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        receipt = json.loads((self.root / "output.json").read_text())
        self.assertEqual(receipt["status"], "partial")
        self.assertEqual(len(self.runtime.patched), 2)
        self.assertTrue((self.root / "state/ai/pending.json").exists())

    def test_stale_synced_healthy_is_not_rollout_success(self):
        self.runtime.stale_status = True
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertFalse((self.root / "state/ai/last-good.json").exists())

    def test_pending_running_and_failed_argo_operations_cannot_be_success(self):
        for phase in ("pending", "Running", "Failed", "Error"):
            with self.subTest(phase=phase):
                self.runtime = ExternalSystems()
                if phase == "pending":
                    self.runtime.operation = {"sync": {}}
                else:
                    self.runtime.operation_phase = phase
                with self.assertRaises(cd.DeployError):
                    self.run_deploy()

    def test_deleting_application_is_never_patched(self):
        self.runtime.apps["image-worker"]["metadata"]["deletionTimestamp"] = "2026-11-14T00:00:00Z"
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_chart_revision_is_full_sha_and_recorded_for_each_app(self):
        self.runtime.chart_revision = "main"
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.runtime.chart_revision = CHART_SHA
        self.runtime.operation_phase = "Succeeded"
        receipt = self.run_deploy()
        self.assertEqual(receipt["apps"]["image-worker"]["chart_revision"], CHART_SHA)

    def test_wrong_actual_image_zero_replicas_and_sidecar_match_are_not_success(self):
        for attribute in ["wrong_pod_digest", "zero_replicas", "sidecar_only"]:
            with self.subTest(attribute=attribute):
                self.runtime = ExternalSystems()
                setattr(self.runtime, attribute, True)
                with self.assertRaises(cd.DeployError):
                    self.run_deploy()

    def test_recreated_application_is_not_silently_repatched(self):
        self.runtime.recreate = True
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertEqual(len(self.runtime.patched), 6)

    def test_final_barrier_catches_an_earlier_app_changing_during_group_scan(self):
        for change in ("uid", "image"):
            with self.subTest(change=change):
                self.runtime = ExternalSystems()
                self.runtime.mutate_first_during_last_read = change
                with self.assertRaises(cd.DeployError):
                    self.run_deploy()
                self.assertFalse((self.root / "state/ai/last-good.json").exists())

    def test_patch_uses_uid_and_resource_version_tests_and_preserves_parameters(self):
        app = application("image-worker", "user")
        patch = cd.image_patch(app, "dev-" + SHA, DIGEST)
        changed = apply_json_patch(app, patch)
        concurrent = copy.deepcopy(app)
        concurrent["metadata"]["resourceVersion"] = "9"
        with self.assertRaises(RuntimeError):
            apply_json_patch(concurrent, patch)
        self.assertEqual(changed["spec"]["source"]["helm"]["parameters"][0]["value"], "preserved")
        self.assertEqual(changed["spec"]["source"]["helm"]["valuesObject"], app["spec"]["source"]["helm"]["valuesObject"])

    def test_first_override_creates_parameter_list_without_replacing_inline_values(self):
        app = application("image-worker", "user")
        del app["spec"]["source"]["helm"]["parameters"]
        changed = apply_json_patch(app, cd.image_patch(app, "dev-" + SHA, DIGEST))
        self.assertEqual(changed["spec"]["source"]["helm"]["parameters"], [
            {"name": "image.tag", "value": "dev-" + SHA, "forceString": True},
            {"name": "image.digest", "value": DIGEST, "forceString": True}])
        self.assertEqual(changed["spec"]["source"]["helm"]["valuesObject"], app["spec"]["source"]["helm"]["valuesObject"])

    def test_duplicate_image_parameter_is_rejected(self):
        app = self.runtime.apps["image-worker"]
        app["spec"]["source"]["helm"]["parameters"] += [
            {"name": "image.digest", "value": OLD_DIGEST}, {"name": "image.digest", "value": DIGEST}]
        with self.assertRaises(cd.DeployError):
            self.run_deploy()
        self.assertEqual(self.runtime.patched, [])

    def test_check_access_needs_no_image_arguments_and_never_changes_apps(self):
        args = cd.parse_args(["--family", "ai", "--check-access"])
        self.assertTrue(args.check_access)
        cd.check_access("ai", self.runtime)
        self.assertEqual(self.runtime.patched, [])

    def test_bootstrap_requires_complete_current_last_good(self):
        self.run_deploy()
        result = cd.bootstrap_overrides(self.root / "state", "ai")
        self.assertEqual(result["image-worker"], {"image.tag": "dev-" + SHA, "image.digest": DIGEST})
        current = self.root / "state/ai/current.json"
        data = json.loads(current.read_text())
        data["status"] = "partial"
        current.write_text(json.dumps(data))
        with self.assertRaises(cd.DeployError):
            cd.bootstrap_overrides(self.root / "state", "ai")

    def test_explicit_rollback_refuses_a_newer_release(self):
        receipt = self.run_deploy()
        previous = copy.deepcopy(receipt)
        previous.update(source_commit=OTHER_SHA, image_tag="dev-" + OTHER_SHA, digest=OLD_DIGEST)
        live = self.runtime.get_app("image-worker")
        patch = cd.rollback_patch(live, receipt, previous)
        restored = apply_json_patch(live, patch)
        values = {p["name"]: p["value"] for p in restored["spec"]["source"]["helm"]["parameters"]}
        self.assertEqual(values["image.digest"], OLD_DIGEST)
        live["spec"]["source"]["helm"]["parameters"][-1]["value"] = "sha256:" + "9" * 64
        with self.assertRaises(cd.DeployError):
            cd.rollback_patch(live, receipt, previous)


if __name__ == "__main__":
    unittest.main()
