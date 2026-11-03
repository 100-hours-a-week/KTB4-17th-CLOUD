"""Check Terraform's actual plan graph, independent of existing state or AWS.

Run `terraform -chdir=terraform init -backend=false -input=false` first in a
fresh checkout. Graph construction does not refresh resources or plan AWS writes.
"""

import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def dependencies(graph, node):
    visited = set()
    pending = list(graph.get(node, ()))
    while pending:
        current = pending.pop()
        if current not in visited:
            visited.add(current)
            pending.extend(graph.get(current, ()))
    return visited


def node(address):
    return f"[root] {address} (expand)"


def assert_order(test, graph):
    secret = node("module.be.aws_secretsmanager_secret.be")
    version = node("module.be.aws_secretsmanager_secret_version.be")
    ai_task = node("module.ai.aws_ecs_task_definition.ai")
    ai = node("module.ai.aws_ecs_service.ai")
    be = node("module.be.aws_ecs_service.be")
    for dependent, prerequisite in ((version, secret), (ai_task, version), (ai, ai_task), (be, ai)):
        test.assertIn(prerequisite, dependencies(graph, dependent), (dependent, prerequisite))
    for current in graph:
        test.assertNotIn(current, dependencies(graph, current), f"Cycle at {current}")
        if current.startswith("[root] module.be.") and ".aws_" in current and current != be:
            test.assertNotIn(ai, dependencies(graph, current), f"BE infrastructure waits for AI: {current}")


class DependencyGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["terraform", "-chdir=terraform", "graph", "-type=plan"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        cls.graph = {}
        for source, target in re.findall(r'^\s*"(.+?)" -> "(.+?)"', result.stdout, re.MULTILINE):
            cls.graph.setdefault(source, set()).add(target)

    def test_secret_version_then_ai_then_only_be_service(self):
        assert_order(self, self.graph)
        for service in ("ai", "be"):
            source = (ROOT / f"terraform/modules/ecs/services/{service}/main.tf").read_text()
            self.assertRegex(source, r"wait_for_steady_state\s*=\s*true")
        self.assertIn("healthCheck =", (ROOT / "terraform/modules/ecs/services/ai/main.tf").read_text())

    def test_regression_proof_rejects_missing_edges_and_module_wide_gate(self):
        for address in ("module.ai.var.backend_config_references", "module.be.var.ai_service_name"):
            broken = {key: set(value) for key, value in self.graph.items()}
            broken[node(address)] = set()
            with self.subTest(address=address), self.assertRaises(AssertionError):
                assert_order(self, broken)
        broken = {key: set(value) for key, value in self.graph.items()}
        broken.setdefault("[root] module.be (expand)", set()).add(node("module.ai.aws_ecs_service.ai"))
        with self.assertRaises(AssertionError):
            assert_order(self, broken)

