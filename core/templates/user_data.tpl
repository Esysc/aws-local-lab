#cloud-config
package_update: true
packages:
- nginx
runcmd:
- /bin/bash -c "echo '${index_b64}' | base64 -d > /usr/share/app/index.html"
- /bin/bash -c "cp /usr/share/app/index.html /var/www/html/index.html"
