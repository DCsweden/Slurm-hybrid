resource "aws_security_group" "slurm" {
  name        = "${var.project_name}-slurm"
  description = "Slurm hybrid cluster traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "SSH from peer cloud"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.gcp_vpc_cidr]
  }

  ingress {
    description = "Slurmctld"
    from_port   = 6817
    to_port     = 6817
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.gcp_vpc_cidr]
  }

  ingress {
    description = "Slurmd"
    from_port   = 6818
    to_port     = 6818
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.gcp_vpc_cidr]
  }

  ingress {
    description = "Slurmdbd"
    from_port   = 6819
    to_port     = 6819
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.gcp_vpc_cidr]
  }

  ingress {
    description = "Munge / internal"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr, var.gcp_vpc_cidr]
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-slurm-sg"
  }
}
