from pathlib import Path
import os
import re
import subprocess
import unittest


class GroovyPolicyTest(unittest.TestCase):
    def run_script(self, name):
        root = Path(__file__).resolve().parents[1]
        configured = os.environ.get("GROOVY_JAR")
        jars = [Path(configured)] if configured else sorted(
            (Path.home() / ".gradle/wrapper/dists").glob("*/**/lib/groovy-[0-9]*.jar"),
            key=lambda p: tuple(map(int, re.search(r"groovy-(\d+)\.(\d+)\.(\d+)", p.name).groups())), reverse=True)
        if not jars:
            self.skipTest("Set GROOVY_JAR to run the independent Groovy policy checks")
        modules = [jars[0]] + list(jars[0].parent.glob("groovy-json-*.jar")) + list(jars[0].parent.glob("groovy-xml-*.jar"))
        result = subprocess.run(["java", "-cp", os.pathsep.join(map(str, modules)), "groovy.ui.GroovyMain",
                                 str(root / "tests" / name), str(root)],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_real_groovy_policy_behavior(self):
        result = self.run_script("test_coordinator_policy.groovy")
        self.assertIn("checks passed", result)

    def test_real_pipeline_flow_handles_four_profiles_and_producer_failures(self):
        result = self.run_script("test_pipeline_flow.groovy")
        self.assertIn("flow checks passed", result)

    def test_actual_snapshot_run_requires_scm_source_and_legacy_branch_proof(self):
        result = self.run_script("test_snapshot_run.groovy")
        self.assertIn("Snapshot checks passed", result)

    def test_bootstrap_requires_enabled_job_and_exact_trigger_properties(self):
        result = self.run_script("test_bootstrap_verification.groovy")
        self.assertIn("Bootstrap verification checks passed", result)

    def test_pipeline_installer_and_bootstrap_syntax(self):
        result = self.run_script("test_pipeline_compile.groovy")
        self.assertIn("syntax passed", result)

    def test_installer_reapply_preserves_other_properties_and_replaces_triggers(self):
        result = self.run_script("test_installer_reapply.groovy")
        self.assertIn("reapply checks passed", result)


if __name__ == "__main__":
    unittest.main()
