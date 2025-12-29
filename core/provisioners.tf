# Example: run `httpCheck` on the bastion via a `remote-exec` provisioner.
# Fill in the connection block with your user/private_key or use an SSH agent.
# This resource is an example and may need changes for your environment.

resource "null_resource" "run_httpcheck_on_bastion" {
  count = var.use_local ? 0 : 1
  # re-run when bastion instance changes
  triggers = {
    bastion_id = aws_instance.main_bastion.id
  }

  provisioner "file" {
    # copy the local script to the remote host
    source      = "${path.module}/../scripts/httpCheck"
    destination = "/tmp/httpCheck"

    connection {
      # Replace with real connection details when using real AWS
      host        = aws_eip.bastionip.public_ip
      user        = "ubuntu"
      # private_key = file("~/.ssh/my_bastion_key.pem")
      # Or rely on SSH agent
      timeout     = "2m"
    }
  }

  provisioner "remote-exec" {
    # Export env vars directly in the inline script
    inline = [
      "chmod +x /tmp/httpCheck",
      "export DOMAIN='${var.domain}' TIMEOUT='5' USE_LOCAL='${tostring(var.use_local)}' && sudo /tmp/httpCheck"
    ]

    connection {
      host        = aws_eip.bastionip.public_ip
      user        = "ubuntu"
      # private_key = file("~/.ssh/my_bastion_key.pem")
      timeout     = "2m"
    }
  }
}
