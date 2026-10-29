data "aws_caller_identity" "current" {}

# Backup bucket for logical dumps (pg_dump).
# The account ID in the name keeps it globally unique.
# force_destroy allows "terraform destroy" to remove a non-empty bucket
# (acceptable for a lab, not for production).
resource "aws_s3_bucket" "backup" {
  bucket        = "${var.project}-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "${var.project}-backups" }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "backup_bucket" {
  value = aws_s3_bucket.backup.bucket
}
