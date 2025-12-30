#cloud-config
package_update: true
packages:
  - openssh-server
runcmd:
  - mkdir -p /root/.ssh
  - /bin/bash -c "echo '${pubkey_b64}' | base64 -d > /root/.ssh/authorized_keys"
  - chmod 700 /root/.ssh
  - chmod 600 /root/.ssh/authorized_keys
