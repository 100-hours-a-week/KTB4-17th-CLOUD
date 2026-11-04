import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.check_readonly_plan import audit


def plan(*changes, **metadata):
    return {"complete": True, "errored": False, "resource_changes": list(changes), **metadata}


def resource(actions, **extra):
    return {"change": {"actions": actions, **extra}}


class ReadonlyPlanTests(unittest.TestCase):
    def test_action_invocations_and_malformed_metadata_rejected(self):
        for field in ("action_invocations", "deferred_action_invocations"):
            audit(plan(**{field: []}))
            for value in ([{"type": "aws_lambda_invoke"}], [None], {}, "unknown", None, False, 0):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    audit(plan(**{field: value}))

    def test_move_requires_both_exact_known_ids(self):
        evidence = plan({"address": "new", "previous_address": "old", "change": {
            "actions": ["no-op"], "before": {"id": "existing"}, "after": {"id": "existing"},
        }})
        manifest = {"imports": {}, "forget": {}, "moves": {"old": {"address": "new", "id": "existing"}}}
        audit(evidence, manifest)
        for side in ("before", "after"):
            for value in (None, False, [], {}, {"id": None}, {"id": "wrong"}, {"id": ""}):
                changed = copy.deepcopy(evidence)
                changed["resource_changes"][0]["change"][side] = value
                with self.subTest(side=side, value=value), self.assertRaises(ValueError):
                    audit(changed, manifest)
        changed = copy.deepcopy(evidence)
        changed["resource_changes"][0]["change"]["after_unknown"] = {"id": True}
        with self.assertRaises(ValueError):
            audit(changed, manifest)
        for move in ("new", {}, {"address": "new"}, {"address": "new", "id": None},
                     {"address": "new", "id": "wrong"}, {"address": "wrong", "id": "existing"}):
            with self.subTest(move=move), self.assertRaises(ValueError):
                audit(evidence, {**manifest, "moves": {"old": move}})
        for moves in ({}, {"unexpected": {"address": "new", "id": "existing"}},
                      {**manifest["moves"], "missing": {"address": "other", "id": "existing"}}):
            with self.subTest(moves=moves), self.assertRaises(ValueError):
                audit(evidence, {**manifest, "moves": moves})
        duplicate = copy.deepcopy(evidence["resource_changes"][0])
        duplicate["address"] = "other"
        with self.assertRaises(ValueError):
            audit(plan(*evidence["resource_changes"], duplicate), manifest)
        with self.assertRaises(ValueError):
            audit(evidence, {**manifest, "moves": {
                **manifest["moves"], "other": {"address": "new", "id": "existing"},
            }})

    def test_cli_rejects_invocation_and_wrong_move_without_private_values(self):
        manifest = {"imports": {}, "forget": {}, "moves": {
            "old": {"address": "new", "id": "EXPECTED_PRIVATE_ID"},
        }}
        evidence = plan({"address": "new", "previous_address": "old", "change": {
            "actions": ["no-op"], "before": {"id": "WRONG_PRIVATE_ID"},
            "after": {"id": "WRONG_PRIVATE_ID"},
        }})
        for value in (evidence, plan(action_invocations=[{"payload": "PRIVATE_SENTINEL"}]),
                      plan(deferred_action_invocations={"payload": "PRIVATE_SENTINEL"})):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "plan.json"
                proposal = Path(directory) / "manifest.json"
                path.write_text(json.dumps(value))
                proposal.write_text(json.dumps(manifest))
                result = subprocess.run(
                    [sys.executable, "scripts/check_readonly_plan.py", str(path), "--manifest", str(proposal)],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                for private in ("EXPECTED_PRIVATE_ID", "WRONG_PRIVATE_ID", "PRIVATE_SENTINEL", "Traceback"):
                    self.assertNotIn(private, result.stderr)

    def test_complete_noop_and_data_read(self):
        result = audit(plan(resource(["no-op"]), resource(["read"])))
        self.assertEqual(result, dict(create=0, update=0, delete=0, replace=0, imports=0, forget=0))

    def test_imports_and_address_reconciliation_allowed(self):
        evidence = plan(
            {"address": "new", "previous_address": "old", "change": {"actions": ["no-op"], "importing": {"id": "existing"}, "before": {"id": "existing"}, "after": {"id": "existing"}}},
            {"address": "obsolete", "change": {"actions": ["forget"], "before": {"id": "old-id"}}},
        )
        manifest = {"imports": {"new": "existing"}, "forget": {"obsolete": "old-id"}, "moves": {"old": {"address": "new", "id": "existing"}}}
        result = audit(evidence, manifest)
        self.assertEqual(result["imports"], 1)
        self.assertEqual(result["forget"], 1)

    def test_every_write_and_both_replacement_orders_rejected(self):
        for actions in (["create"], ["update"], ["delete"], ["delete", "create"], ["create", "delete"]):
            with self.subTest(actions=actions), self.assertRaises(ValueError):
                audit(plan(resource(actions)))

    def test_import_with_update_is_rejected(self):
        with self.assertRaises(ValueError):
            audit(plan(resource(["update"], importing={"id": "existing"})))

    def test_partial_errored_and_deferred_plans_rejected(self):
        for metadata in ({"complete": False}, {"errored": True}, {"deferred_changes": [{}]}):
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                audit(plan(**metadata))

    def test_missing_evidence_and_unknown_actions_rejected(self):
        for evidence in ({}, {"complete": True, "errored": False}, plan(resource(["future-action"]))):
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                audit(evidence)


    def test_reconciliation_requires_exact_addresses_ids_and_complete_set(self):
        evidence = plan(
            {"address": "new", "previous_address": "old", "change": {"actions": ["no-op"], "importing": {"id": "existing"}, "before": {"id": "existing"}, "after": {"id": "existing"}}},
            {"address": "obsolete", "change": {"actions": ["forget"], "before": {"id": "old-id"}}},
        )
        manifest = {"imports": {"new": "existing"}, "forget": {"obsolete": "old-id"}, "moves": {"old": {"address": "new", "id": "existing"}}}
        with self.assertRaises(ValueError):
            audit(evidence)
        for category in manifest:
            for replacement in ({}, {"unexpected": "wrong"}, {next(iter(manifest[category])): "wrong"}):
                with self.subTest(category=category, replacement=replacement), self.assertRaises(ValueError):
                    audit(evidence, {**manifest, category: replacement})
        with self.assertRaises(ValueError):
            audit(plan(*evidence["resource_changes"], evidence["resource_changes"][0]), manifest)

    def test_all_writes_rejected_even_with_manifest(self):
        manifest = {"imports": {"new": "existing"}, "forget": {}, "moves": {}}
        for actions in (["create"], ["update"], ["delete"], ["delete", "create"], ["create", "delete"]):
            with self.subTest(actions=actions), self.assertRaises(ValueError):
                audit(plan({"address": "new", "change": {"actions": actions, "importing": {"id": "existing"}, "before": {"id": "existing"}, "after": {"id": "existing"}}}), manifest)

    def test_cli_never_prints_private_plan_values(self):
        for actions, expected_exit in ((["update"], 1), (["no-op"], 0)):
            with self.subTest(actions=actions), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "private.json"
                path.write_text(json.dumps(plan(resource(actions, before={"password": "PRIVATE_SENTINEL"}))))
                result = subprocess.run(
                    [sys.executable, "scripts/check_readonly_plan.py", str(path)],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, expected_exit)
                self.assertNotIn("PRIVATE_SENTINEL", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
