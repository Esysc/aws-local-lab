output "bastion_public_ip" {
  description = "Public IP of the bastion EIP"
  value       = aws_eip.bastionip.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the bastion EIP"
  value       = aws_eip.bastionip.private_ip
}

output "elb_dns_name" {
  description = "DNS name of the web ELB"
  value       = try(aws_elb.web_elb[0].dns_name, "")
}
