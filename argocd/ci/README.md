# Jenkins deployment connection

The existing `star23-ci-controller` instance role publishes only `star23/be` and `star23/ai` images and describes the two EKS clusters. `jenkins-publisher-policy.json` defines that scope; it cannot edit EKS resources, change ECR configuration, or read application secrets.

Create a STANDARD EKS access entry for `arn:aws:iam::975779326240:role/star23-ci-controller` in each cluster with Kubernetes group `star23-jenkins-observers`. Associate no Amazon EKS access policy. Apply `jenkins-observer.yaml` independently to each cluster: it grants only GET of the existing eleven BE/AI Applications in `argocd`. It grants neither list/watch nor image-worker access nor deployment writes.

These files are an operator bootstrap, outside both application Kustomize roots. Committing them does not grant permissions. Each Argo CD continues to apply its own workloads.

Jenkins needs three intended GitHub App credentials: source read (`github-app-star23`, BE/AI Contents+Metadata+Actions read); CLOUD-only writer (`github-app-star23-gitops`, Contents write+Metadata read); separate CLOUD read (`github-app-star23-cloud-read`, Contents+Metadata read). Installation scope and issued token permissions must match. Do not substitute a broad personal token or store keys in Git.

After prerequisites and actual branch deployment validation, enable `STAR23_AUTO_DEPLOY_STAGING`, `STAR23_AUTO_DEPLOY_PROD`, `AI_STAGING_AUTO_DEPLOY_ENABLED`, and `AI_PROD_AUTO_DEPLOY_ENABLED` as Jenkins global environment variables. Source Jenkinsfiles remain gated until these are true. Preserve semantic-release workflows and disable legacy EC2/ECS deployment publishers before cutover. ECR source/version tags must be immutable; retain only explicitly needed mutable legacy tags as exclusions.

The success chain is source SHA → Jenkins URL → ECR tag/digest → CLOUD commit → all role Applications at one compatible CLOUD revision Synced/Healthy. Validate the other environment's images are unchanged when deploying staging.

The existing prod EKS private endpoint resolves to 10.1.x addresses inside the CI VPC. Its cluster security group `sg-06e19a0919af952c8` needs TCP 443 ingress from the existing Jenkins security group `sg-027dd9d0145682f1f`. `jenkins-prod-eks443-ingress.json` describes only that source-group rule, with no CIDR or Internet ingress. Apply it once with `aws ec2 authorize-security-group-ingress --group-id sg-06e19a0919af952c8 --ip-permissions file://argocd/ci/jenkins-prod-eks443-ingress.json` after verifying both group identities. Staging observation uses its existing public endpoint through NAT and needs no inter-VPC route or peering.

The AI repository now uses IMMUTABLE tags, matching BE and the publisher's version-tag safety gate. `terraform/common/storage/ecr.tf` records this setting so a later infrastructure apply preserves it. Disable legacy AI ECS deployment with `AI_LEGACY_ECS_CD_ENABLED=false` in GitHub repository variables before EKS cutover; semantic-release remains enabled.

2026-11-13 bootstrap verification: the actual Jenkins user/instance role could GET eleven Applications in each cluster; Secret listing and image-worker GET returned 403. The source/rollout code was merged into dev; BE main PR521 and AI main PR281 require one separate approving review under their current rulesets. Auto merge is disabled in both repositories. At this verification point no GitHub App credentials were registered and all four automatic deployment flags remained unset. These connection checks do not constitute an end-to-end release.
