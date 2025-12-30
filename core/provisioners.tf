# Example: run `httpCheck` on the bastion via a `remote-exec` provisioner.
# Fill in the connection block with your user/private_key or use an SSH agent.
# This resource is an example and may need changes for your environment.

resource "null_resource" "run_httpcheck_on_bastion" {
  count = var.use_local ? 0 : 1
  # re-run when bastion instance changes
  triggers = {
    bastion_id = aws_instance.main_bastion[0].id
  }

  # Ensure ELB/DNS is created before running the check when present
  depends_on = [aws_route53_record.cloudlab]

  provisioner "file" {
    # copy the local script to the remote host
    source      = "${path.module}/../scripts/httpCheck"
    destination = "/tmp/httpCheck"

    connection {
      # Replace with real connection details when using real AWS
      host = aws_eip.bastionip[0].public_ip
      user = "ubuntu"
      # private_key = file("~/.ssh/my_bastion_key.pem")
      # Or rely on SSH agent
      timeout = "5m"
    }
  }

  provisioner "remote-exec" {
    # Export env vars directly in the inline script
    inline = [
      "chmod +x /tmp/httpCheck",
      "export DOMAIN='${var.domain}' TIMEOUT='5' USE_LOCAL='${tostring(var.use_local)}' && sudo /tmp/httpCheck"
    ]

    connection {
      host = aws_eip.bastionip[0].public_ip
      user = "ubuntu"
      # private_key = file("~/.ssh/my_bastion_key.pem")
      timeout = "5m"
    }
  }
}

# Local-mode provisioner: run httpCheck against the local docker-based bastion (ec2-node-1)
resource "null_resource" "run_httpcheck_on_local_bastion" {
  count = var.use_local ? 1 : 0

  triggers = {
    # use the bastion_host and ssh key path as triggers so changes re-run
    bastion_host = var.bastion_host
    ssh_key      = var.ssh_private_key_path
  }

  # Ensure both local bastion and web containers exist before running the check
  depends_on = [
    docker_container.bastion[0],
    docker_container.web[0]
  ]

  provisioner "file" {
    source      = "${path.module}/../scripts/httpCheck"
    destination = "/tmp/httpCheck"

    connection {
      host        = var.bastion_host
      port        = var.bastion_ssh_port
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/httpCheck",
      "export DOMAIN='${var.domain}' TIMEOUT='5' USE_LOCAL='${tostring(var.use_local)}' && sudo /tmp/httpCheck"
    ]

    connection {
      host        = var.bastion_host
      port        = var.bastion_ssh_port
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      timeout     = "5m"
    }
  }
}
