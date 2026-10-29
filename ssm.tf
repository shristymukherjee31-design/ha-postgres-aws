# Tracks which instance currently acts as the PostgreSQL primary.
# Seeded with the initial primary; the failover script overwrites it after a
# standby promotion, so Terraform must not revert the value.
resource "aws_ssm_parameter" "current_primary" {
  name        = "/${var.project}/current_primary"
  description = "Instance ID of the current PostgreSQL primary"
  type        = "String"
  value       = aws_instance.primary.id

  lifecycle {
    ignore_changes = [value]
  }
}
