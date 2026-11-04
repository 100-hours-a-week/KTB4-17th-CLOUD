"""Repository safety contracts for the service-module code stage."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "terraform/prod"


class SourceContractTests(unittest.TestCase):
    def test_direct_service_resource_visibility(self):
        for service in ("be", "ws", "ai"):
            folder = ROOT / "ecs/service" / service
            with self.subTest(service=service):
                self.assertIn('resource "aws_security_group"', (folder / "security.tf").read_text())
                self.assertIn('resource "aws_iam_role"', (folder / "iam.tf").read_text())
                self.assertIn('resource "aws_cloudwatch_log_group"', (folder / "logs.tf").read_text())
                self.assertTrue((folder / "configuration.tf").is_file())
                self.assertNotIn('module "runtime"', "\n".join(p.read_text() for p in folder.glob("*.tf")))
        self.assertFalse((ROOT / "modules/ecs/runtime").exists())

    def test_steady_source_has_no_reconciliation_blocks(self):
        sources = [p for p in ROOT.parent.rglob("*.tf") if ".terraform" not in p.parts]
        self.assertTrue(sources)
        for path in sources:
            with self.subTest(path=path.relative_to(ROOT.parent)):
                self.assertIsNone(re.search(r"^\s*(import|moved|removed)\s*\{", path.read_text(), re.MULTILINE))

    def test_backend_identities_remain_separate(self):
        for path, key in ((ROOT.parent / "dev", "dev/terraform.tfstate"), (ROOT, "prod/terraform.tfstate"), (ROOT / "cloudwatch-loki", "prod/cloudwatch-loki/terraform.tfstate")):
            with self.subTest(path=path):
                source = (path / "backend.tf").read_text()
                self.assertIn('bucket       = "star23-tfstate-975779326240"', source)
                self.assertRegex(source, rf'key\s*=\s*"{re.escape(key)}"')

    def test_ci_retains_service_revision_ownership(self):
        for service in ("be", "ws", "ai"):
            with self.subTest(service=service):
                source = (ROOT / "ecs/service" / service / "main.tf").read_text()
                service_block = re.search(r'resource "aws_ecs_service"[^\n]*\{(.*?)^\}', source, re.MULTILINE | re.DOTALL)
                self.assertIsNotNone(service_block)
                self.assertRegex(service_block[1], r'ignore_changes\s*=\s*\[task_definition\]')


if __name__ == "__main__":
    unittest.main()
