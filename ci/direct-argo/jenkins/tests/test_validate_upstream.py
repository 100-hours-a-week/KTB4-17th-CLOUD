import json
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "validate_upstream.py"
SHA = "a" * 40
DIGEST = "sha256:" + "1" * 64
REGISTRY = "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/star23/"


def fixture(family, branch="dev", outcome="released"):
    environment = "staging" if branch == "dev" else "prod"
    repository = "100-hours-a-week/KTB4-17th-" + ("BE" if family == "be" else "AI")
    job = ("ci/backend/" if family == "be" else "ci/ai/") + branch
    receipt = {
        "schema_version": 2, "family": family, "source_repository": repository,
        "source_job": job, "build_number": 8, "run_id": job + "#8",
        "result": "SUCCESS", "push_image": True, "source_branch": branch, "environment": environment, "source_commit": SHA,
        "scm_evidence": [{"kind": "SCMRevisionAction", "source_repository": repository,
                          "source_sha": SHA, "branch": branch}],
    }
    files = {"upstream-validation.json": receipt, "image-digest.txt": DIGEST + "\n"}
    if family == "be":
        files.update({
            "image-uri.txt": REGISTRY + "be@" + DIGEST + "\n",
            "image-version.json": {"source_repository": repository, "source_branch": "dev",
                                   "source_commit": SHA, "environment": "staging", "git_release_tag": None,
                                   "image_tag": "dev-" + SHA, "release_outcome": "development"},
            "ecr-image.json": {"status": "ecr-tags-verified", "source_repository": repository,
                               "source_branch": "dev", "source_commit": SHA, "environment": "staging",
                               "image_tag": "dev-" + SHA, "image_digest": DIGEST,
                               "image": REGISTRY + "be@" + DIGEST},
        })
    else:
        files.update({
            "image-reference.txt": REGISTRY + "ai@" + DIGEST + "\n", "image-tag.txt": "dev-" + SHA + "\n",
            "release-version.json": {"source_sha": SHA, "source_branch": "dev", "release_tag": None,
                                     "image_tag": "dev-" + SHA, "release_status": "development"},
        })
    if branch == "main":
        tag = "v4.2.2" if outcome == "released" else "sha-" + SHA
        version = files["image-version.json" if family == "be" else "release-version.json"]
        version.update(source_branch=branch, image_tag=tag)
        if family == "be":
            version.update(environment=environment, git_release_tag=tag if outcome == "released" else None,
                           release_outcome=outcome, release_workflow_id=1234, release_workflow_attempt=2,
                           release_workflow_url=f"https://github.com/{repository}/actions/runs/1234")
            files["ecr-image.json"].update(source_branch=branch, environment=environment, image_tag=tag)
        else:
            version.update(release_tag=tag if outcome == "released" else None, release_status=outcome,
                           workflow_run_id=1234, workflow_run_attempt=2,
                           workflow_run_url=f"https://github.com/{repository}/actions/runs/1234")
            files["image-tag.txt"] = tag
    if family == "be":
        files["ecr-image.json"]["source_image_tag"] = SHA
    return files


