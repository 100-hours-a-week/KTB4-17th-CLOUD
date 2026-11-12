/** Cluster role
 * 클러스터의 현재 신뢰 정책과 AWS 실행 권한을 보존한다.
 */
resource "aws_iam_role" "cluster" {
  name                 = "AmazonEKSRoleManager-ap-northeast-2-Cluster"
  path                 = "/service-role/"
  description          = "Allows access to other AWS service resources that are required to operate non-auto mode clusters managed by EKS."
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "eks.amazonaws.com"
        },
        "Action" : [
          "sts:AssumeRole",
          "sts:TagSession"
        ],
        "Condition" : {
          "StringEquals" : {
            "aws:SourceAccount" : "975779326240"
          }
        }
      }
    ]
  })
  tags = {}
}

/** Node role
 * EKS 노드가 클러스터에 연결하고 이미지를 가져올 기존 역할을 관리한다.
 */
resource "aws_iam_role" "node" {
  name                 = "AmazonEKSRoleManager-ap-northeast-2-Node"
  path                 = "/"
  description          = "Allows EKS nodes to connect to EKS Auto Mode clusters and to pull container images from ECR."
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = {}
}

/** CNI role
 * VPC CNI가 사용하는 Pod Identity 신뢰 정책을 보존한다.
 */
resource "aws_iam_role" "cni" {
  name                 = "AmazonEKSPodIdentityAmazonVPCCNIRole"
  path                 = "/"
  description          = ""
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "pods.eks.amazonaws.com"
        },
        "Action" : [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
  tags = {}
}

/** Load balancer controller role
 * 현재 IRSA의 OIDC·ServiceAccount 신뢰를 유지하며 컨트롤러 배포는 관리하지 않는다.
 */
resource "aws_iam_role" "load_balancer_controller" {
  name                 = "AmazonEKSLoadBalancerControllerRole-star-EKS-v3"
  path                 = "/"
  description          = "AWS Load Balancer Controller for star-EKS-v3 via EKS Pod Identity"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : aws_iam_openid_connect_provider.cluster.arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${local.oidc_issuer}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller",
            "${local.oidc_issuer}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
  tags = {}
}

/** Cluster autoscaler role
 * 현재 IRSA 신뢰를 유지하며 자동 확장 권한은 기존 클러스터 태그로 제한한다.
 */
resource "aws_iam_role" "cluster_autoscaler" {
  name                 = "ClusterAutoscalerRole-star-EKS-v3"
  path                 = "/"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : aws_iam_openid_connect_provider.cluster.arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${local.oidc_issuer}:sub" : "system:serviceaccount:kube-system:cluster-autoscaler",
            "${local.oidc_issuer}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
  tags = {}
}

/** External secrets role
 * ESO의 Pod Identity 역할만 관리하며 Secret·SSM 실제 값은 조회하지 않는다.
 */
resource "aws_iam_role" "external_secrets" {
  name                 = "star23-v3-external-secrets"
  path                 = "/"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "pods.eks.amazonaws.com"
        },
        "Action" : [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
  tags = {}
}

/** Application storage role
 * 앱 Pod의 S3 접근에 쓰는 Pod Identity 역할을 관리한다.
 */
resource "aws_iam_role" "application_s3" {
  name                 = "star23-v3-be-s3"
  path                 = "/"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "pods.eks.amazonaws.com"
        },
        "Action" : [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
  tags = {}
}

/** Role policy attachments
 * AWS 관리 정책은 연결만 소유하고, 고객 관리 정책은 아래 정책 자원을 참조한다.
 */
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_minimal" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_pull" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy_attachment" "node_ecr_public" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicReadOnly"
}

resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

/** External secrets permissions
 * 기존 Secret·Redis 파라미터 ARN에 대한 ESO 읽기 권한만 그대로 관리한다.
 */
resource "aws_iam_role_policy" "external_secrets" {
  name = "star23-v3-read-secrets"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadExistingStar23Secrets",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        "Resource" : [
          "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/be-q1bpe9",
          "arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/ai/slm-api-key-8VzUsP"
        ]
      },
      {
        "Sid" : "ReadExistingRedisParameters",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ],
        "Resource" : [
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/be/REDIS_URL",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/ws/REDIS_URL"
        ]
      }
    ]
  })
}

/** Application storage permissions
 * star23-images 객체의 기존 읽기·쓰기·삭제 권한을 그대로 관리한다.
 */
resource "aws_iam_role_policy" "application_s3" {
  name = "star23-v3-be-s3-objects"
  role = aws_iam_role.application_s3.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "Star23ImagesObjects",
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        "Resource" : "arn:aws:s3:::star23-images/*"
      }
    ]
  })
}
