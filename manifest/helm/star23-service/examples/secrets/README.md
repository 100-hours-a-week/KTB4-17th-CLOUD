# Secrets Manager → EKS Pod environment variables

No secret values are stored here. `backend.values.yaml`, `websocket.values.yaml`, and `ai.values.yaml` contain only Secrets Manager ARNs, SSM parameter paths, and JSON property names. Existing ECS task definitions `star23-be:21`, `star23-ws:8`, and `star23-ai:18` were used to verify the key mapping.

## Current status

- The EKS Pod Identity Agent and External Secrets Operator (ESO) chart `2.14.0` are installed. The `user-api`, `auth-api`, `chat-socket`, and `onboarding-persona-ai` ExternalSecrets report `Ready=True`.
- `star23/prod/be` and `star23/prod/ai/slm-api-key` already exist in Secrets Manager. The v2 Redis URLs are existing SSM `SecureString` parameters and are deliberately not written into ConfigMaps or Git.
- v3 intentionally shares the existing v2 RDS, Kafka, and Redis. BE `DB_PASSWORD` and AI `DATABASE_URL` map to existing keys in `star23/prod/be`.
- BE `DB_URL`, `DB_USERNAME`, and Kafka bootstrap servers are copied from the existing v2 SSM `String` parameters into the BE/WebSocket ConfigMaps. Redis URLs are synced from SSM `SecureString` into the generated Kubernetes Secret with `REDIS_URL`, `SPRING_DATA_REDIS_URL`, and `PROFILE_CACHE_REDIS_URL` keys. BE and WebSocket have different Redis parameter values, so use the matching overlay. V2 and v3 background consumers, schedulers, migrations, and shared Redis channels require a coordinated rollout. BE/WebSocket examples keep `FLYWAY_ENABLED=true`, matching the existing ECS application default. V2 and v3 use the same image by design, so they carry the same migration files; Flyway checks the shared schema history and does not reapply an already completed version.

## Reproducible setup order (already applied to this cluster)

1. Create an IAM role with `eso-pod-identity-trust.json`, attach the permissions in `eso-read-secrets-policy.json`, and associate the role to ServiceAccount `external-secrets` in namespace `external-secrets` on cluster `star-EKS-v3`. The policy covers the two existing Secrets Manager sources and the exact BE/WebSocket Redis SSM parameters. Both currently use the AWS-managed KMS key; add `kms:Decrypt` if a future secret uses a customer-managed KMS key.
2. Install ESO chart version `2.14.0` in the `external-secrets` namespace with controller ServiceAccount name `external-secrets`. ESO installs the `SecretStore` and `ExternalSecret` CRDs. This is a cluster add-on, not a dependency chart under this application chart.
Example commands from the CLOUD repository root (these change AWS/EKS only when executed):

```sh
aws iam create-role --role-name star23-v3-external-secrets \
  --assume-role-policy-document file://helm/star23-service/examples/secrets/eso-pod-identity-trust.json
aws iam put-role-policy --role-name star23-v3-external-secrets \
  --policy-name star23-v3-read-secrets \
  --policy-document file://helm/star23-service/examples/secrets/eso-read-secrets-policy.json
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version 2.14.0 --namespace external-secrets --create-namespace \
  --set serviceAccount.name=external-secrets
aws eks create-pod-identity-association --region ap-northeast-2 \
  --cluster-name star-EKS-v3 --namespace external-secrets \
  --service-account external-secrets \
  --role-arn arn:aws:iam::975779326240:role/star23-v3-external-secrets
```

The Secrets Manager IAM policy grants access to whole secret objects, not selected JSON properties. The ESO controller reads the shared `star23/prod/be` Secret; the BE/AI Kubernetes Secrets receive only their explicitly mapped properties.

3. Confirm v3 is meant to use the existing production RDS before deploying. The mappings now reference the existing `DB_PASSWORD` and `AI_DATABASE_URL` properties; no new DB Secret is needed for this shared-DB plan. Never commit secret **values**.
4. Add the appropriate secret overlay after each base and role values file: `examples/secrets/backend.values.yaml` for BE Spring roles, `examples/secrets/websocket.values.yaml` for `chat-socket`, and `examples/secrets/ai.values.yaml` for FastAPI. The chart creates one namespaced Secrets Manager `SecretStore`, optionally one Parameter Store `SecretStore`, one `ExternalSecret`, and a Pod `envFrom.secretRef` per release. ESO, not the application Pod, uses Pod Identity to read Secrets Manager.
5. Check `kubectl get externalsecret -n <namespace>` for `Ready=True` and verify the generated Kubernetes Secret exists without printing its data. Because this chart creates the ExternalSecret and Deployment together, the Pod may wait briefly for the Secret on first install; confirm sync before judging application health.

Example (render only; requires the Helm CLI):

```sh
helm template user-api ./helm/star23-service -n user \
  -f ./helm/star23-service/examples/backend.values.yaml \
  -f ./helm/star23-service/examples/services/user-api.values.yaml \
  -f ./helm/star23-service/examples/secrets/backend.values.yaml
```

## v3 hostname and login

Gabia only maps `v3.star23sharp.com` to CloudFront. Spring also checks browser origins for CORS and `/ws/chat`, and Kakao sends the login authorization code to the configured `REDIRECT_URI`. BE/WebSocket ConfigMaps allow both `https://star23sharp.com` and `https://v3.star23sharp.com`. The `auth-api` role overlay directs the Kakao callback to `https://v3.star23sharp.com/api/v1/auth/kakao/callback` and browser redirects to the v3 site. Register that exact callback URI in Kakao Developers before testing login; the existing v2 URI remains unchanged in ECS. The `user-api` and `auth-api` QA Ingresses are live on the existing ALB; the Kakao Developers callback registration has not been verified or changed.

Pod environment variables do not update automatically when ESO refreshes the Kubernetes Secret. Roll the Deployment after a secret rotation or implement a restart controller. The application uses a separate `star23-v3-be-s3` Pod Identity role with the exact v2 BE S3 object actions on `star23-images/*`. It is associated with the `user-api`, `auth-api`, `chat-socket`, `onboarding-api`, `chat-api`, and `recommend-api` ServiceAccounts. ESO's read role covers only secret synchronization.

References: [ESO AWS Pod Identity](https://external-secrets.io/latest/provider/aws-access/), [ESO ExternalSecret](https://external-secrets.io/latest/api/externalsecret/), [AWS EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).
