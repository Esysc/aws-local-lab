// local_ec2.tf — helper to bring up a local "EC2" container when running locally
resource "null_resource" "local_ec2" {
  count = var.use_local ? 1 : 0

  provisioner "local-exec" {
    command = "docker compose up -d ec2-node-1"
  }

  triggers = {
    # change when local mode changes
    use_local = tostring(var.use_local)
  }
}
