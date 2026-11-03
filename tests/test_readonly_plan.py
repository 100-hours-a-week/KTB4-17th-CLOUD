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
    def test_complete_noop_and_data_read(self):
        result = audit(plan(resource(["no-op"]), resource(["read"])))
        self.assertEqual(result, dict(create=0, update=0, delete=0, replace=0, imports=0, forget=0))

    def test_imports_and_address_reconciliation_allowed(self):
        result = audit(plan(resource(["no-op"], importing={"id": "existing"}), resource(["forget"])))
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
