locals {
  repo_root = abspath("${path.module}/../../..")

  slurm_conf = file("${local.repo_root}/slurm/slurm.conf")
  slurmdbd_conf = replace(
    file("${local.repo_root}/slurm/slurmdbd.conf"),
    "SLURM_DB_PASSWORD",
    var.db_password
  )
  cgroup_conf = file("${local.repo_root}/slurm/cgroup.conf")

  install_script_b64     = base64encode(file("${local.repo_root}/scripts/install-slurm.sh"))
  bootstrap_script_b64   = base64encode(file("${local.repo_root}/scripts/bootstrap-controller.sh"))
  bootstrap_login_b64    = base64encode(file("${local.repo_root}/scripts/bootstrap-login.sh"))
  bootstrap_compute_b64  = base64encode(file("${local.repo_root}/scripts/bootstrap-compute.sh"))
  resume_script          = file("${local.repo_root}/scripts/slurm_resume")
  suspend_script         = file("${local.repo_root}/scripts/slurm_suspend")
  resume_fail_script     = file("${local.repo_root}/scripts/slurm_resume_fail")

  cloud_init_base = {
    ssh_public_key     = var.ssh_public_key
    slurm_conf         = local.slurm_conf
    slurmdbd_conf      = local.slurmdbd_conf
    cgroup_conf        = local.cgroup_conf
    install_script_b64 = local.install_script_b64
    resume_script      = local.resume_script
    suspend_script     = local.suspend_script
    resume_fail_script = local.resume_fail_script
    cluster_name       = var.cluster_name
    slurm_version      = var.slurm_version
    db_password        = var.db_password
    gcp_project_id     = var.gcp_project_id
    gcp_zone           = var.gcp_zone
  }
}
