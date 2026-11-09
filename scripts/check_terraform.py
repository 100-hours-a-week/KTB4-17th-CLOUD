#!/usr/bin/env python3
"""Offline acceptance suite. Only init/validate/test/plan/show; never apply or AWS calls.

The handoff fixture copies production removed/moved blocks and service definitions,
resolves infra references to fixed fixture IDs, then plans against synthetic state.
Production modules themselves are also planned in full with Terraform's mock AWS.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
AWS = 'registry.terraform.io/hashicorp/aws'
ENV = dict(os.environ, AWS_ACCESS_KEY_ID='offline-fixture', AWS_SECRET_ACCESS_KEY='offline-fixture',
           AWS_EC2_METADATA_DISABLED='true', AWS_PROFILE='', AWS_CONFIG_FILE='/dev/null',
           AWS_SHARED_CREDENTIALS_FILE='/dev/null', CHECKPOINT_DISABLE='1')


def run(args, cwd=ROOT, success=True):
    p = subprocess.run(args, cwd=cwd, env=ENV, text=True, timeout=120, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if success and p.returncode:
        details = '\n'.join(line for line in p.stdout.splitlines() if '"type":"test_plan"' not in line)
        raise AssertionError(f'{args}:\n{details[-14000:]}')
    return p


def blocks(text, prefix):
    """Extract top-level HCL blocks (opening/closing braces begin at column zero)."""
    return re.findall(r'(?ms)^' + prefix + r'[^\n]*\{\n.*?^\}', text)


class OwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plans = {}
        for root in ('dev', 'prod', 'prod/cloudwatch'):
            path = ROOT / 'terraform' / root
            run(['terraform', 'init', '-backend=false', '-input=false', '-lockfile=readonly'], path)
            run(['terraform', 'validate', '-no-color'], path)
            result = run(['terraform', 'test', '-no-color', '-verbose', '-json'], path)
            events = [json.loads(line) for line in result.stdout.splitlines()]
            summary = next(e['test_summary'] for e in events if e['type'] == 'test_summary')
            if summary['status'] != 'pass' or not summary['passed']:
                raise AssertionError(summary)
            print(f'{root}: init/validate passed; {summary["passed"]} Terraform plan tests passed', flush=True)
            for event in events:
                if event['type'] == 'test_plan':
                    plan = event['test_plan']
                    schemas = plan.pop('provider_schemas')[AWS]['resource_schemas']
                    if not hasattr(cls, 'schema'):
                        types = {'aws_ecs_service', 'aws_ecs_task_definition', 'aws_lambda_function', 'aws_lambda_function_event_invoke_config', 'aws_ssm_parameter', 'aws_secretsmanager_secret_version'}
                        cls.schema = {key: value for key, value in schemas.items() if key in types}
                    cls.plans[event['@testrun']] = plan

    def test_full_roots_bootstrap_and_external_references(self):
        forbidden = {'aws_ecs_task_definition', 'aws_ssm_parameter', 'aws_secretsmanager_secret_version', 'aws_lambda_function', 'aws_ssm_parameters_by_path', 'aws_ssm_parameters'}
        for name, plan in self.plans.items():
            for r in plan['resource_changes']:
                self.assertNotIn('delete', r['change']['actions'], (name, r['address']))
                self.assertNotIn(r['type'], forbidden, (name, r['address']))
                if r['type'] == 'aws_ecs_service':
                    self.assertEqual(r['change']['after']['desired_count'], 0)
                    self.assertIn(':task-definition/star23-', r['change']['after']['task_definition'])
        for name in ('fresh_infrastructure', 'fresh_logging_infrastructure'):
            banned = {'aws_ecs_service', 'aws_lambda_permission', 'aws_cloudwatch_log_subscription_filter', 'aws_lambda_function_event_invoke_config'}
            self.assertFalse(any(r['type'] in banned for r in self.plans[name]['resource_changes']))
        shell = self.plans['external_task_service_shells']['resource_changes']
        self.assertEqual(sum(r['type'] == 'aws_ecs_service' for r in shell), 3)
        required = {'aws_vpc', 'aws_subnet', 'aws_route_table', 'aws_nat_gateway', 'aws_security_group',
                    'aws_alb', 'aws_lb_target_group', 'aws_db_instance', 'aws_s3_bucket', 'aws_ecr_repository',
                    'aws_iam_role', 'aws_secretsmanager_secret', 'aws_cloudwatch_log_group', 'aws_ecs_cluster'}
        self.assertTrue(required <= {r['type'] for r in shell})
        resources = {r['address']: r['change']['after'] for r in shell}
        def statements(resources, address):
            return json.loads(resources[address]['policy'])['Statement']
        be = statements(resources, 'module.be.aws_iam_role_policy.ecs_execution_secrets[0]')
        self.assertEqual(be[0]['Resource'], ['arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/be/DB_URL'])
        self.assertEqual(set(be[1]['Resource']), {
            'arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:external-abcdef',
            'arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/be-abcdef'})
        ai = statements(resources, 'module.ai.aws_iam_role_policy.service_execution_secrets["ai"]')
        self.assertEqual(set(ai[0]['Resource']), {
            'arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:ai-abcdef',
            'arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:other-abcdef'})
        ws = statements(resources, 'module.ws.aws_iam_role_policy.service_execution_secrets["ws"]')
        self.assertEqual({s['Resource'] for s in ws}, set(be[0]['Resource'] + be[1]['Resource']))
        for svc in ('be', 'ws'):
            address = ('module.be.aws_iam_role_policy.ecs_execution_secret_kms[0]' if svc == 'be'
                       else 'module.ws.aws_iam_role_policy.service_execution_secret_kms["ws"]')
            self.assertEqual(statements(resources, address)[0]['Resource'],
                             ['arn:aws:kms:ap-northeast-2:975779326240:key/be-fixture'])
        optional = self.plans['ws_disabled']['resource_changes']
        self.assertEqual(sum(r['type'] == 'aws_ecs_service' for r in optional), 2)
        self.assertFalse(any(r['address'].startswith('module.ws.aws_iam_role.') for r in optional))
        independent = {r['address']: r['change']['after'] for r in
                       self.plans['independent_ws_and_ai_parameter_access']['resource_changes']}
        ws = statements(independent, 'module.ws.aws_iam_role_policy.service_execution_secrets["ws"]')
        self.assertEqual(ws, [{'Effect': 'Allow', 'Action': ['secretsmanager:GetSecretValue'],
                              'Resource': 'arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:ws-abcdef'}])
        self.assertNotIn('module.ws.aws_iam_role_policy.ws_s3[0]', independent)
        ai = statements(independent, 'module.ai.aws_iam_role_policy.service_execution_secrets["ai"]')
        self.assertEqual(ai[0]['Action'], ['ssm:GetParameters'])
        self.assertEqual(ai[0]['Resource'], 'arn:aws:ssm:ap-northeast-2:975779326240:parameter/external/ai/setting')
        self.assertEqual(ai[1]['Resource'], ['arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:other-abcdef'])
        logging = self.plans['external_function_connections']['resource_changes']
        self.assertEqual(sum(r['type'] == 'aws_cloudwatch_log_subscription_filter' for r in logging), 3)
        for r in logging:
            if r['type'] == 'aws_cloudwatch_log_subscription_filter':
                self.assertEqual(r['change']['after']['destination_arn'], 'arn:aws:lambda:ap-northeast-2:975779326240:function:star23-prod-cloudwatch-loki')

    def test_existing_state_handoff_and_live_scaling_preservation(self):
        # This is fabricated, public fixture data, never production state.
        with tempfile.TemporaryDirectory(prefix='ktb-handoff-') as tmp:
            path = Path(tmp)
            shutil.copy(ROOT / 'terraform/prod/.terraform.lock.hcl', path)
            header = '''terraform {
  required_version = ">= 1.11.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.0" } }
}
provider "aws" {
  region = "ap-northeast-2"
  skip_credentials_validation = true
  skip_requesting_account_id = true
  skip_metadata_api_check = true
  skip_region_validation = true
  max_retries = 0
  endpoints {
    sts = "http://127.0.0.1:9"
    ecs = "http://127.0.0.1:9"
    lambda = "http://127.0.0.1:9"
    ssm = "http://127.0.0.1:9"
    secretsmanager = "http://127.0.0.1:9"
  }
}
'''
            root = header
            old = []
            expected_forgotten = set()
            services = set()
            def state(module, typ, name, attrs, key=None):
                inst = {'schema_version': self.schema[typ]['version'], 'attributes': attrs, 'sensitive_attributes': []}
                if key is not None:
                    inst['index_key'] = key
                existing = next((r for r in old if r['module'] == 'module.' + module and r['type'] == typ and r['name'] == name), None)
                if existing:
                    existing['instances'].append(inst)
                else:
                    old.append({'module': 'module.' + module, 'mode': 'managed', 'type': typ, 'name': name,
                                'provider': 'provider["' + AWS + '"]', 'instances': [inst]})
            for svc in ('be', 'ai', 'ws'):
                source = ROOT / f'terraform/prod/ecs/service/{svc}'
                text = (source / 'main.tf').read_text()
                content = '\n'.join(blocks(text, '(?:removed|moved)') + blocks(text, 'resource "aws_ecs_service"'))
                # Substitute infrastructure references only; preserve service lifecycle and all options.
                values = {'name_prefix': 'star23', 'environment': 'prod', 'cluster_id': 'arn:aws:ecs:ap-northeast-2:975779326240:cluster/star23-ecs-cluster',
                          'namespace_arn': 'arn:aws:servicediscovery:ap-northeast-2:975779326240:namespace/ns-1234567890abcdef',
                          'subnet_ids': ['subnet-0123456789abcdef0'], 'services_enabled': True, 'ws_enabled': True,
                          'ws_use_backend_config': True, 'task_definition_arn': f'arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-{svc}:42',
                          'be_target_group_arn': 'arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:targetgroup/be/0123456789abcdef',
                          'ws_target_group_arn': 'arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:targetgroup/ws/0123456789abcdef'}
                content = re.sub(r'^\s*depends_on\s*=.*$', '', content, flags=re.M)
                content = re.sub(r'var\.(\w+)', lambda m: 'var.task_definition_arn' if m[1] == 'task_definition_arn' else json.dumps(values[m[1]]), content)
                content += '\nvariable "task_definition_arn" { default = ' + json.dumps(values['task_definition_arn']) + ' }\n'
                locals_ = {'app_port': 8080, 'ws_port': 8080, 'ai_port': 8000, 'ai_request_timeout_seconds': 150}
                content = re.sub(r'local\.(\w+)', lambda m: str(locals_[m[1]]), content)
                content = re.sub(r'aws_security_group\.(?:app|service)\.id', '"sg-0123456789abcdef0"', content)
                if svc == 'be':
                    content += '\n' + '\n'.join(blocks((source / 'configuration.tf').read_text(), 'removed'))
                mod = path / svc; mod.mkdir(); (mod / 'main.tf').write_text(content)
                root += f'\nmodule "{svc}" {{ source = "./{svc}" }}\n'
                expected_forgotten.add(f'module.{svc}.aws_ecs_task_definition.{svc}' + ('[0]' if svc == 'ws' else ''))
                state(svc, 'aws_ecs_task_definition', svc, {'id': f'star23-{svc}', 'arn': values['task_definition_arn'], 'family': f'star23-{svc}', 'revision': 42, 'container_definitions': '[]'}, 0 if svc == 'ws' else None)
                services.add(f'module.{svc}.aws_ecs_service.{svc}[0]')
            forwarder = ROOT / 'terraform/prod/cloudwatch/forwarder/main.tf'
            mod = path / 'logging'; mod.mkdir()
            logging_content = '\n'.join(blocks(forwarder.read_text(), '(?:removed|moved)') + blocks(forwarder.read_text(), 'resource "aws_lambda_function_event_invoke_config"'))
            logging_content = logging_content.replace('var.enable_function_connections', 'true').replace('var.name', '"star23-prod-cloudwatch-loki"')
            (mod / 'main.tf').write_text(logging_content)
            services.add('module.cloudwatch_loki.aws_lambda_function_event_invoke_config.forwarder[0]')
            root += '\nmodule "cloudwatch_loki" { source = "./logging" }\n'
            state('cloudwatch_loki', 'aws_lambda_function', 'forwarder', {'id': 'star23-prod-cloudwatch-loki', 'function_name': 'star23-prod-cloudwatch-loki'})
            expected_forgotten.add('module.cloudwatch_loki.aws_lambda_function.forwarder')
            state('be', 'aws_ssm_parameter', 'be_config', {'id': '/star23/prod/be/DB_URL', 'name': '/star23/prod/be/DB_URL', 'type': 'String', 'value': 'synthetic-fixture-only'}, 'DB_URL')
            expected_forgotten.add('module.be.aws_ssm_parameter.be_config["DB_URL"]')
            state('be', 'aws_ssm_parameter', 'be_config', {'id': '/star23/prod/be/ANY_SETTING', 'name': '/star23/prod/be/ANY_SETTING', 'type': 'String', 'value': 'synthetic'}, 'ANY_SETTING')
            expected_forgotten.add('module.be.aws_ssm_parameter.be_config["ANY_SETTING"]')
            state('be', 'aws_secretsmanager_secret_version', 'be', {'id': 'synthetic|version', 'secret_id': 'synthetic', 'version_id': 'version'})
            expected_forgotten.add('module.be.aws_secretsmanager_secret_version.be')
            (path / 'main.tf').write_text(root)
            run(['terraform', 'init', '-backend=false', '-input=false', '-lockfile=readonly', '-plugin-dir=' + str(ROOT / 'terraform/prod/.terraform/providers')], path)
            run(['terraform', 'plan', '-refresh=false', '-input=false', '-lock=false', '-out=fresh.tfplan'], path)
            fresh = json.loads(run(['terraform', 'show', '-json', 'fresh.tfplan'], path).stdout)
            for module in fresh['planned_values']['root_module']['child_modules']:
                for r in module.get('resources', []):
                    if r['type'] == 'aws_lambda_function_event_invoke_config':
                        attrs = r['values']
                        attrs['id'] = 'star23-prod-cloudwatch-loki'
                        state('cloudwatch_loki', r['type'], 'forwarder', attrs)
                        continue
                    if r['type'] != 'aws_ecs_service': continue
                    attrs = r['values']
                    attrs.update(id=attrs['cluster'] + '/' + attrs['name'], triggers={}, desired_count=5,
                                 task_definition=attrs['task_definition'].rsplit(':', 1)[0] + ':99')
                    svc = module['address'].split('.')[1]
                    # AWS Read normalizes this optional/computed Service Connect port to zero.
                    if svc == 'ai':
                        attrs['service_connect_configuration'][0]['service'][0]['ingress_port_override'] = 0
                    state(svc, 'aws_ecs_service', svc, attrs, 0 if svc == 'ws' else None)
            (path / 'fixture.tfstate').write_text(json.dumps({'version': 4, 'terraform_version': '1.11.0', 'serial': 1,
                'lineage': '00000000-0000-0000-0000-000000000019', 'outputs': {}, 'resources': old}))
            run(['terraform', 'plan', '-refresh=false', '-input=false', '-lock=false', '-state=fixture.tfstate', '-out=handoff.tfplan'], path)
            plan = json.loads(run(['terraform', 'show', '-json', 'handoff.tfplan'], path).stdout)
            changes = {r['address']: r['change'] for r in plan['resource_changes']}
            self.assertEqual({a for a, c in changes.items() if c['actions'] == ['forget']}, expected_forgotten)
            self.assertEqual(set(changes) - expected_forgotten, services)
            for a in services:
                self.assertEqual(changes[a]['actions'], ['no-op'], (a, {k: (changes[a]['before'].get(k), v) for k, v in changes[a]['after'].items() if changes[a]['before'].get(k) != v}, changes[a].get('after_unknown')))
                if 'aws_ecs_service' in a:
                    self.assertEqual(changes[a]['after']['desired_count'], 5)
                    self.assertTrue(changes[a]['after']['task_definition'].endswith(':99'))
            # Removal protection must reject disabling existing service shells.
            for svc in ('be', 'ai', 'ws'):
                f = path / svc / 'main.tf'
                f.write_text(re.sub(r'count\s*= true(?: && true)? \? 1 : 0', 'count = 0', f.read_text()))
            result = run(['terraform', 'plan', '-refresh=false', '-input=false', '-lock=false', '-state=fixture.tfstate'], path, success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('prevent_destroy', result.stdout)
            for svc in ('be', 'ai', 'ws'):
                f = path / svc / 'main.tf'
                content = re.sub(r'count\s*= 0', 'count = 1', f.read_text())
                content = re.sub(r'(variable "task_definition_arn" \{ default = )"[^"]+"', r'\1null', content)
                f.write_text(content)
            result = run(['terraform', 'plan', '-refresh=false', '-input=false', '-lock=false'], path, success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Supply an externally registered task definition ARN', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
