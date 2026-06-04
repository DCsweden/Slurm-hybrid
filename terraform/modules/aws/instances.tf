data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

locals {
  common_tags = {
    SlurmCluster = var.cluster_name
    Project      = var.project_name
  }
}

resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "login" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_login
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.slurm.id]
  key_name                    = aws_key_pair.main.key_name
  private_ip                  = var.login_private_ip
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../../templates/cloud-init-login.yaml", merge(local.cloud_init_base, {
    bootstrap_login_b64 = local.bootstrap_login_b64
  }))

  root_block_device {
    volume_size = 40
  }

  tags = merge(local.common_tags, {
    Name = var.login_hostname
    Role = "login"
  })
}

resource "aws_instance" "ctrl1" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_controller
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.slurm.id]
  key_name                    = aws_key_pair.main.key_name
  private_ip                  = var.ctrl1_private_ip
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.controller.name

  user_data = templatefile("${path.module}/../../templates/cloud-init-controller.yaml", merge(local.cloud_init_base, {
    is_primary            = "true"
    bootstrap_script_b64  = local.bootstrap_script_b64
    cloud_nodes_json      = jsonencode({
      "aws-compute" = { provider = "aws", instance_id = aws_instance.compute.id, zone = "" }
      "gcp-compute" = { provider = "gcp", instance_id = var.gcp_compute_hostname, zone = var.gcp_zone }
    })
    aws_compute_id         = aws_instance.compute.id
    gcp_compute_hostname   = var.gcp_compute_hostname
  }))

  root_block_device {
    volume_size = 50
  }

  tags = merge(local.common_tags, {
    Name = var.ctrl1_hostname
    Role = "controller"
  })

  depends_on = [aws_instance.compute]
}

resource "aws_instance" "ctrl2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_controller
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.slurm.id]
  key_name                    = aws_key_pair.main.key_name
  private_ip                  = var.ctrl2_private_ip
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.controller.name

  user_data = templatefile("${path.module}/../../templates/cloud-init-controller.yaml", merge(local.cloud_init_base, {
    is_primary            = "false"
    bootstrap_script_b64  = local.bootstrap_script_b64
    cloud_nodes_json      = jsonencode({
      "aws-compute" = { provider = "aws", instance_id = aws_instance.compute.id, zone = "" }
      "gcp-compute" = { provider = "gcp", instance_id = var.gcp_compute_hostname, zone = var.gcp_zone }
    })
    aws_compute_id         = aws_instance.compute.id
    gcp_compute_hostname   = var.gcp_compute_hostname
  }))

  root_block_device {
    volume_size = 50
  }

  tags = merge(local.common_tags, {
    Name = var.ctrl2_hostname
    Role = "controller"
  })

  depends_on = [aws_instance.ctrl1, aws_instance.compute]
}

resource "aws_instance" "compute" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_compute
  subnet_id              = aws_subnet.compute.id
  vpc_security_group_ids = [aws_security_group.slurm.id]
  key_name               = aws_key_pair.main.key_name
  private_ip             = var.compute_private_ip
  iam_instance_profile   = aws_iam_instance_profile.compute.name

  user_data = templatefile("${path.module}/../../templates/cloud-init-compute.yaml", merge(local.cloud_init_base, {
    node_name         = var.compute_hostname
    cloud_provider    = "aws"
    ctrl1_ip          = var.ctrl1_private_ip
    ctrl2_ip          = var.ctrl2_private_ip
    bootstrap_compute_b64 = local.bootstrap_compute_b64
  }))

  root_block_device {
    volume_size = 80
  }

  tags = merge(local.common_tags, {
    Name = var.compute_hostname
    Role = "compute"
    Cloud = "aws"
  })
}
