# VPN tunnel/route moved into module.gcp (vpn_aws.tf) for forwarding-rule depends_on.
moved {
  from = google_compute_vpn_tunnel.aws_tunnel1
  to   = module.gcp.google_compute_vpn_tunnel.aws[0]
}

moved {
  from = google_compute_route.aws_via_vpn
  to   = module.gcp.google_compute_route.aws_via_vpn[0]
}
