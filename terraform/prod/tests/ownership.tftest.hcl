mock_provider "aws" {
  mock_resource "aws_secretsmanager_secret" {
    override_during = plan
    defaults        = { arn = "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/be-abcdef" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" { defaults = { region = "ap-northeast-2" } }
}
variables {
  acm_certificate_arn = "arn:aws:acm:ap-northeast-2:975779326240:certificate/11111111-1111-1111-1111-111111111111"
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
    services_enabled  = false
    ws_infrastructure = { enabled = false, use_backend_config = false }
  }
  assert {
    condition     = !contains(keys(output.ecs_service_names), "ws")
    error_message = "Disabled WS must remain optional."
  }
}
