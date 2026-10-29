resource "local_file" "ssh_config" {
  filename        = pathexpand("~/.ssh/ha-pg.conf")
  file_permission = "0600"
  content         = <<-EOT
    Host bastion
        HostName ${aws_instance.bastion.public_ip}
        User ubuntu
        IdentityFile ~/.ssh/${var.key_name}.pem
        IdentitiesOnly yes
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null

    Host primary
        HostName ${aws_instance.primary.private_ip}
        User ubuntu
        IdentityFile ~/.ssh/${var.key_name}.pem
        IdentitiesOnly yes
        ProxyJump bastion
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null

    Host standby
        HostName ${aws_instance.standby.private_ip}
        User ubuntu
        IdentityFile ~/.ssh/${var.key_name}.pem
        IdentitiesOnly yes
        ProxyJump bastion
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
  EOT
}

