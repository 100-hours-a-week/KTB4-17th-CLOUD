"""Environment boundaries and bounded dev adoption safety regressions."""
import copy
import json
import re
import subprocess
import shutil
import tempfile
import unittest
from pathlib import Path
from scripts.check_readonly_plan import audit

ROOT = Path(__file__).resolve().parents[1]


class EnvironmentSeparationTests(unittest.TestCase):
    def test_roots_use_only_environment_local_modules(self):
        self.assertFalse(list((ROOT / "terraform").glob("*.tf")))
        for obsolete in ("modules", "environments", "cloudwatch-loki"):
            self.assertFalse((ROOT / "terraform" / obsolete).exists())
        for env in ("dev", "prod"):
            root = ROOT / "terraform" / env
            self.assertFalse((root / "modules").exists())
            for name in ("vpc", "subnet", "routetable"):
                self.assertTrue((root / "network" / name).is_dir())
            for f in root.rglob("*.tf"):
                if ".terraform" in f.parts:
                    continue
                for source in re.findall(r'source\s*=\s*"([.][^"\n]+)"', f.read_text()):
                    target = (f.parent / source).resolve()
                    self.assertTrue(target.is_dir())
                    self.assertIn(root.resolve(), target.parents)
        self.assertIn('source = "./forwarder"',
                      (ROOT / "terraform/prod/cloudwatch-loki/main.tf").read_text())

    def test_dev_graph_has_only_bounded_ec2_ownership(self):
        # A fresh checkout needs no dev backend access to exercise ownership.
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "dev"
            shutil.copytree(ROOT / "terraform/dev", folder,
                            ignore=shutil.ignore_patterns(".terraform"))
            (folder / "backend.tf").unlink()
            (folder / ".terraform").mkdir()
            cache = ROOT / "terraform/dev/.terraform/providers"
            if cache.is_dir():
                (folder / ".terraform/providers").symlink_to(cache, target_is_directory=True)
            subprocess.run(["terraform", f"-chdir={folder}", "init", "-backend=false", "-input=false",
                            "-lockfile=readonly"], capture_output=True, text=True, check=True)
            result = subprocess.run(["terraform", f"-chdir={folder}", "graph", "-type=plan"],
                                    capture_output=True, text=True, check=True)
        owned = {a for a in re.findall(r'\[root\] (module\.[^\s]+\.aws_\w+\.\w+) \(expand\)', result.stdout) if ".data.aws_" not in a}
        self.assertEqual(owned, {"module.ec2.aws_instance.app", "module.ec2.aws_instance.messaging", "module.database.aws_instance.data"})
        source = "\n".join(p.read_text() for folder in ("ec2", "database") for p in (ROOT / "terraform/dev" / folder).glob("*.tf"))
        self.assertNotIn("ignore_changes", source)
        self.assertNotIn('resource "aws_security_group', source)
        self.assertNotIn('resource "aws_route', source)

    def test_dev_adoption_rejects_missing_extra_wrong_and_unknown_ids(self):
        imports = {("module.database" if n == "data" else "module.ec2") + ".aws_instance." + n: "i-fixture-" + n for n in ("app", "data", "messaging")}
        manifest = {"imports": imports, "moves": {}, "forget": {}}
        changes = [{"address": a, "mode": "managed", "change": {
            "actions": ["no-op"], "importing": {"id": i}, "after": {"id": i},
        }} for a, i in imports.items()]
        plan = {"complete": True, "errored": False, "resource_changes": changes}
        self.assertEqual(audit(plan, manifest)["imports"], 3)
        mutations = []
        missing = copy.deepcopy(plan); missing["resource_changes"].pop(); mutations.append(missing)
        extra = copy.deepcopy(plan); extra["resource_changes"].append({
            "address": "module.ec2.aws_instance.gpu", "change": {
                "actions": ["no-op"], "importing": {"id": "i-unapproved"}, "after": {"id": "i-unapproved"}}})
        mutations.append(extra)
        for field, value in (("after", {"id": "i-wrong"}), ("after_unknown", {"id": True}),
                             ("actions", ["update"]), ("actions", ["delete", "create"])):
            changed = copy.deepcopy(plan); changed["resource_changes"][0]["change"][field] = value
            mutations.append(changed)
        for changed in mutations:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                audit(changed, manifest)
        with self.assertRaises(ValueError):
            audit(plan)
