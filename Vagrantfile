# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Three-VM test environment for Schnappy platform
#
#   pi1      192.168.56.20  — Pi services (Vault, Forgejo, MinIO, Keycloak, Postgres primary)
#   pi2      192.168.56.21  — Pi services mirror (same stack, Postgres replica)
#   kubeadm  192.168.56.10  — kubeadm node (Calico/Cilium CNI, full stack)
#
# Host requirements (Intel Core Ultra 125H, 32GB RAM):
#   pi1: 2 CPUs, 4GB — pi2: 2 CPUs, 4GB — kubeadm: 8 CPUs, 18GB
#   Leaves 6 threads + 6GB for host
#
# Usage:
#   vagrant up                    # Start all 3 VMs
#   vagrant up pi1 pi2            # Start Pi pair only
#   vagrant up kubeadm            # Start k8s node only
#   vagrant destroy -f            # Destroy all

# Shared Pi provisioning script
PI_SERVICES_SCRIPT = <<-'PISCRIPT'
  set -e
  export DEBIAN_FRONTEND=noninteractive

  PI_IP=$1
  PEER_IP=$2
  PI_NAME=$3

  apt-get update -qq
  apt-get install -y curl unzip jq ufw openssl python3 git postgresql postgresql-client

  # Persist private network config
  if ! grep -q eth1 /etc/network/interfaces; then
    cat >> /etc/network/interfaces << EOF

auto eth1
iface eth1 inet static
  address $PI_IP
  netmask 255.255.255.0
EOF
    ifup eth1 || true
  fi

  # UFW
  ufw allow 22/tcp comment "SSH"
  ufw allow 3000/tcp comment "Forgejo"
  ufw allow 8080/tcp comment "Keycloak"
  ufw allow 8200/tcp comment "Vault"
  ufw allow 9000/tcp comment "MinIO"
  ufw allow 5432/tcp comment "Postgres"

  # ── Forgejo ──
  echo "=== Installing Forgejo ==="
  FORGEJO_VERSION=14.0.3
  ARCH=$(dpkg --print-architecture)
  curl -sSL "https://code.forgejo.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-${ARCH}" -o /usr/local/bin/forgejo
  chmod +x /usr/local/bin/forgejo

  useradd --system --shell /bin/bash --home-dir /var/lib/forgejo forgejo 2>/dev/null || true
  mkdir -p /var/lib/forgejo/{data,repos,log,custom/conf}
  chown -R forgejo:forgejo /var/lib/forgejo

  cat > /var/lib/forgejo/custom/conf/app.ini << FEOF
APP_NAME = Forgejo
RUN_USER = forgejo

[server]
HTTP_PORT = 3000
HTTP_ADDR = 0.0.0.0
ROOT_URL = http://${PI_IP}:3000/
APP_DATA_PATH = /var/lib/forgejo/data
LFS_START_SERVER = false

[database]
DB_TYPE = sqlite3
PATH = /var/lib/forgejo/data/forgejo.db

[repository]
ROOT = /var/lib/forgejo/repos

[log]
ROOT_PATH = /var/lib/forgejo/log
LEVEL = Warn

[security]
INSTALL_LOCK = true
FEOF
  chown forgejo:forgejo /var/lib/forgejo/custom/conf/app.ini

  cat > /etc/systemd/system/forgejo.service << 'SEOF'
[Unit]
Description=Forgejo Git Forge
After=network.target
[Service]
Type=simple
User=forgejo
Group=forgejo
WorkingDirectory=/var/lib/forgejo
ExecStart=/usr/local/bin/forgejo web --config /var/lib/forgejo/custom/conf/app.ini
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SEOF
  systemctl daemon-reload
  systemctl enable --now forgejo

  until curl -sf http://localhost:3000/ >/dev/null 2>&1; do sleep 2; done

  su - forgejo -c "forgejo admin user create \
    --admin --username forgejo_admin \
    --password vagrant-forgejo-pw \
    --email admin@test.local \
    --config /var/lib/forgejo/custom/conf/app.ini" 2>/dev/null || true

  # ── MinIO ──
  echo "=== Installing MinIO ==="
  curl -sSL "https://dl.min.io/server/minio/release/linux-${ARCH}/minio" -o /usr/local/bin/minio
  chmod +x /usr/local/bin/minio
  curl -sSL "https://dl.min.io/client/mc/release/linux-${ARCH}/mc" -o /usr/local/bin/mc
  chmod +x /usr/local/bin/mc

  useradd --system --shell /bin/false --home-dir /var/lib/minio minio 2>/dev/null || true
  mkdir -p /var/lib/minio/data
  chown -R minio:minio /var/lib/minio

  cat > /etc/systemd/system/minio.service << 'MEOF'
