"""Repository safety contracts for the service-module code stage."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "terraform"


class SourceContractTests(unittest.TestCase):
    def test_steady_source_has_no_reconciliation_blocks(self):
        sources = [p for p in ROOT.rglob("*.tf") if ".terraform" not in p.parts]
        self.assertTrue(sources)
        for path in sources:
            with self.subTest(path=path.relative_to(ROOT)):
                self.assertIsNone(re.search(r"^\s*(import|moved|removed)\s*\{", path.read_text(), re.MULTILINE))

    def test_backend_identities_remain_separate(self):
        for path, key in ((ROOT, "prod/terraform.tfstate"), (ROOT / "cloudwatch-loki", "prod/cloudwatch-loki/terraform.tfstate")):
            with self.subTest(path=path):
                source = (path / "backend.tf").read_text()
                self.assertIn('bucket       = "star23-tfstate-975779326240"', source)
                self.assertRegex(source, rf'key\s*=\s*"{re.escape(key)}"')

    def test_ci_retains_service_revision_ownership(self):
        for service in ("be", "ws", "ai"):
            with self.subTest(service=service):
                source = (ROOT / "modules/ecs/services" / service / "main.tf").read_text()
                service_block = re.search(r'resource "aws_ecs_service"[^\n]*\{(.*?)^\}', source, re.MULTILINE | re.DOTALL)
                self.assertIsNotNone(service_block)
                self.assertRegex(service_block[1], r'ignore_changes\s*=\s*\[task_definition\]')


if __name__ == "__main__":
    unittest.main()
