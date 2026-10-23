data "aws_caller_identity" "current" {}

locals {
  project     = "homeops"
  github_repo = "Tegoisback/homeops"
  account_id  = data.aws_caller_identity.current.account_id
}

# ---------- Bucket para el estado de Terraform ----------
resource "aws_s3_bucket" "tfstate" {
  bucket = "${local.project}-tfstate-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- Confianza AWS <-> GitHub Actions (OIDC) ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Solo la rama main y los entornos de GitHub de ESTE repo pueden usar el rol
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.github_repo}:ref:refs/heads/main",
        "repo:${local.github_repo}:environment:*",
      ]
    }
  }
}

# ---------- Rol del pipeline ----------
resource "aws_iam_role" "github_deploy" {
  name                 = "${local.project}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# Puede gestionar casi todos los servicios, pero NO IAM...
resource "aws_iam_role_policy_attachment" "poweruser" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# ...salvo los roles de la aplicación (prefijo homeops-app-*).
# No coincide con su propio nombre, así que no puede darse más permisos a sí mismo.
data "aws_iam_policy_document" "iam_scoped" {
  statement {
    sid = "ManageAppRolesOnly"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.project}-app-*"]
  }
}

resource "aws_iam_role_policy" "iam_scoped" {
  name   = "manage-app-roles"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.iam_scoped.json
}