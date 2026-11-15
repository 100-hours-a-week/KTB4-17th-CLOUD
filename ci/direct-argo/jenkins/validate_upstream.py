#!/usr/bin/env python3
"""Normalize only archived image evidence from one controller-validated fixed-profile Run.

No Jenkins, GitHub or AWS calls occur here. The deployment helper independently
rechecks source HEAD, release workflow, ECR and environment resources before any cluster mutation.
"""
import argparse
import json
from pathlib import Path
import re
import stat


LIMIT = 128 * 1024
REGISTRY = "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/star23/"
PROFILES = {
    "be": ("100-hours-a-week/KTB4-17th-BE", "ci/backend/",
           {"image-digest.txt", "image-uri.txt", "image-version.json", "ecr-image.json"}),
    "ai": ("100-hours-a-week/KTB4-17th-AI", "ci/ai/",
           {"image-digest.txt", "image-reference.txt", "image-tag.txt", "release-version.json"}),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON field")
        result[key] = value
    return result


def normalize(family, environment, branch, input_dir):
    require(branch in ("dev", "main") and environment == ("staging" if branch == "dev" else "prod"),
            "Invalid fixed deployment profile")
    repository, job_prefix, names = PROFILES[family]
    job = job_prefix + branch
    names = names | {"upstream-validation.json"}
    require(input_dir.is_dir() and not input_dir.is_symlink(), "Expected a regular input directory")
    require({p.name for p in input_dir.iterdir()} == names, "Archive file allowlist mismatch")
    texts = {}
    for name in sorted(names):
        path = input_dir / name
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and not path.is_symlink(), "Expected a regular archive file")
        require(0 < info.st_size <= LIMIT, "Archive file size outside the allowed range")
        text = path.read_text(encoding="utf-8")
        require("\x00" not in text, "Invalid archive text")
        texts[name] = text.strip()

    def document(name):
        value = json.loads(texts[name], object_pairs_hook=unique_object)
        require(isinstance(value, dict), "Expected a JSON object")
        return value

    receipt = document("upstream-validation.json")
    sha = receipt.get("source_commit")
    require("source_sha" not in receipt or receipt["source_sha"] == sha, "Conflicting source SHA fields")
    require(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid source SHA")
    number = receipt.get("build_number")
    require(type(number) is int and 0 < number <= 2147483647, "Invalid upstream build number")
    require(type(receipt.get("schema_version")) is int and receipt["schema_version"] == 2,
            "Unsupported validation receipt version")
    expected = {"family": family, "source_repository": repository, "source_job": job,
                "source_branch": branch, "environment": environment, "run_id": job + "#" + str(number), "result": "SUCCESS"}
    require(all(receipt.get(k) == v for k, v in expected.items()), "Upstream Run identity mismatch")
    require(receipt.get("push_image") is True, "Upstream Run did not publish an image")
    evidence = receipt.get("scm_evidence")
    require(isinstance(evidence, list) and 0 < len(evidence) <= 8, "Missing SCM evidence")
    for proof in evidence:
        require(isinstance(proof, dict) and proof.get("kind") in ("SCMRevisionAction", "BuildData"),
                "Unsupported SCM evidence")
        require(proof.get("source_repository") == repository and proof.get("source_sha") == sha
                and proof.get("branch") == branch, "SCM evidence does not match the upstream Run")

    digest = texts["image-digest.txt"]
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", digest), "Invalid image digest")
    version = document("image-version.json" if family == "be" else "release-version.json")
    tag = version.get("image_tag")
    outcome = version.get("release_outcome" if family == "be" else "release_status")
    release_tag = version.get("git_release_tag" if family == "be" else "release_tag")
    publisher = None
    if branch == "dev":
        require(tag == "dev-" + sha and outcome == "development" and release_tag is None,
                "Invalid development version")
    else:
        semver = r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
        require((outcome == "released" and isinstance(tag, str) and re.fullmatch(semver, tag)
                 and release_tag == tag) or
                (outcome == "no-release" and tag == "sha-" + sha and release_tag is None),
                "Invalid production publisher outcome")
        prefix = "release_workflow" if family == "be" else "workflow_run"
        run_id, attempt = version.get(prefix + "_id"), version.get(prefix + "_attempt")
        require(type(run_id) is int and 0 < run_id <= 2**63 - 1 and
                type(attempt) is int and 0 < attempt <= 2147483647, "Invalid publisher workflow identity")
        url = f"https://github.com/{repository}/actions/runs/{run_id}"
        require(version.get(prefix + "_url") == url, "Invalid publisher workflow URL")
        publisher = {"workflow_run_id": run_id, "workflow_run_attempt": attempt,
                     "workflow_path": ".github/workflows/release.yml", "workflow_url": url,
                     "git_release_tag": release_tag}
    image = REGISTRY + family + "@" + digest
    if family == "be":
        require(texts["image-uri.txt"] == image, "Image reference mismatch")
        expected_version = {"source_repository": repository, "source_branch": branch, "source_commit": sha,
                            "environment": environment, "image_tag": tag}
        require(all(version.get(k) == v for k, v in expected_version.items()), "Image version metadata mismatch")
        published = document("ecr-image.json")
        expected_published = {"status": "ecr-tags-verified", "source_repository": repository,
                              "source_branch": branch, "source_commit": sha, "environment": environment,
                              "source_image_tag": sha,
                              "image_tag": tag, "image_digest": digest, "image": image}
        require(all(published.get(k) == v for k, v in expected_published.items()), "ECR metadata mismatch")
    else:
        require(texts["image-reference.txt"] == image and texts["image-tag.txt"] == tag, "Image reference or tag mismatch")
        expected_version = {"source_sha": sha, "source_branch": branch, "image_tag": tag}
        require(all(version.get(k) == v for k, v in expected_version.items()), "Image version metadata mismatch")
    release = {"schema_version": 2, "environment": environment, "result": "SUCCESS", "family": family, "source_repository": repository,
            "source_job": job, "build_number": number, "run_id": receipt["run_id"],
            "source_branch": branch, "source_commit": sha, "image_tag": tag,
            "image_digest": digest, "image": image}
    if publisher is not None:
        release.update(publisher_version=publisher, release_outcome=outcome)
    return release


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--family", choices=tuple(PROFILES), required=True)
    parser.add_argument("--environment", choices=("staging", "prod"), required=True)
    parser.add_argument("--source-branch", choices=("dev", "main"), required=True)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-file", type=Path, required=True)
    args = parser.parse_args()
    try:
        release = normalize(args.family, args.environment, args.source_branch, args.input_dir)
        args.output_file.write_text(json.dumps(release, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, KeyError, TypeError, UnicodeError):
        # Artifact content and parser errors may contain credentials or hostile text.
        parser.exit(1, "Upstream image evidence validation failed; no deployment inputs produced.\n")
    print("Verified " + release["run_id"] + " image evidence")


if __name__ == "__main__":
    main()
