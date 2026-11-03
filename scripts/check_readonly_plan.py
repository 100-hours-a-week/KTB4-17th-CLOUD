#!/usr/bin/env python3
"""Check complete private Terraform plans against a bounded reconciliation manifest."""

import argparse
import json
from pathlib import Path


def known_id(change, side):
    values = change.get(side)
    if not isinstance(values, dict) or not isinstance(values.get("id"), str) or not values["id"]:
        raise ValueError("Resource identity is missing or invalid")
    unknown = change.get("after_unknown", {})
    if side == "after" and (not isinstance(unknown, dict) or unknown.get("id")):
        raise ValueError("Resource identity is unknown")
    return values["id"]


def audit(plan, manifest=None):
    """Reject writes and any unlisted, missing, or differently identified state operation.

    Without a manifest, require steady-state plans (no imports, forgets or moves).
    A manifest contains exact imports {address: id}, forget {address: id}, and
    moves {previous_address: {address: target, id: existing_id}};
    it contains identities, never secret values.
    """
    if plan.get("errored") is not False or plan.get("complete") is not True:
        raise ValueError("Plan is errored, incomplete, or missing completion metadata")
    if plan.get("deferred_changes"):
        raise ValueError("Plan contains deferred changes")
    for field in ("action_invocations", "deferred_action_invocations"):
        if field in plan and (not isinstance(plan[field], list) or plan[field]):
            raise ValueError("Plan contains action invocations or unsupported action metadata")
    changes = plan.get("resource_changes")
    if not isinstance(changes, list):
        raise ValueError("Plan is missing resource changes")
    expected = {key: {} for key in ("imports", "forget", "moves")}
    if manifest is not None:
        if set(manifest) != set(expected) or any(not isinstance(v, dict) for v in manifest.values()):
            raise ValueError("Invalid reconciliation manifest")
        for category in ("imports", "forget"):
            if any(not isinstance(a, str) or not a or not isinstance(i, str) or not i
                   for a, i in manifest[category].items()):
                raise ValueError("Invalid reconciliation identities")
        for previous, move in manifest["moves"].items():
            if (not isinstance(previous, str) or not previous or not isinstance(move, dict)
                    or set(move) != {"address", "id"}
                    or any(not isinstance(v, str) or not v for v in move.values())):
                raise ValueError("Invalid move identity")
        if len({m["address"] for m in manifest["moves"].values()}) != len(manifest["moves"]):
            raise ValueError("Duplicate move destination")
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
            identity = change["importing"]["id"]
            if known_id(change, "after") != identity:
                raise ValueError("Imported identity is missing, unknown or changed")
            observed["imports"][resource["address"]] = identity
        if actions == ["forget"]:
            observed["forget"][resource["address"]] = known_id(change, "before")
        if resource.get("previous_address"):
            previous = resource["previous_address"]
            if previous in observed["moves"]:
                raise ValueError("Duplicate previous address")
            move = expected["moves"].get(previous)
            if (move is None or resource.get("mode", "managed") != "managed"
                    or known_id(change, "before") != move["id"]
                    or known_id(change, "after") != move["id"]):
                raise ValueError("Moved identity is missing, unknown or changed")
            observed["moves"][previous] = {"address": resource["address"], "id": move["id"]}
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
