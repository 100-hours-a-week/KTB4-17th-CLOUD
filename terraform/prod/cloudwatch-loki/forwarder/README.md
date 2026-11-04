# Production ECS CloudWatch → private Loki

This module adds a ZIP Lambda forwarder, its execution role, one Lambda security
group, one additional ingress rule on the existing Loki group, and subscriptions
for the existing `be`, `ws`, and `ai` production log groups. Source log groups,
existing Loki security-group rules, VPCs, subnets and routes remain owned elsewhere.

```hcl
module "cloudwatch_loki" {
  source = "./forwarder"

  vpc_id                 = "vpc-0c203bd23ce77e200"
  subnet_ids             = ["subnet-0d6ff6e6460961e3c"]
  loki_security_group_id = "sg-0820d4fcf2170225f"
  loki_write_address     = "http://10.0.1.88:3100/loki/api/v1/push"
  lambda_zip_path        = abspath("artifacts/lambda-promtail-v1.0.1.zip")
}
```

The calling root should configure its AWS provider/region and its own backend,
for example the dedicated key `prod/cloudwatch-loki/terraform.tfstate`. Region, account and
partition are discovered from that provider; none is embedded in IAM ARNs.

## Pinned artifact

Use the official `grafana/lambda-promtail` v1.0.1 release ZIP, with an executable
Linux x86_64 `bootstrap` at ZIP root. Runtime is `provided.al2023`.
SHA-256: `2a436a30772ac638f715dd240784f787b9f0c745ba292a49cd23d132c477fd13`.
Keep the ZIP in the calling root's reproducible artifact packaging process; the
module does not download code or run build/provisioner commands.

## Labels

All entries receive `environment=prod`, `job=ecs`, `source=cloudwatch` and the
configurable default `cluster=star23-ecs-cluster`. JSON relabeling derives:

| CloudWatch group suffix | service | ecs_service |
| --- | --- | --- |
| `/be` | `spring` | `star23-be-service` |
| `/ws` | `ws` | `star23-ws-service` |
| `/ai` | `ai` | `star23-ai-service` |

`cloudwatch_log_group` retains the source group. Internal `__aws_*` labels are
removed after copying. `KEEP_STREAM=false` avoids task-ID stream cardinality and
`PRINT_LOG_LINE=false` keeps application contents out of the forwarder's own logs.

`RELABEL_CONFIGS` is a JSON array. v1.0.1 builds its input labels from an
unsorted Go map without calling `ScratchBuilder.Sort()`, which makes relabel
lookups unreliable with multiple input labels. This module deliberately leaves
`EXTRA_LABELS` empty and drops the type/owner labels, leaving only the CloudWatch
group before relabeling. Constant labels, including `extra_labels`, are added
through relabel rules afterward. Keep this workaround when using the pinned
v1.0.1 package; do not populate `EXTRA_LABELS` directly.

## Permissions, network and delivery

The default concurrency is unreserved (`-1`) to work with the account's current
10-execution quota. Lambda has no inbound security-group rules. Its only egress is TCP 3100 to the
existing Loki security group; one reciprocal ingress rule is added separately.
Select existing same-VPC subnets with a private/local route to Loki. The function
only pushes to Loki: no S3, SSM, Secrets Manager, or CloudWatch read permission is
granted. No source log payload needs fetching from an AWS API.

The role can create/write streams only in this function's pre-created log group.
The six EC2 ENI operations require `Resource="*"` for Lambda VPC attachment, as
specified by AWS; they are limited to the provider's region. A second statement
denies those operations when called from function code using
`lambda:SourceFunctionArn`, while preserving service-side ENI management.
All other resource permissions are exact log-group or queue ARNs. Each subscription
gets its own invocation permission scoped to source account and source log group.

The default DLQ is SQS-managed encrypted with 14-day retention; Lambda's async
service sends exhausted events, so runtime code does not call SQS and needs no
SQS endpoint or NAT. Invocation retry count is 2 and maximum event age is 1 hour.
`enable_dlq=false` removes the queue and its send permission. The function's own
logs retain 30 days; source ECS log retention remains unchanged. Delivery can be
duplicated by retries; this is not a backfill of historical CloudWatch entries.
Monitor Lambda Errors/Throttles/DeadLetterErrors and DLQ depth after enabling the
subscriptions. Existing log groups must have an available subscription-filter
slot. Avoid inline management of the existing Loki SG's rules in another state.

Sources:
- [lambda-promtail v1.0.1](https://github.com/grafana/lambda-promtail/releases/tag/v1.0.1)
- [AWS Lambda VPC execution permissions](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)
