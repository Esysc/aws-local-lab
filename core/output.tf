output "bastion_public_ip" {
  description = "Public IP or host used to reach the bastion (EIP for AWS, host for local mode)"
  value       = var.use_local ? var.bastion_host : try(aws_eip.bastionip[0].public_ip, "")
}

output "bastion_private_ip" {
  description = "Private IP of the bastion (EIP private_ip when on AWS, empty in local mode)"
  value       = var.use_local ? "" : try(aws_eip.bastionip[0].private_ip, "")
}
output "bastion_ssh_port" {
  description = "SSH port to connect to the bastion (local or AWS NAT/forwarding)"
  value       = var.use_local ? var.bastion_ssh_port : 22
}
output "elb_dns_name" {
  description = "DNS name of the web ELB"
  value       = try(aws_elb.web_elb[0].dns_name, "")
}

output "web_address" {
  description = "URL to access the web server (local or AWS)."
  value       = var.use_local ? "http://127.0.0.1:${var.local_web_port}" : "http://${try(aws_elb.web_elb[0].dns_name, "")}"
}
