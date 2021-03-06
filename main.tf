locals {
  service_client_server = templatefile("${path.module}/tpl/nomad.service.tpl", {
    user = var.ssh_user
    with_server = true
  })
  service_client_only = templatefile("${path.module}/tpl/nomad.service.tpl", {
    user = var.ssh_user
    with_server = false
  })
  client_tpl  = templatefile("${path.module}/tpl/nomad-client.hcl", {
    user = var.ssh_user
    cluster_main = var.cluster_main
    nomad_http = var.nomad_http
    nomad_rpc = var.nomad_rpc
    nomad_serf = var.nomad_serf
  })
  server_tpl  = templatefile("${path.module}/tpl/nomad-server.hcl", {
    user = var.ssh_user
    nomad_http = var.nomad_http
    nomad_rpc = var.nomad_rpc
    nomad_serf = var.nomad_serf
  })
}

resource "null_resource" "service-nomad-client-server" {
  count = var.enable_server && var.enable_client && !var.cleanup ? 1 : 0

  triggers = {
    policy_sha1 = sha1(join("", [
      local.service_client_server,
      local.client_tpl,
      local.server_tpl
    ]))
  }

  depends_on = [
    null_resource.nomad-install
  ]

  connection {
    user        = var.ssh_user
    private_key = file(var.ssh_private_key)
    host        = var.ssh_ip
    port        = var.port
    timeout     = "1m"
  }

  provisioner "file" {
    content     = local.client_tpl
    destination = "/home/${var.ssh_user}/.config/nomad/config.hcl"
  }
  
  provisioner "file" {
    content     = local.server_tpl
    destination = "/home/${var.ssh_user}/.config/nomad/server.hcl"
  }

  provisioner "file" {
    content     = local.service_client_server
    destination = "/home/${var.ssh_user}/.config/systemd/user/nomad.service"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl --user stop nomad",
      "systemctl --user enable --now nomad",
      "sleep 5"
    ]
  }
}

resource "null_resource" "service-nomad-client-only" {
  count = !var.enable_server && var.enable_client && !var.cleanup ? 1 : 0

  triggers = {
    policy_sha1 = sha1(join("", [
      local.service_client_only,
      local.client_tpl
    ]))
  }

  depends_on = [
    null_resource.nomad-install
  ]

  connection {
    user        = var.ssh_user
    private_key = file(var.ssh_private_key)
    host        = var.ssh_ip
    port        = var.port
    timeout     = "1m"
  }

  provisioner "file" {
    content     = local.client_tpl
    destination = "/home/${var.ssh_user}/.config/nomad/config.hcl"
  }
  
  provisioner "file" {
    content     = local.service_client_only
    destination = "/home/${var.ssh_user}/.config/systemd/user/nomad.service"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl --user stop nomad",
      "systemctl --user enable --now nomad",
      "sleep 5"
    ]
  }
}

locals {
  command_downlod_nomad = <<EOT
if [ ! -f ${path.root}/.terraform/tmp/nomad/${var.nomad_version}/nomad.zip ]; then \
  mkdir -p ${path.root}/.terraform/tmp/nomad/${var.nomad_version} \
  && wget -q -O ${path.root}/.terraform/tmp/nomad/${var.nomad_version}/nomad.zip https://releases.hashicorp.com/nomad/${var.nomad_version}/nomad_${var.nomad_version}_linux_amd64.zip; \
fi; \
if [ ! -f ${path.root}/.terraform/tmp/nomad/${var.nomad_version}/nomad ]; then \
  unzip -o -q -d ${path.root}/.terraform/tmp/nomad/${var.nomad_version} ${path.root}/.terraform/tmp/nomad/${var.nomad_version}/nomad.zip; \
fi; \
if [ ! -f ${path.root}/.terraform/tmp/nomad/${var.nomad_version}/nomad ]; then \
  echo "Something was going wrong. Try a replay" && exit 1; \
fi \
EOT
}

resource "null_resource" "nomad-install" {
  count = var.cleanup ? 0 : 1

  triggers = {
    on_version_change = var.nomad_version
    policy_sha1 = sha1(local.command_downlod_nomad)
  }

  connection {
    user        = var.ssh_user
    private_key = file(var.ssh_private_key)
    host        = var.ssh_ip
    port        = var.port
    timeout     = "1m"
  }

  provisioner "local-exec" {
    command     = local.command_downlod_nomad
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /home/${var.ssh_user}/nomad-data/plugins",
      "mkdir -p /home/${var.ssh_user}/.config/nomad",
      "mkdir -p /home/${var.ssh_user}/.config/systemd/user",
      "systemctl --user stop nomad || true",
      "sleep 2"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/.terraform/tmp/nomad/${var.nomad_version}/nomad"
    destination = "/home/${var.ssh_user}/bin/nomad"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.ssh_user}/bin/nomad",
      "systemctl --user start nomad || true",
      "sleep 5"
    ]
  }
}

locals {
  command_downlod_nomad_driver_podman = <<EOT
if [ ! -f ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman.zip ]; then \
  mkdir -p ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version} \
  && wget -q -O ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman.zip https://releases.hashicorp.com/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman_${var.nomad-driver-podman_version}_linux_amd64.zip \
  || rm -f ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman*; \
fi; \
if [ ! -f ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman ]; then \
  unzip -o -q -d ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version} ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman.zip \
  || rm -f ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman*; \
fi; \
if [ ! -f ${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman ]; then \
  echo "Something was going wrong. Try a replay" && exit 1; \
fi \
EOT
}

resource "null_resource" "install-nomad-driver-podman" {
  count = var.cleanup ? 0 : 1

  triggers = {
    on_version_change = var.nomad-driver-podman_version
    policy_sha1 = sha1(local.command_downlod_nomad_driver_podman)
  }

  depends_on = [
    null_resource.nomad-install
  ]

  connection {
    user        = var.ssh_user
    private_key = file(var.ssh_private_key)
    host        = var.ssh_ip
    port        = var.port
    timeout     = "1m"
  }

  provisioner "local-exec" {
    command     = local.command_downlod_nomad_driver_podman
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl --user stop nomad || true",
      "systemctl --user enable --now podman.socket || true",
      "rm -rf /home/${var.ssh_user}/nomad-data/plugins/nomad-driver-podman",
      "sleep 4",
      "echo jens",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/.terraform/tmp/nomad-driver-podman/${var.nomad-driver-podman_version}/nomad-driver-podman"
    destination = "/home/${var.ssh_user}/nomad-data/plugins/nomad-driver-podman"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.ssh_user}/nomad-data/plugins/nomad-driver-podman",
      "systemctl --user start nomad || true",
      "sleep 5"
    ]
  }
}

resource "null_resource" "cleanup" {
  count = var.cleanup ? 1 : 0

  connection {
    user        = var.ssh_user
    private_key = file(var.ssh_private_key)
    host        = var.ssh_ip
    port        = var.port
    timeout     = "1m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "systemctl --user disable --now podman.socket",
      "systemctl --user disable --now nomad",
      "rm -f /home/${var.ssh_user}/.config/nomad/server.hcl",
      "rm -f /home/${var.ssh_user}/.config/nomad/config.hcl",
      "rm -f /home/${var.ssh_user}/.config/systemd/user/nomad.service",
      "rm -f /home/${var.ssh_user}/bin/nomad",
      "rm -f /home/${var.ssh_user}/nomad-data/plugins/nomad-driver-podman",
      "sleep 5"
    ]
  }
}
