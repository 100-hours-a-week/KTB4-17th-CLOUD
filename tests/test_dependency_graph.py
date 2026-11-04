"""Check Terraform's actual plan graph, independent of existing state or AWS.

Run `terraform -chdir=terraform/prod init -input=false` first in a
fresh checkout. Graph construction does not refresh resources or plan AWS writes.
"""

import re
import json
import shutil
import tempfile
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


RULES = {
    "be": ("aws_vpc_security_group_egress_rule.alb_to_app", "aws_vpc_security_group_ingress_rule.app_from_alb",
           "aws_vpc_security_group_ingress_rule.mysql_from_app", "aws_vpc_security_group_ingress_rule.postgres_from_app",
           "aws_vpc_security_group_ingress_rule.ai_from_be"),
    "ws": ("aws_vpc_security_group_ingress_rule.ws_from_alb", "aws_vpc_security_group_egress_rule.alb_to_ws",
           "aws_vpc_security_group_ingress_rule.ai_from_ws", "aws_vpc_security_group_ingress_rule.additional_ecs_database"),
    "ai": ("aws_vpc_security_group_ingress_rule.ai_from_be", "aws_vpc_security_group_ingress_rule.ai_from_ws",
           "aws_vpc_security_group_ingress_rule.additional_ecs_database"),
}


def assert_network_order(test, graph):
    assert_order(test, graph)
    alb_output = node("module.alb.output.alb_security_group_id")
    for rule in ("alb_http", "alb_https"):
        prerequisite = node(f"module.alb.aws_vpc_security_group_ingress_rule.{rule}")
        test.assertIn(prerequisite, dependencies(graph, alb_output))
        test.assertIn(prerequisite, dependencies(graph, node("module.alb.aws_alb.main")))
    for service, rules in RULES.items():
        ecs = node(f"module.{service}.aws_ecs_service.{service}")
        token = node(f"module.{service}.var.traffic_rule_ids")
        test.assertIn(token, dependencies(graph, ecs))
        for rule in (*rules, "aws_vpc_security_group_ingress_rule.v1_database_from_ecs"):
            # Check the service's own input, even where BE -> AI provides a second path.
            test.assertIn(node(rule), dependencies(graph, token), (service, rule))
        outbound = "app_outbound_rule" if service == "be" else "outbound"
        test.assertIn(node(f"module.{service}.aws_vpc_security_group_egress_rule.{outbound}"), dependencies(graph, ecs))
        for current in graph:
            if current.startswith(f"[root] module.{service}.") and ".aws_" in current and current != ecs:
                test.assertNotIn(token, dependencies(graph, current), current)
        for other in ("be", "ws", "ai"):
            if other != service:
                test.assertNotIn(node(f"module.{other}.aws_ecs_service.{other}"), dependencies(graph, token))
    # WS never had a dependency on the HTTP listener or AI service readiness.
    ws_dependencies = dependencies(graph, node("module.ws.aws_ecs_service.ws"))
    test.assertNotIn(node("module.alb.aws_lb_listener.http"), ws_dependencies)
    test.assertNotIn(node("module.ai.aws_ecs_service.ai"), ws_dependencies)
    # The network output must not regain cross-owner rules (which would cycle).
    for rules in RULES.values():
        for rule in rules:
            test.assertNotIn(node(rule), dependencies(graph, alb_output))


class DependencyGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["terraform", "-chdir=terraform/prod", "graph", "-type=plan"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        cls.graph = {}
        for source, target in re.findall(r'^\s*"(.+?)" -> "(.+?)"', result.stdout, re.MULTILINE):
            cls.graph.setdefault(source, set()).add(target)

    def test_secret_version_then_ai_then_only_be_service(self):
        assert_order(self, self.graph)
        for service in ("ai", "be"):
            source = (ROOT / f"terraform/prod/ecs/service/{service}/main.tf").read_text()
            self.assertRegex(source, r"wait_for_steady_state\s*=\s*true")
        self.assertIn("healthCheck =", (ROOT / "terraform/prod/ecs/service/ai/main.tf").read_text())

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


    def test_nested_network_readiness_is_reachable(self):
        required = {
            "module.alb.aws_alb.main": (
                "module.network.module.vpc.aws_internet_gateway.main",
                "module.network.module.routetable.aws_route.public_internet",
                "module.network.module.routetable.aws_route_table_association.public",
            ),
            "module.be.aws_ecs_service.be": (
                "module.network.module.routetable.aws_route.app_nat",
                "module.network.module.routetable.aws_route_table_association.application",
                "module.network.aws_route.application_to_v1_database",
                "module.network.aws_route.v1_database_to_application",
            ),
            "module.database.aws_db_subnet_group.postgres": (
                "module.network.module.routetable.aws_route_table_association.data",
            ),
            "module.database.aws_db_subnet_group.mysql": (
                "module.network.module.routetable.aws_route_table_association.data",
            ),
        }
        for dependent, prerequisites in required.items():
            for prerequisite in prerequisites:
                with self.subTest(dependent=dependent, prerequisite=prerequisite):
                    self.assertIn(node(prerequisite), dependencies(self.graph, node(dependent)))

    def test_network_readiness_on_service_nodes_only(self):
        assert_network_order(self, self.graph)

    def test_each_missing_network_gate_is_rejected(self):
        gates = [
            (node("module.be.aws_ecs_service.be"), node("module.be.aws_vpc_security_group_egress_rule.app_outbound_rule")),
            *((node("module.alb.output.alb_security_group_id"), node(f"module.alb.aws_vpc_security_group_ingress_rule.{rule}")) for rule in ("alb_http", "alb_https")),
        ]
        for service, rules in RULES.items():
            token = node(f"module.{service}.var.traffic_rule_ids")
            gates.append((node(f"module.{service}.aws_ecs_service.{service}"), token))
            gates.extend((token, node(rule)) for rule in (*rules, "aws_vpc_security_group_ingress_rule.v1_database_from_ecs"))
        for source, target in gates:
            with self.subTest(source=source, target=target):
                self.assertIn(target, self.graph[source])
                broken = {key: set(value) for key, value in self.graph.items()}
                broken[source].remove(target)
                with self.assertRaises(AssertionError):
                    assert_network_order(self, broken)

    def test_actual_graph_rejects_source_regression(self):
        # Regenerate real graphs from each regressed source category, as well as
        # testing every individual edge above. No backend or AWS writes occur.
        mutations = [
            ("ecs/service/be/main.tf", ", aws_vpc_security_group_egress_rule.app_outbound_rule", ""),
            ("alb/outputs.tf", "    aws_vpc_security_group_ingress_rule.alb_http,", ""),
            ("alb/outputs.tf", "    aws_vpc_security_group_ingress_rule.alb_https,", ""),
            *((f"ecs/service/{service}/main.tf", ", var.traffic_rule_ids", "") for service in RULES),
        ]
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "terraform/prod"
            shutil.copytree(ROOT / "terraform/prod", copy, ignore=shutil.ignore_patterns(".terraform", "dist"))
            (copy / ".terraform").symlink_to(ROOT / "terraform/prod/.terraform", target_is_directory=True)
            for relative, before, after in mutations:
                with self.subTest(source=relative, removed=before):
                    path = copy / relative
                    original = path.read_text()
                    self.assertIn(before, original)
                    path.write_text(original.replace(before, after))
                    try:
                        result = subprocess.run(["terraform", f"-chdir={copy}", "graph", "-type=plan"],
                                                capture_output=True, text=True, check=True)
                        broken = {}
                        for source, target in re.findall(r'^\s*"(.+?)" -> "(.+?)"', result.stdout, re.MULTILINE):
                            broken.setdefault(source, set()).add(target)
                        with self.assertRaises(AssertionError):
                            assert_network_order(self, broken)
                    finally:
                        path.write_text(original)

    def test_conditional_rule_tokens_empty_and_per_service(self):
        # Evaluate the actual root token expressions using Terraform, with independent
        # fixture IDs. Cover absent V1, every WS/AI DB subset, and both DB types.
        source = (ROOT / "terraform/prod/main.tf").read_text()
        expressions = {}
        for service in RULES:
            block = source.split(f'module "{service}" {{', 1)[1].split("\n}", 1)[0]
            expressions[service] = block.split("traffic_rule_ids = ", 1)[1].strip()
        cases = []
        expected = []
        for v1 in (False, True):
            for ws in ([], ["mysql"], ["postgres"], ["mysql", "postgres"]):
                for ai in ([], ["mysql"], ["postgres"], ["mysql", "postgres"]):
                    metadata = {f"{service}-{db}": {"service": service} for service, dbs in (("ws", ws), ("ai", ai)) for db in dbs}
                    v1_metadata = {"be-mysql": {"service": "be"}, **metadata} if v1 else {}
                    for service, expression in expressions.items():
                        values = {"local.additional_ecs_database_rules": metadata, "local.v1_database_ingress_rules": v1_metadata}
                        for collection, rules in (("additional_ecs_database", metadata), ("v1_database_from_ecs", v1_metadata)):
                            values[f"aws_vpc_security_group_ingress_rule.{collection}"] = {key: {"id": f"{collection}:{key}"} for key in rules}
                        for rules in RULES.values():
                            for rule in rules:
                                if not rule.endswith(".additional_ecs_database"):
                                    values[rule + ".id"] = rule
                        for key in sorted(values, key=len, reverse=True):
                            expression = expression.replace(key, json.dumps(values[key]))
                        cases.append(expression)
                        expected.append([r for r in RULES[service] if not r.endswith(".additional_ecs_database")] +
                                        [f"additional_ecs_database:{key}" for key in sorted(metadata) if metadata[key]["service"] == service] +
                                        [f"v1_database_from_ecs:{key}" for key in sorted(v1_metadata) if v1_metadata[key]["service"] == service])
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(["terraform", f"-chdir={directory}", "console"],
                                    input="jsonencode([" + ",".join(cases).replace("\n", " ") + "])\n",
                                    capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(json.loads(result.stdout)), expected)

    def test_network_proof_rejects_module_wide_gates_and_cycles(self):
        for service in RULES:
            broken = {key: set(value) for key, value in self.graph.items()}
            broken.setdefault(f"[root] module.{service} (expand)", set()).add(node(f"module.{service}.var.traffic_rule_ids"))
            with self.subTest(service=service), self.assertRaises(AssertionError):
                assert_network_order(self, broken)
        broken = {key: set(value) for key, value in self.graph.items()}
        broken[node("module.be.aws_security_group.app")].add(node("module.be.aws_ecs_service.be"))
        with self.assertRaises(AssertionError):
            assert_network_order(self, broken)
