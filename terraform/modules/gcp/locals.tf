locals {
  repo_root = abspath("${path.module}/../../..")

  slurm_conf        = file("${local.repo_root}/slurm/slurm.conf")
  install_script    = file("${local.repo_root}/scripts/install-slurm.sh")
  bootstrap_compute = file("${local.repo_root}/scripts/bootstrap-compute.sh")
}