class ValidateUpstreamTest(unittest.TestCase):
    def invoke(self, family, files, mutate_files=None, branch="dev", environment=None):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            base = Path(directory)
            inputs = base / "input"
            inputs.mkdir()
            for name, value in files.items():
                (inputs / name).write_text(json.dumps(value) if isinstance(value, dict) else value)
            if mutate_files:
                mutate_files(inputs)
            output = base / "verified-release.json"
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--family", family,
                                     "--source-branch", branch, "--environment", environment or ("staging" if branch == "dev" else "prod"),
                                     "--input-dir", str(inputs), "--output-file", str(output)],
                                    text=True, capture_output=True)
            return result, json.loads(output.read_text()) if output.exists() else None

    def test_both_families_normalize_exact_successful_image_build(self):
        for family in ("be", "ai"):
            with self.subTest(family=family):
                result, output = self.invoke(family, fixture(family))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output["source_commit"], SHA)
                self.assertEqual(output["image_digest"], DIGEST)
                self.assertEqual(output["image_tag"], "dev-" + SHA)
                self.assertEqual(output["image"], REGISTRY + family + "@" + DIGEST)
                self.assertEqual(output["source_branch"], "dev")

    def test_main_preserves_publisher_released_and_no_release_semantics(self):
        for family in ("be", "ai"):
            for outcome in ("released", "no-release"):
                with self.subTest(family=family, outcome=outcome):
                    result, output = self.invoke(family, fixture(family, "main", outcome), branch="main")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output["schema_version"], 2)
                    self.assertEqual(output["result"], "SUCCESS")
                    self.assertEqual(output["environment"], "prod")
                    self.assertEqual(output["source_branch"], "main")
                    self.assertEqual(output["release_outcome"], outcome)
                    self.assertEqual(output["image_tag"], "v4.2.2" if outcome == "released" else "sha-" + SHA)
                    self.assertIn("publisher_version", output)

    def test_normalized_record_sanitizes_publisher_fields_and_contains_only_agreed_interface(self):
        core = {"schema_version", "family", "source_repository", "source_branch", "environment", "source_commit",
                "image_tag", "image_digest", "source_job", "build_number", "run_id", "result", "image"}
        for family in ("be", "ai"):
            for branch in ("dev", "main"):
                files = fixture(family, branch)
                name = "image-version.json" if family == "be" else "release-version.json"
                files[name]["hostile_extra"] = "secret-must-never-be-archived"
                result, output = self.invoke(family, files, branch=branch)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(set(output), core | ({"publisher_version", "release_outcome"} if branch == "main" else set()))
                if branch == "main":
                    self.assertEqual(set(output["publisher_version"]),
                                     {"workflow_run_id", "workflow_run_attempt", "workflow_path", "workflow_url", "git_release_tag"})
                self.assertNotIn("secret-must-never-be-archived", json.dumps(output))

    def test_every_normalized_profile_is_consumed_by_protected_deployment_interface(self):
        helper_path = ROOT.parent / "common" / "deploy_release.py"
        spec = importlib.util.spec_from_file_location("direct_cd_release_interface", helper_path)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        for family in ("be", "ai"):
            for branch in ("dev", "main"):
                for outcome in (("released", "no-release") if branch == "main" else ("development",)):
                    environment = "staging" if branch == "dev" else "prod"
                    result, output = self.invoke(family, fixture(family, branch, outcome), branch=branch)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    request = helper.request_from_release(output, family, environment, branch, SHA)
                    self.assertEqual(request.source_commit, SHA)
                    self.assertEqual(request.digest, DIGEST)
                    self.assertEqual(request.environment, environment)

    def test_reused_publisher_keeps_its_exact_old_run_and_forged_artifacts_fail(self):
        for family in ("be", "ai"):
            files = fixture(family, "main")
            # A later ordinary CI trigger does not rewrite the publisher identity.
            trigger = {"build_number": 10, "source_commit": SHA}
            result, output = self.invoke(family, files, branch="main")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output["build_number"], 8)
            self.assertTrue(output["run_id"].endswith("#8"))
            self.assertEqual(output["source_commit"], trigger["source_commit"])
            name, field = ("image-version.json", "source_commit") if family == "be" else ("release-version.json", "source_sha")
            files[name][field] = "b" * 40
            result, output = self.invoke(family, files, branch="main")
            self.assertNotEqual(result.returncode, 0)
            self.assertIsNone(output)

    def test_reused_publisher_stale_source_head_is_rejected_before_any_application_patch(self):
        helper_path = ROOT.parent / "common" / "deploy_release.py"
        spec = importlib.util.spec_from_file_location("reuse_current_head_gate", helper_path)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)

        class MovedHead:
            def __init__(self): self.patched = []
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def verify_identity(self): pass
            def source_head(self, family, branch): return "b" * 40
            def patch_app(self, *args): self.patched.append(args)

        for family in ("be", "ai"):
            for branch in ("dev", "main"):
                result, output = self.invoke(family, fixture(family, branch), branch=branch)
                self.assertEqual(result.returncode, 0, result.stderr)
                request = helper.request_from_release(output, family, "staging" if branch == "dev" else "prod", branch, SHA)
                runtime = MovedHead()
                with tempfile.TemporaryDirectory() as directory:
                    base = Path(directory)
                    with self.assertRaises(helper.DeployError):
                        helper.deploy(request, runtime, base / "state", base / "deployment.json")
                    rejected = json.loads((base / "deployment.json").read_text())
                    self.assertEqual(rejected["preflight_stage"], "source_head")
                    self.assertEqual(rejected["run_id"], output["run_id"])
                self.assertEqual(runtime.patched, [])

    def test_main_rejects_missing_foreign_untyped_or_inconsistent_publisher_proof(self):
        for family in ("be", "ai"):
            name = "image-version.json" if family == "be" else "release-version.json"
            prefix = "release_workflow" if family == "be" else "workflow_run"
            status = "release_outcome" if family == "be" else "release_status"
            tag = "git_release_tag" if family == "be" else "release_tag"
            for field, value in ((prefix + "_id", True), (prefix + "_id", 0),
                                 (prefix + "_attempt", "1"), (prefix + "_url", "https://evil.invalid/1234"),
                                 (status, "development"), (status, "no-release"), (tag, None),
                                 ("image_tag", "dev-" + SHA), ("image_tag", "v01.2.3")):
                with self.subTest(family=family, field=field, value=value):
                    files = fixture(family, "main")
                    files[name][field] = value
                    result, output = self.invoke(family, files, branch="main")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIsNone(output)
            files = fixture(family, "main", "no-release")
            files[name]["image_tag"] = "sha-" + "b" * 40
            result, _ = self.invoke(family, files, branch="main")
            self.assertNotEqual(result.returncode, 0)
            files = fixture(family, "main")
            del files[name][prefix + "_id"]
            result, _ = self.invoke(family, files, branch="main")
            self.assertNotEqual(result.returncode, 0)

    def test_explicit_fixed_profile_rejects_cross_environment_and_cross_branch(self):
        for family in ("be", "ai"):
            result, _ = self.invoke(family, fixture(family, "main"))
            self.assertNotEqual(result.returncode, 0)
            result, _ = self.invoke(family, fixture(family, "main"), branch="main", environment="staging")
            self.assertNotEqual(result.returncode, 0)

    def test_unsuccessful_unpublished_wrong_job_or_foreign_receipt_is_rejected(self):
        mutations = [("result", "FAILURE"), ("push_image", "true"), ("push_image", False),
                     ("source_branch", "main"), ("source_job", "ci/backend/main"),
                     ("source_repository", "someone/other"), ("build_number", True),
                     ("run_id", "ci/backend/dev#9"), ("schema_version", True), ("family", "ai")]
        for field, value in mutations:
            with self.subTest(field=field, value=value):
                files = fixture("be")
                files["upstream-validation.json"][field] = value
                result, output = self.invoke("be", files)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(output)

    def test_source_sha_must_agree_with_scm_and_all_artifacts(self):
        for family in ("be", "ai"):
            for target in ("receipt", "scm", "version"):
                with self.subTest(family=family, target=target):
                    files = fixture(family)
                    receipt = files["upstream-validation.json"]
                    if target == "receipt":
                        receipt["source_commit"] = "b" * 40
                    elif target == "scm":
                        receipt["scm_evidence"][0]["source_sha"] = "b" * 40
                    else:
                        name, key = ("image-version.json", "source_commit") if family == "be" else ("release-version.json", "source_sha")
                        files[name][key] = "b" * 40
                    result, output = self.invoke(family, files)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIsNone(output)

    def test_missing_or_foreign_scm_proof_is_rejected(self):
        for proof in ([], [{"kind": "made-up", "source_repository": "100-hours-a-week/KTB4-17th-BE",
                            "source_sha": SHA, "branch": "dev"}],
                      [{"kind": "BuildData", "source_repository": "someone/other", "source_sha": SHA, "branch": "dev"}]):
            files = fixture("be")
            files["upstream-validation.json"]["scm_evidence"] = proof
            result, output = self.invoke("be", files)
            self.assertNotEqual(result.returncode, 0)
            self.assertIsNone(output)

    def test_tag_digest_repository_and_production_release_injection_are_rejected(self):
        cases = [
            ("be", "image-uri.txt", REGISTRY + "ai@" + DIGEST),
            ("ai", "image-reference.txt", REGISTRY + "be@" + DIGEST),
            ("ai", "image-tag.txt", "dev-" + "b" * 40),
            ("be", "image-digest.txt", "sha256:" + "2" * 64),
        ]
        for family, name, value in cases:
            files = fixture(family)
            files[name] = value
            result, output = self.invoke(family, files)
            self.assertNotEqual(result.returncode, 0)
            self.assertIsNone(output)
        files = fixture("be")
        files["image-version.json"]["git_release_tag"] = "v1.2.3"
        result, output = self.invoke("be", files)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(output)

    def test_missing_extra_oversized_symlink_and_duplicate_json_inputs_fail_closed(self):
        changes = [
            lambda p: (p / "image-digest.txt").unlink(),
            lambda p: (p / "unapproved.txt").write_text("not accepted"),
            lambda p: (p / "image-digest.txt").write_text("x" * (128 * 1024 + 1)),
            lambda p: ((p / "image-digest.txt").unlink(), (p / "image-digest.txt").symlink_to(p / "image-uri.txt")),
            lambda p: (p / "image-version.json").write_text('{"source_commit":"' + SHA + '","source_commit":"' + "b" * 40 + '"}'),
        ]
        for change in changes:
            result, output = self.invoke("be", fixture("be"), change)
            self.assertNotEqual(result.returncode, 0)
            self.assertIsNone(output)

    def test_failure_never_echoes_untrusted_artifact_values(self):
        marker = "sensitive-untrusted-field"
        files = fixture("ai")
        files["image-reference.txt"] = marker
        result, _ = self.invoke("ai", files)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(marker, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
