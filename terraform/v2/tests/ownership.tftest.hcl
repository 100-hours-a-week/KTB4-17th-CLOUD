mock_provider "aws" {
  mock_resource "aws_secretsmanager_secret" {
    override_during = plan
    defaults        = { arn = "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/be-abcdef" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" { defaults = { region = "ap-northeast-2" } }
  mock_data "aws_vpc" { defaults = { cidr_block = "172.31.0.0/16" } }
}
override_data {
  target = data.terraform_remote_state.common
  values = {
    outputs = {
      image_bucket_arn  = "arn:aws:s3:::fixture-shared-images"
      be_repository_url = "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/fixture-be"
      ai_repository_url = "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/fixture-ai"
    }
  }
}

variables {
  acm_certificate_arn          = "arn:aws:acm:ap-northeast-2:975779326240:certificate/11111111-1111-1111-1111-111111111111"
  monitoring_security_group_id = null
}
run "fresh_infrastructure" {
  command = plan
  variables { services_enabled = false }
  assert {
    condition     = output.ecs_service_names.be == null && output.ecs_service_names.ai == null && output.ecs_service_names.ws == null
    error_message = "Fresh infrastructure must not create application services before external task registration."
  }
}
run "external_task_service_shells" {
  command = plan
  variables {
    task_definition_arns = {
      be = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-be:42"
      ai = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-ai:43"
      ws = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-ws:44"
    }
    be_access = {
      parameter_arns = { DB_URL = "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/be/DB_URL" }
      kms_key_arns   = ["arn:aws:kms:ap-northeast-2:975779326240:key/be-fixture"]
      secrets        = { EXTERNAL = "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:external-abcdef:password::" }
    }
    ai_access = {
      secrets                          = { API_KEY = "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:ai-abcdef" }
      additional_execution_secret_arns = ["arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:other-abcdef"]
    }
  }
  assert {
    condition     = module.be.service_name == "star23-be-service" && module.ai.service_name == "star23-ai-service" && module.ws.service_name == "star23-ws-service"
    error_message = "Service operational names must be preserved."
  }
}
run "ws_disabled" {
  command = plan
  variables {
    task_definition_arns = {
      be = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-be:42"
      ai = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-ai:43"
    }
    ws_infrastructure = { enabled = false, use_backend_config = false }
  }
  assert {
    condition     = !contains(keys(output.ecs_service_names), "ws")
    error_message = "Disabled WS must remain optional."
  }
}

run "independent_ws_and_ai_parameter_access" {
  command = plan
  variables {
    task_definition_arns = {
      be = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-be:42"
      ai = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-ai:43"
      ws = "arn:aws:ecs:ap-northeast-2:975779326240:task-definition/star23-ws:44"
    }
    ws_infrastructure = { enabled = true, use_backend_config = false }
    ai_access = {
      secrets                          = { SETTING = "arn:aws:ssm:ap-northeast-2:975779326240:parameter/external/ai/setting" }
      additional_execution_secret_arns = ["arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:other-abcdef"]
    }
    ws_access = {
      secrets      = { TOKEN = "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:ws-abcdef:token::" }
      kms_key_arns = ["arn:aws:kms:ap-northeast-2:975779326240:key/ws-fixture"]
    }
  }
}

run "v2_database_access_ws_disabled" {
  command = plan
  variables {
    services_enabled  = false
    ws_infrastructure = { enabled = false, use_backend_config = false }
  }
  assert {
    condition     = length(module.database.be_rule_ids) == 2 && length(module.database.ws_rule_ids) == 1 && length(module.database.ai_rule_ids) == 1
    error_message = "Disabling WS services must preserve the fixed V2 database access rules."
  }
}
