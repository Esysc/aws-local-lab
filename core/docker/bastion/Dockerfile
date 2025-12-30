FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-server ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd /root/.ssh
# Allow root login via public key
RUN sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
RUN sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true

# Add an entrypoint that runs a mounted provision script once (cloud-init-like)
RUN mkdir -p /var/lib/local
RUN cat > /usr/local/bin/entrypoint.sh <<'EOF'
#!/bin/sh
set -e
# Run mounted user-data/provision script once if present
if [ -f /tmp/local_provision.sh ] && [ ! -f /var/lib/local/provision_done ]; then
  chmod +x /tmp/local_provision.sh
  /tmp/local_provision.sh || true
  touch /var/lib/local/provision_done
fi
exec /usr/sbin/sshd -D
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
