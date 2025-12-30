provider "docker" {
  host = var.docker_host
}

# Render local provision scripts as files that can be copied into containers
resource "local_file" "provision_bastion" {
  count    = var.use_local ? 1 : 0
  content  = templatefile("${path.module}/templates/local_provision.sh.tpl", { index_b64 = "", pubkey_b64 = try(base64encode(file("${path.module}/../.local/ssh/id_rsa.pub")), "") })
  filename = "${path.module}/.local_provision_bastion.sh"
}

resource "local_file" "provision_web" {
  count    = var.use_local ? 1 : 0
  content  = templatefile("${path.module}/templates/local_provision.sh.tpl", { index_b64 = try(base64encode(file("${path.module}/../local_web/index.html")), ""), pubkey_b64 = try(base64encode(file("${path.module}/../.local/ssh/id_rsa.pub")), "") })
  filename = "${path.module}/.local_provision_web.sh"
}

resource "docker_image" "bastion" {
  count = var.use_local ? 1 : 0
  name  = "local/bastion:latest"

  build {
    context = "${path.module}/docker/bastion"
  }
}

resource "docker_container" "bastion" {
  count = var.use_local ? 1 : 0
  name  = "ec2-node-1"
  # Use the image_id (pure digest) to avoid name-vs-digest churn causing unnecessary replacements
  image = docker_image.bastion[0].image_id

  ports {
    internal = 22
    external = var.bastion_ssh_port
  }

  restart = "unless-stopped"

  lifecycle {
    # Ignore computed network attributes and port re-ordering churn reported by the Docker provider
    # Note: `network_data` is provider-computed and has no configured value, so omit it to avoid
    # a redundant ignore_changes warning.
    ignore_changes = [
      network_mode,
      ports,
    ]
  }

  # Mount the pubkey into a temp path so the container can copy it with correct ownership
  volumes {
    host_path      = abspath("${path.module}/../.local/ssh/id_rsa.pub")
    container_path = "/tmp/id_rsa.pub"
  }

  # Mount the provision script
  volumes {
    host_path      = abspath(local_file.provision_bastion[0].filename)
    container_path = "/tmp/local_provision.sh"
  }

  provisioner "remote-exec" {
    inline = ["chmod +x /tmp/local_provision.sh", "/tmp/local_provision.sh"]

    connection {
      type        = "ssh"
      host        = "127.0.0.1"
      port        = var.bastion_ssh_port
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      timeout     = "5m"
    }
  }
}

resource "docker_image" "web" {
  count = var.use_local ? 1 : 0
  name  = "local/web:latest"

  build {
    context = "${path.module}/docker/web"
  }
}

resource "docker_container" "web" {
  count = var.use_local ? 1 : 0
  name  = "ec2-web"
  # Use the image_id (pure digest) to avoid name-vs-digest churn causing unnecessary replacements
  image = docker_image.web[0].image_id

  ports {
    internal = 80
    external = var.local_web_port
  }
  ports {
    internal = 22
    external = var.web_ssh_port
  }

  restart = "unless-stopped"
  lifecycle {
    # Ignore computed network attributes and port re-ordering churn reported by the Docker provider
    # Note: `network_data` is provider-computed and has no configured value, so omit it to avoid
    # a redundant ignore_changes warning.
    ignore_changes = [
      network_mode,
      ports,
    ]
  }
  depends_on = [docker_container.bastion]

  # Mount the pubkey into a temp path so the container can copy it with correct ownership
  volumes {
    host_path      = abspath("${path.module}/../.local/ssh/id_rsa.pub")
    container_path = "/tmp/id_rsa.pub"
  }

  # Mount the provision script
  volumes {
    host_path      = abspath(local_file.provision_web[0].filename)
    container_path = "/tmp/local_provision.sh"
  }

  provisioner "remote-exec" {
    inline = ["chmod +x /tmp/local_provision.sh", "/tmp/local_provision.sh"]

    connection {
      type        = "ssh"
      host        = "127.0.0.1"
      port        = var.web_ssh_port
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      timeout     = "5m"
    }
  }
}
