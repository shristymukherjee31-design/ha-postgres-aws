resource "aws_instance" "primary" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.db_a.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project}-primary"
    Role = "primary"
  }
}

resource "aws_instance" "standby" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.db_b.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project}-standby"
    Role = "standby"
  }
}

output "primary_private_ip" {
  value = aws_instance.primary.private_ip
}

output "standby_private_ip" {
  value = aws_instance.standby.private_ip
}
