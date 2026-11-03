#!/usr/bin/env python3
"""Check a private Terraform JSON plan without printing values or raw diffs."""

import argparse
import json
from pathlib import Path


def audit(plan):
    """Accept complete plans with only reads, no-ops, imports and forgets."""
    if plan.get("errored") is not False or plan.get("complete") is not True:
        raise ValueError("Plan is errored, incomplete, or missing completion metadata")
    if plan.get("deferred_changes"):
        raise ValueError("Plan contains deferred changes")
    changes = plan.get("resource_changes")
    if not isinstance(changes, list):
        raise ValueError("Plan is missing resource changes")
    counts = dict(create=0, update=0, delete=0, replace=0, imports=0, forget=0)
    for resource in changes:
        change = resource["change"]
        actions = change["actions"]
        for action in ("create", "update", "delete", "forget"):
            counts[action] += action in actions
        counts["replace"] += "create" in actions and "delete" in actions
        counts["imports"] += change.get("importing") is not None
        if actions not in (["no-op"], ["read"], ["forget"]):
            raise ValueError("Plan contains AWS writes or unsupported resource actions")
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan_json", type=Path, help="Private output of terraform show -json")
    args = parser.parse_args()
    try:
        result = audit(json.loads(args.plan_json.read_text()))
    except (ValueError, KeyError, TypeError):
        parser.exit(1, "FAIL: plan is incomplete, invalid, or proposes resource writes.\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
