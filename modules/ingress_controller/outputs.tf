output "load_balancer_ip" {
  description = "External IP address of the nginx-ingress LoadBalancer Service. Empty string while GKE is still provisioning the IP."
  # status[0].load_balancer[0].ingress may be an empty list while the IP is
  # still being assigned; try() surfaces an empty string instead of erroring.
  value = try(
    data.kubernetes_service.nginx_lb.status[0].load_balancer[0].ingress[0].ip,
    ""
  )
}
