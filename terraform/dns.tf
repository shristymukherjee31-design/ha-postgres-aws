# -----------------------------------------------------------------------------
# Private DNS zone for the database tier.
# Resolvable only from inside the VPC; provides a stable endpoint (db.internal)
# that always points at the current PostgreSQL primary.
# -----------------------------------------------------------------------------
resource "aws_route53_zone" "internal" {
  name = "db.internal"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = { Name = "${var.project}-private-zone" }
}

# -----------------------------------------------------------------------------
# A record: db.internal -> primary private IP.
# A short TTL (10s) lets clients pick up a failover change quickly.
# -----------------------------------------------------------------------------
resource "aws_route53_record" "db" {
  zone_id         = aws_route53_zone.internal.zone_id
  name            = "db.internal"
  type            = "A"
  ttl             = 10
  records         = [aws_instance.primary.private_ip]
  allow_overwrite = true

  # The failover script updates this record at runtime (standby promotion).
  # Ignore drift so Terraform does not revert DNS back to the old primary.
  lifecycle {
    ignore_changes = [records]
  }
}
