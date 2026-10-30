# Ubuntu 
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  # Installs the client tools used for demos and validation on first boot.
  user_data = <<-EOT
    #!/bin/bash
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-client dnsutils
  EOT

  # Replace the instance (instead of stop/start) when user_data changes.
  user_data_replace_on_change = true
  tags = {
    Name = "${var.project}-bastion"
   Role = "bastion"
  }
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
