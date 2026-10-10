## IAM Roles for Service Accounts (IRSA) ##
# Lets a Kubernetes ServiceAccount assume an IAM role via the cluster's OIDC
# provider -- so the External Secrets Operator pod gets AWS access scoped to
# exactly this one secret, with no static AWS keys stored in the cluster.


data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      # Must match the Kubernetes namespace + ServiceAccount name used below
      values = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project_name}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json
}

data "aws_iam_policy_document" "eso_secrets_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_role_policy" "eso_secrets_read" {
  name   = "${var.project_name}-eso-secrets-read"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_secrets_read.json
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}
