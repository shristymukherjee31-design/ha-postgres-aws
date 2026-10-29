# Values consumed by the failover and validation scripts.
output "primary_instance_id" {
  value = aws_instance.primary.id
}

output "standby_instance_id" {
  value = aws_instance.standby.id
}

output "route53_zone_id" {
  value = aws_route53_zone.internal.zone_id
}