[Unit]
Description=MinIO Object Storage
After=network.target
[Service]
Type=simple
User=minio
Group=minio
Environment="MINIO_ROOT_USER=velero-admin"
Environment="MINIO_ROOT_PASSWORD=velero-vagrant-secret"
Environment="MINIO_SITE_NAME=${PI_NAME}"
ExecStart=/usr/local/bin/minio server /var/lib/minio/data --address :9000
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
MEOF
  # Fix env var in service file
  sed -i "s/\${PI_NAME}/$PI_NAME/" /etc/systemd/system/minio.service
  systemctl daemon-reload
  systemctl enable --now minio
  until curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1; do sleep 2; done
  HOME=/tmp mc alias set local http://localhost:9000 velero-admin velero-vagrant-secret
  HOME=/tmp mc mb local/velero --ignore-existing
  HOME=/tmp mc mb local/pg-dump --ignore-existing

  # ── Postgres ──
  echo "=== Configuring Postgres ==="
  sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'kc-db-vagrant-pw';" 2>/dev/null
  sudo -u postgres createdb keycloak 2>/dev/null || true
  echo "host all all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
  echo "host replication all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
  sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
  echo "wal_level = replica" >> /etc/postgresql/*/main/postgresql.conf
  echo "max_wal_senders = 3" >> /etc/postgresql/*/main/postgresql.conf
  systemctl restart postgresql

  # ── Keycloak ──
  echo "=== Installing Keycloak ==="
  KC_VERSION=26.5.7
  curl -sSL "https://github.com/keycloak/keycloak/releases/download/${KC_VERSION}/keycloak-${KC_VERSION}.tar.gz" | tar -xz -C /opt
  ln -sf /opt/keycloak-${KC_VERSION} /opt/keycloak
  useradd --system --shell /bin/false --home-dir /opt/keycloak keycloak 2>/dev/null || true
  chown -R keycloak:keycloak /opt/keycloak-${KC_VERSION}

  cat > /etc/systemd/system/keycloak.service << KCEOF
