#!/usr/bin/env python3
"""Check complete private Terraform plans against a bounded reconciliation manifest."""

import argparse
import json
from pathlib import Path


def audit(plan, manifest=None):
    """Reject writes and any unlisted, missing, or differently identified state operation.

    Without a manifest, require steady-state plans (no imports, forgets or moves).
    A manifest contains exact imports {address: id}, forget {address: id}, and
    moves {previous_address: address}; it contains identities, never secret values.
    """
    if plan.get("errored") is not False or plan.get("complete") is not True:
        raise ValueError("Plan is errored, incomplete, or missing completion metadata")
    if plan.get("deferred_changes"):
        raise ValueError("Plan contains deferred changes")
    changes = plan.get("resource_changes")
    if not isinstance(changes, list):
        raise ValueError("Plan is missing resource changes")
    expected = {key: {} for key in ("imports", "forget", "moves")}
    if manifest is not None:
        if set(manifest) != set(expected) or any(not isinstance(v, dict) for v in manifest.values()):
            raise ValueError("Invalid reconciliation manifest")
        expected = manifest
    observed = {key: {} for key in expected}
    counts = dict(create=0, update=0, delete=0, replace=0, imports=0, forget=0)
    seen = set()
    for resource in changes:
        change = resource["change"]
        actions = change["actions"]
        for action in ("create", "update", "delete", "forget"):
            counts[action] += action in actions
        counts["replace"] += "create" in actions and "delete" in actions
        counts["imports"] += change.get("importing") is not None
        if actions not in (["no-op"], ["read"], ["forget"]):
            raise ValueError("Plan contains AWS writes or unsupported resource actions")
        address = resource.get("address")
        if address is not None:
            if address in seen:
                raise ValueError("Duplicate resource address")
            seen.add(address)
        if change.get("importing") is not None:
            observed["imports"][resource["address"]] = change["importing"]["id"]
        if actions == ["forget"]:
            observed["forget"][resource["address"]] = change["before"]["id"]
        if resource.get("previous_address"):
            previous = resource["previous_address"]
            if previous in observed["moves"]:
                raise ValueError("Duplicate previous address")
            observed["moves"][previous] = resource["address"]
    if observed != expected:
        raise ValueError("State reconciliation differs from the exact approved proposal")
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan_json", type=Path, help="Private output of terraform show -json")
    parser.add_argument("--manifest", type=Path, help="Private exact reconciliation proposal")
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text()) if args.manifest else None
        result = audit(json.loads(args.plan_json.read_text()), manifest)
    except (ValueError, KeyError, TypeError):
        parser.exit(1, "FAIL: incomplete/invalid plan, AWS writes, or unbounded state reconciliation.\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
