# Jenkins deployment connection

The existing `star23-ci-controller` instance role publishes only `star23/be` and `star23/ai` images and describes the two EKS clusters. `jenkins-publisher-policy.json` defines that scope; it cannot edit EKS resources, change ECR configuration, or read application secrets.

Create a STANDARD EKS access entry for `arn:aws:iam::975779326240:role/star23-ci-controller` in each cluster with Kubernetes group `star23-jenkins-observers`. Associate no Amazon EKS access policy. Apply `jenkins-observer.yaml` independently to each cluster: it grants only GET of the existing eleven BE/AI Applications in `argocd`. It grants neither list/watch nor image-worker access nor deployment writes.

These files are an operator bootstrap, outside both application Kustomize roots. Committing them does not grant permissions. Each Argo CD continues to apply its own workloads.

Jenkins needs three intended GitHub App credentials: source read (`github-app-star23`, BE/AI Contents+Metadata+Actions read); CLOUD-only writer (`github-app-star23-gitops`, Contents write+Metadata read); separate CLOUD read (`github-app-star23-cloud-read`, Contents+Metadata read). Installation scope and issued token permissions must match. Do not substitute a broad personal token or store keys in Git.

After prerequisites and actual branch deployment validation, enable `STAR23_AUTO_DEPLOY_STAGING`, `STAR23_AUTO_DEPLOY_PROD`, `AI_STAGING_AUTO_DEPLOY_ENABLED`, and `AI_PROD_AUTO_DEPLOY_ENABLED` as Jenkins global environment variables. Source Jenkinsfiles remain gated until these are true. Preserve semantic-release workflows and disable legacy EC2/ECS deployment publishers before cutover. ECR source/version tags must be immutable; retain only explicitly needed mutable legacy tags as exclusions.

The success chain is source SHA → Jenkins URL → ECR tag/digest → CLOUD commit → all role Applications at one compatible CLOUD revision Synced/Healthy. Validate the other environment's images are unchanged when deploying staging.
