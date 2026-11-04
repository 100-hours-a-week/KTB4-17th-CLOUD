#!/usr/bin/env python3
"""Verify private refreshed previews; print only identities, counts and hashes.

Input directory contains prod/dev/loki-plan.json, prod/dev-manifest.json,
source-hashes.json, keys-index.json and before-N.json snapshots. No state writes.
"""
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import unittest
from pathlib import Path

from check_readonly_plan import audit


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def entries(state):
    for resource in state["resources"]:
        if resource["mode"] != "managed":
            continue
        for instance in resource["instances"]:
            address = (resource.get("module", "") + "." if resource.get("module") else "")
            address += resource["type"] + "." + resource["name"]
            if "index_key" in instance:
                address += "[" + json.dumps(instance["index_key"]) + "]"
            yield address, instance["attributes"]["id"]


def verify(private):
    root = Path("terraform")
    hashes = {str(f): digest(f) for f in root.rglob("*.tf") if ".terraform" not in f.parts}
    assert hashes == json.loads((private / "source-hashes.json").read_text())
    for name in ("dev", "prod"):
        for source in (root / name).rglob("*.tf"):
            if ".terraform" in source.parts:
                continue
            assert not re.search(r"^\s*(import|moved|removed)\s*\{", source.read_text(), re.M)
            if name == "dev" and source.name == "backend.tf":
                continue  # Private adoption uses an empty local backend.
            assert digest(source) == digest(private / name / source.relative_to(root / name))
    assert not (private / "dev/backend.tf").exists()
    assert not list((private / "dev").glob("*.tfstate*"))
    plans = {name: json.loads((private / (name + "-plan.json")).read_text())
             for name in ("dev", "prod", "loki")}
    manifests = {name: json.loads((private / (name + "-manifest.json")).read_text())
                 for name in ("dev", "prod")}
    counts = {name: audit(plan, manifests.get(name)) for name, plan in plans.items()}
    assert manifests["prod"]["moves"]
    assert all("module.network.module." in move["address"] for previous, move in manifests["prod"]["moves"].items() if previous.startswith(("module.network.aws_vpc.", "module.network.aws_subnet.", "module.network.aws_route_table.")))
    assert counts["prod"]["imports"] == 7 and counts["prod"]["forget"] == 2
    assert counts["dev"]["imports"] == 3 and counts["dev"]["forget"] == 0
    assert not manifests["dev"]["moves"]
    dev = {r["address"]: r for r in plans["dev"]["resource_changes"] if r.get("mode") == "managed"}
    assert set(dev) == set(manifests["dev"]["imports"])
    assert not plans["dev"].get("prior_state", {}).get("values", {}).get("root_module", {}).get("resources")
    serials = {}
    index = json.loads((private / "keys-index.json").read_text())
    assert len(index) == 5
    owned = set()
    for n, key in index.items():
        before, after = private / f"before-{n}.json", private / f"after-{n}.json"
        subprocess.run(["aws", "s3api", "get-object", "--bucket", "star23-tfstate-975779326240",
                        "--key", key, str(after)], capture_output=True, check=True)
        assert before.read_bytes() == after.read_bytes(), key
        state = json.loads(before.read_text())
        serials[key] = {"serial": state["serial"], "lineage": state["lineage"], "sha256": digest(before)}
        owned.update(identity for _, identity in entries(state))
        if key == "prod/terraform.tfstate":
            prod = state
    assert not owned.intersection(manifests["dev"]["imports"].values())
    changes = {r["address"]: r for r in plans["prod"]["resource_changes"] if r.get("mode") == "managed"}
    expected, preserved = set(), 0
    manifest = manifests["prod"]
    for address, identity in entries(prod):
        target = manifest["moves"].get(address, {}).get("address", address)
        expected.add(target)
        change = changes[target]["change"]
        forgetting = address in manifest["forget"]
        assert change["actions"] == (["forget"] if forgetting else ["no-op"])
        assert change["before" if forgetting else "after"]["id"] == identity
        preserved += not forgetting
    assert set(changes) == expected | set(manifest["imports"])
    assert preserved == 137
    keys = json.loads(subprocess.run(["aws", "s3api", "list-objects-v2", "--bucket",
                                     "star23-tfstate-975779326240"], capture_output=True, check=True).stdout)
    assert "dev/terraform.tfstate" not in {o["Key"] for o in keys["Contents"]}
    caller = json.loads(subprocess.run(["aws", "sts", "get-caller-identity"], capture_output=True, check=True).stdout)
    assert caller["Arn"] == "arn:aws:iam::975779326240:user/noel"
    services = json.loads(subprocess.run(["aws", "ecs", "describe-services", "--region", "ap-northeast-2",
                                         "--cluster", "star23-ecs-cluster", "--services", "star23-be-service",
                                         "star23-ws-service", "star23-ai-service"], capture_output=True, check=True).stdout)
    assert not services["failures"] and len(services["services"]) == 3
    for service in services["services"]:
        name = service["serviceName"].split("-")[1]
        address = f"module.{name}.aws_ecs_service.{name}" + ("[0]" if name == "ws" else "")
        after = changes[address]["change"]["after"]
        assert after["task_definition"] == service["taskDefinition"]
        assert after["desired_count"] == service["desiredCount"]
    spec = importlib.util.spec_from_file_location("graph_tests", "tests/test_dependency_graph.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    graph = subprocess.run(["terraform", "-chdir=terraform/prod", "graph", "-type=plan"],
                           capture_output=True, text=True, check=True).stdout
    (private / "prod-graph.dot").write_text(graph)
    edges = {}
    for source, target in re.findall(r'^\s*"(.+?)" -> "(.+?)"', graph, re.M):
        edges.setdefault(source, set()).add(target)
    module.assert_network_order(unittest.TestCase(), edges)
    summary = {"plans": counts, "preserved_prod_ids": preserved, "moves": len(manifest["moves"]),
               "sources_sha256": hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
               "graph_sha256": digest(private / "prod-graph.dot"), "graph_edges": sum(map(len, edges.values())),
               "remote_unchanged": serials, "dev_remote_state_absent": True, "ci_revisions_preserved": 3}
    (private / "verification-summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("private", type=Path)
    verify(parser.parse_args().private)