[Unit]
Description=Keycloak SSO
After=network.target postgresql.service
[Service]
Type=exec
User=keycloak
Group=keycloak
Environment=KC_DB=postgres
Environment=KC_DB_URL=jdbc:postgresql://localhost:5432/keycloak
Environment=KC_DB_USERNAME=postgres
Environment=KC_DB_PASSWORD=kc-db-vagrant-pw
Environment=KC_HOSTNAME_STRICT=false
Environment=KC_HTTP_ENABLED=true
Environment=KC_HTTP_PORT=8080
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=admin
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=admin-test-pw
ExecStart=/opt/keycloak/bin/kc.sh start-dev
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
KCEOF
  systemctl daemon-reload
  systemctl enable --now keycloak

  echo "Waiting for Keycloak..."
  until curl -sf http://localhost:8080/realms/master >/dev/null 2>&1; do sleep 5; done

  # Create schnappy realm
  KC_TOKEN=$(curl -sf -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
    -d "client_id=admin-cli&grant_type=password&username=admin&password=admin-test-pw" | \
    python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
  curl -sf -X POST http://localhost:8080/admin/realms \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"realm":"schnappy","enabled":true}' || true

  echo "$PI_NAME bootstrap complete"
  echo "  Forgejo:  http://${PI_IP}:3000/"
  echo "  MinIO:    http://${PI_IP}:9000/"
  echo "  Keycloak: http://${PI_IP}:8080/"
  echo "  Postgres: ${PI_IP}:5432"
PISCRIPT

Vagrant.configure("2") do |config|

  # ══════════════════════════════════════════════════════════════════
  # Pi-1 — primary services
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "pi1" do |pi|
    pi.vm.box = "debian/trixie64"
    pi.vm.hostname = "pi1"
    pi.vm.synced_folder ".", "/vagrant", disabled: true
    pi.vm.network "private_network", ip: "192.168.56.20"
    pi.vm.network "forwarded_port", guest: 8200, host: 8300
    pi.vm.network "forwarded_port", guest: 3000, host: 3030
    pi.vm.network "forwarded_port", guest: 9000, host: 9090

    pi.vm.provider "libvirt" do |lv|
      lv.memory = 4096
      lv.cpus = 2
      lv.driver = "kvm"
    end

    pi.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
      vb.name = "pi1"
    end

    pi.vm.provision "shell", name: "setup-services", inline: PI_SERVICES_SCRIPT,
      args: ["192.168.56.20", "192.168.56.21", "pi1"]
  end

  # ══════════════════════════════════════════════════════════════════
  # Pi-2 — mirror services
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "pi2" do |pi|
    pi.vm.box = "debian/trixie64"
    pi.vm.hostname = "pi2"
    pi.vm.synced_folder ".", "/vagrant", disabled: true
    pi.vm.network "private_network", ip: "192.168.56.21"
    pi.vm.network "forwarded_port", guest: 8200, host: 8301
    pi.vm.network "forwarded_port", guest: 3000, host: 3031
    pi.vm.network "forwarded_port", guest: 9000, host: 9091

    pi.vm.provider "libvirt" do |lv|
      lv.memory = 4096
      lv.cpus = 2
      lv.driver = "kvm"
    end

    pi.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
      vb.name = "pi2"
    end

    pi.vm.provision "shell", name: "setup-services", inline: PI_SERVICES_SCRIPT,
      args: ["192.168.56.21", "192.168.56.20", "pi2"]
  end

  # ══════════════════════════════════════════════════════════════════
  # kubeadm — Kubernetes cluster
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "kubeadm", primary: true do |node|
    node.vm.box = "debian/trixie64"
    node.vm.hostname = "schnappy-test"
    node.vm.network "forwarded_port", guest: 80, host: 8080
    node.vm.network "forwarded_port", guest: 443, host: 8443
    node.vm.network "forwarded_port", guest: 6443, host: 6443
    node.vm.network "private_network", ip: "192.168.56.10"

    node.vm.provider "libvirt" do |lv|
      lv.memory = 18432   # 18GB (reduced from 22 to fit 3 VMs)
      lv.cpus = 8
      lv.driver = "kvm"
      lv.machine_type = "q35"
      lv.cpu_mode = "host-passthrough"
    end

    node.vm.provider "virtualbox" do |vb|
      vb.memory = 18432
      vb.cpus = 8
      vb.name = "schnappy-test"
    end

    # DNS: resolve Pi hostnames
    node.vm.provision "shell", name: "hosts", inline: <<-SHELL
      grep -q "pi1" /etc/hosts || echo "192.168.56.20 pi1 vault.schnappy.io" >> /etc/hosts
      grep -q "pi2" /etc/hosts || echo "192.168.56.21 pi2" >> /etc/hosts
    SHELL

    # Sync repos
    node.vm.synced_folder ".", "/vagrant", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"]
    node.vm.synced_folder "../infra", "/vagrant-infra", type: "rsync",
      rsync__exclude: [".git/"], create: true
    node.vm.synced_folder "../platform", "/vagrant-platform", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true
    node.vm.synced_folder "../monitor", "/vagrant-monitor", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"], create: true
    node.vm.synced_folder "../site", "/vagrant-site", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/"], create: true
    node.vm.synced_folder "../admin", "/vagrant-admin", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true
    node.vm.synced_folder "../chat", "/vagrant-chat", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true
    node.vm.synced_folder "../chess", "/vagrant-chess", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true

    # Install system dependencies + kubeadm
    node.vm.provision "shell", name: "install-deps", inline: <<-SHELL
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y curl wget gnupg2 ca-certificates zip unzip git \
        apt-transport-https socat conntrack ipset nftables

      swapoff -a
      sed -i '/swap/d' /etc/fstab

      cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
      modprobe overlay
      modprobe br_netfilter

      cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
      sysctl --system

      # containerd from Docker repo
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list
      apt-get update
      apt-get install -y containerd.io
      mkdir -p /etc/containerd
      containerd config default > /etc/containerd/config.toml
      sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
      systemctl restart containerd
      systemctl enable containerd

      # kubeadm
      KUBE_VERSION=1.34
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | \
        gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | \
        tee /etc/apt/sources.list.d/kubernetes.list
      apt-get update
      apt-get install -y kubelet kubeadm kubectl
      apt-mark hold kubelet kubeadm kubectl
      systemctl enable kubelet

      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    SHELL

    # SDKs (no set -e, sdkman has harmless errors)
    node.vm.provision "shell", name: "install-sdks", privileged: false, inline: <<-SHELL
      curl -s "https://get.sdkman.io" | bash
      source "$HOME/.sdkman/bin/sdkman-init.sh"
      sdk install java 25-open
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
      nvm install 22
    SHELL

    # kubeadm init + Calico
    node.vm.provision "shell", name: "setup-kubeadm", inline: <<-SHELL
      set -e

      # Base nftables
      cat > /etc/nftables.conf << 'NFTEOF'
#!/usr/sbin/nft -f
table ip base-filter {
  chain input {
    type filter hook input priority -10; policy accept;
    ct state established,related accept
    iif lo accept
    tcp dport 22 accept
    tcp dport 6443 accept
    icmp type echo-request accept
  }
  chain forward {
    type filter hook forward priority -10; policy accept;
  }
  chain output {
    type filter hook output priority -10; policy accept;
  }
}
NFTEOF
      systemctl enable nftables
      nft -f /etc/nftables.conf

      kubeadm init \
        --pod-network-cidr=10.42.0.0/16 \
        --service-cidr=10.43.0.0/16 \
        --apiserver-advertise-address=192.168.56.10 \
        --node-name=schnappy-test

      mkdir -p /root/.kube /home/vagrant/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config
      cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown -R vagrant:vagrant /home/vagrant/.kube
      kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

      # Calico
      kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/tigera-operator.yaml
      until kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; do sleep 5; done

      cat <<'EOF' | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - cidr: 10.42.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
    linuxDataplane: Nftables
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

      until kubectl get nodes | grep -q " Ready"; do sleep 5; done

      # local-path-provisioner
      kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
      kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
      mkdir -p /mnt/storage
      kubectl get nodes
      echo "=== kubeadm cluster ready ==="
    SHELL

    # Tier 0 bootstrap
    node.vm.provision "shell", name: "bootstrap-tier0", privileged: false, inline: <<-SHELL
      set -e
      export INFRA_DIR=/vagrant-infra
      /vagrant/bootstrap.sh all
    SHELL
  end

end
