# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Two-VM test environment for Schnappy platform
#
#   kubeadm  192.168.56.10  — kubeadm node (Calico CNI, Istio, full stack)
#   vault-pi 192.168.56.20  — simulates Raspberry Pi unseal Vault (transit engine)
#
# Host requirements:
#   - Vagrant with libvirt or VirtualBox provider
#   - Tuned for: Intel Core Ultra 125H (14C/18T) + 32GB RAM
#     kubeadm: 10 CPUs, 22GB — vault-pi: 2 CPUs, 4GB — leaves 6 threads + 6GB for host
#
# Usage:
#   vagrant up                          # Start both VMs
#   vagrant up kubeadm                  # Start kubeadm VM only
#   vagrant up vault-pi                 # Start vault-pi VM only
#   vagrant ssh kubeadm                 # SSH into kubeadm node
#   vagrant ssh vault-pi                # SSH into vault-pi
#   vagrant destroy -f                  # Destroy both VMs
#
# After 'vagrant up', run the tiered bootstrap:
#   cd deploy/ansible
#   # Tier 0: bootstrap.sh installs cert-manager, ESO, Istio, Velero
#   # Then: Vault → Forgejo → ArgoCD → Tier 1 auto-syncs
#   ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault-pi.yml \
#     -e @vars/vault.yml -e @vars/vault-vagrant.yml
#   ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault.yml \
#     -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml

Vagrant.configure("2") do |config|

  # ══════════════════════════════════════════════════════════════════
  # vault-pi VM — simulates Raspberry Pi transit unseal Vault
  # Lightweight: only needs Vault binary + systemd
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "vault-pi" do |vpi|
    vpi.vm.box = "debian/trixie64"
    vpi.vm.hostname = "vault-pi"

    # No synced folders — repos are pushed to Forgejo via the test playbook
    vpi.vm.synced_folder ".", "/vagrant", disabled: true

    # Private network for vault-pi ↔ kubeadm communication
    vpi.vm.network "private_network", ip: "192.168.56.20"

    # Forward ports for debugging from host
    vpi.vm.network "forwarded_port", guest: 8200, host: 8300   # Vault
    vpi.vm.network "forwarded_port", guest: 3000, host: 3030   # Forgejo
    vpi.vm.network "forwarded_port", guest: 9000, host: 9090   # MinIO

    vpi.vm.provider "libvirt" do |lv|
      lv.memory = 4096
      lv.cpus = 2
      lv.driver = "kvm"
    end

    vpi.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
      vb.name = "vault-pi"
    end

    # Minimal bootstrap — Ansible handles the rest via setup-vault-pi.yml
    vpi.vm.provision "shell", name: "bootstrap", inline: <<-SHELL
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y curl unzip jq ufw openssl python3 git

      # Persist private network config (vagrant-libvirt may not configure eth1 on Debian trixie)
      if ! grep -q eth1 /etc/network/interfaces; then
        cat >> /etc/network/interfaces << 'EOF'

auto eth1
iface eth1 inet static
  address 192.168.56.20
  netmask 255.255.255.0
EOF
        ifup eth1 || true
      fi

      # Install Forgejo (lightweight git forge, runs outside the cluster)
      echo "=== Installing Forgejo ==="
      FORGEJO_VERSION=14.0.3
      ARCH=$(dpkg --print-architecture)
      curl -sSL "https://code.forgejo.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-${ARCH}" -o /usr/local/bin/forgejo
      chmod +x /usr/local/bin/forgejo

      # Create forgejo user and directories
      useradd --system --shell /bin/bash --home-dir /var/lib/forgejo forgejo 2>/dev/null || true
      mkdir -p /var/lib/forgejo/{data,repos,log,custom/conf}
      chown -R forgejo:forgejo /var/lib/forgejo

      # Forgejo config
      cat > /var/lib/forgejo/custom/conf/app.ini << 'FEOF'
APP_NAME = Forgejo
RUN_USER = forgejo

[server]
HTTP_PORT = 3000
HTTP_ADDR = 0.0.0.0
ROOT_URL = http://192.168.56.20:3000/
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

      # Systemd service
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

      # Wait for Forgejo to start
      for i in $(seq 1 30); do
        curl -sf http://localhost:3000/ >/dev/null 2>&1 && break
        sleep 2
      done

      # Create admin user
      su - forgejo -c "forgejo admin user create \
        --admin --username forgejo_admin \
        --password vagrant-forgejo-pw \
        --email admin@test.local \
        --config /var/lib/forgejo/custom/conf/app.ini" 2>/dev/null || true

      echo "Forgejo running at http://192.168.56.20:3000/"

      # Install MinIO (Velero backup target, runs outside the cluster)
      echo "=== Installing MinIO ==="
      ARCH=$(dpkg --print-architecture)
      curl -sSL "https://dl.min.io/server/minio/release/linux-${ARCH}/minio" -o /usr/local/bin/minio
      chmod +x /usr/local/bin/minio

      # Create minio user and data directory
      useradd --system --shell /bin/false --home-dir /var/lib/minio minio 2>/dev/null || true
      mkdir -p /var/lib/minio/data
      chown -R minio:minio /var/lib/minio

      # Systemd service
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
ExecStart=/usr/local/bin/minio server /var/lib/minio/data --address :9000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
MEOF
      systemctl daemon-reload
      systemctl enable --now minio

      # Wait for MinIO to start
      for i in $(seq 1 30); do
        curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1 && break
        sleep 2
      done
      echo "MinIO running at http://192.168.56.20:9000/"

      echo "vault-pi bootstrap complete"
    SHELL
  end

  # ══════════════════════════════════════════════════════════════════
  # kubeadm VM — vanilla Kubernetes with Calico CNI
  # Matches production: kubeadm 1.34, Calico nftables, Istio sidecar
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "kubeadm", primary: true do |node|
    node.vm.box = "debian/trixie64"
    node.vm.hostname = "schnappy-test"

    # NAT port forwards (host → guest)
    node.vm.network "forwarded_port", guest: 80, host: 8080
    node.vm.network "forwarded_port", guest: 443, host: 8443
    node.vm.network "forwarded_port", guest: 6443, host: 6443   # k8s API

    # Private network for kubeadm ↔ vault-pi communication
    node.vm.network "private_network", ip: "192.168.56.10"

    # Sized for Core Ultra 125H (14C/18T) + 32GB: 10 CPUs + 22GB
    node.vm.provider "libvirt" do |lv|
      lv.memory = 22528
      lv.cpus = 10
      lv.driver = "kvm"
      lv.machine_type = "q35"
      lv.cpu_mode = "host-passthrough"
    end

    node.vm.provider "virtualbox" do |vb|
      vb.memory = 22528
      vb.cpus = 10
      vb.name = "schnappy-test"
    end

    # DNS: resolve vault.schnappy.io to vault-pi VM
    node.vm.provision "shell", name: "hosts-vault", inline: <<-SHELL
      grep -q "vault.schnappy.io" /etc/hosts || \
        echo "192.168.56.20 vault.schnappy.io" >> /etc/hosts
      echo "DNS: vault.schnappy.io -> 192.168.56.20"
    SHELL

    # Sync project
    node.vm.synced_folder ".", "/vagrant", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"]

    # Sync sibling repos for integration testing
    node.vm.synced_folder "../infra", "/vagrant-infra", type: "rsync",
      rsync__exclude: [".git/"],
      create: true
    node.vm.synced_folder "../platform", "/vagrant-platform", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    node.vm.synced_folder "../monitor", "/vagrant-monitor", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"],
      create: true
    node.vm.synced_folder "../site", "/vagrant-site", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/"],
      create: true
    node.vm.synced_folder "../admin", "/vagrant-admin", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    node.vm.synced_folder "../chat", "/vagrant-chat", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    node.vm.synced_folder "../chess", "/vagrant-chess", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true

    # Install system dependencies + kubeadm
    node.vm.provision "shell", name: "install-deps", inline: <<-SHELL
      set -e
      export DEBIAN_FRONTEND=noninteractive

      echo "=== Installing dependencies ==="
      apt-get update
      apt-get install -y curl wget gnupg2 ca-certificates zip unzip git \
        apt-transport-https socat conntrack ipset nftables

      # Disable swap (required for kubeadm)
      swapoff -a
      sed -i '/swap/d' /etc/fstab

      # Load required kernel modules
      cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
      modprobe overlay
      modprobe br_netfilter

      # Sysctl for Kubernetes networking
      cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
      sysctl --system

      # Install containerd from Docker repo (Debian's version is too old for kubeadm 1.34)
      echo "=== Installing containerd ==="
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

      # Install kubeadm, kubelet, kubectl
      echo "=== Installing kubeadm ==="
      KUBE_VERSION=1.34
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key | \
        gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | \
        tee /etc/apt/sources.list.d/kubernetes.list
      apt-get update
      apt-get install -y kubelet kubeadm kubectl
      apt-mark hold kubelet kubeadm kubectl
      systemctl enable kubelet

      # Install Helm
      echo "=== Installing Helm ==="
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      # Install nerdctl + buildkit for image building
      echo "=== Installing nerdctl + buildkit ==="
      NERDCTL_VERSION=2.0.4
      ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
      curl -sSL "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-full-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /usr/local
      systemctl enable --now buildkit

      echo "=== Dependencies installed ==="
    SHELL

    # Install sdkman + Java and nvm + Node.js for vagrant user
    node.vm.provision "shell", name: "install-sdks", privileged: false, inline: <<-SHELL
      set -e

      # Install SDKMAN and Java
      echo "=== Installing SDKMAN ==="
      curl -s "https://get.sdkman.io" | bash
      source "$HOME/.sdkman/bin/sdkman-init.sh"
      echo "=== Installing Java 25 ==="
      sdk install java 25-open

      # Install nvm and Node.js
      echo "=== Installing nvm ==="
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
      echo "=== Installing Node.js 22 ==="
      nvm install 22

      echo "=== SDKs installed ==="
      java -version
      node --version
    SHELL

    # Initialize kubeadm cluster
    node.vm.provision "shell", name: "setup-kubeadm", inline: <<-SHELL
      set -e

      # Base firewall rules (survives CNI removal/crash)
      echo "=== Configuring base nftables ==="
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

      echo "=== Initializing kubeadm cluster ==="
      kubeadm init \
        --pod-network-cidr=10.42.0.0/16 \
        --service-cidr=10.43.0.0/16 \
        --apiserver-advertise-address=192.168.56.10 \
        --node-name=schnappy-test

      # Setup kubeconfig for root
      mkdir -p /root/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config

      # Setup kubeconfig for vagrant user
      mkdir -p /home/vagrant/.kube
      cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
      chown -R vagrant:vagrant /home/vagrant/.kube

      # Allow scheduling on control plane (single node)
      kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

      # Install Calico CNI (nftables mode, matches production)
      echo "=== Installing Calico CNI ==="
      kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/tigera-operator.yaml

      # Wait for Installation CRD to be registered by the operator
      echo "Waiting for Calico CRDs..."
      for i in $(seq 1 30); do
        kubectl get crd installations.operator.tigera.io >/dev/null 2>&1 && break
        sleep 2
      done

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

      echo "=== Waiting for Calico ==="
      for i in $(seq 1 60); do
        if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
          echo "Node is ready!"
          break
        fi
        echo "Waiting... ($i/60)"
        sleep 5
      done

      # Install local-path-provisioner
      echo "=== Installing local-path-provisioner ==="
      kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
      kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
      mkdir -p /mnt/storage

      kubectl get nodes
      kubectl get sc
      echo "=== kubeadm cluster ready ==="
    SHELL

    # Run Tier 0 bootstrap
    node.vm.provision "shell", name: "bootstrap-tier0", privileged: false, inline: <<-SHELL
      set -e
      echo "=== Running Tier 0 bootstrap ==="
      export INFRA_DIR=/vagrant-infra
      /vagrant/bootstrap.sh all
      echo "=== Tier 0 bootstrap complete ==="
    SHELL

    # Build artifacts locally and deploy
    node.vm.provision "shell", name: "deploy-app", privileged: false, inline: <<-SHELL
      set -e
      cd /vagrant

      # Source sdkman and nvm
      source "$HOME/.sdkman/bin/sdkman-init.sh"
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

      # Skip if monitor repo not synced (infra-only tests)
      if [ ! -d /vagrant-monitor/src ]; then
        echo "=== No monitor repo — skipping app build ==="
        exit 0
      fi

      # Build backend JAR (monitor repo has gradle at root)
      echo "=== Building backend JAR ==="
      cd /vagrant-monitor
      ./gradlew bootJar --no-daemon -x test

      # Build frontend dist (site repo)
      echo "=== Building frontend ==="
      cd /vagrant-site
      npm ci --silent
      GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      VITE_GIT_HASH=$GIT_HASH VITE_BUILD_TIME=$BUILD_TIME npm run build

      # Stage artifacts and build images with nerdctl
      echo "=== Building container images ==="
      STAGE=$(mktemp -d)

      # Backend: copy JAR + Dockerfile.runtime
      mkdir -p "$STAGE/backend"
      cp /vagrant-monitor/build/libs/*.jar "$STAGE/backend/app.jar"
      cp /vagrant-monitor/Dockerfile.runtime "$STAGE/backend/Dockerfile"

      # Frontend: copy dist + runtime files
      mkdir -p "$STAGE/frontend"
      cp -r /vagrant-site/dist "$STAGE/frontend/"
      cp /vagrant-site/Dockerfile.runtime "$STAGE/frontend/Dockerfile"
      cp /vagrant-site/nginx.conf "$STAGE/frontend/"
      cp /vagrant-site/nginx.conf.template "$STAGE/frontend/"
      cp /vagrant-site/security-headers.conf "$STAGE/frontend/"
      cp /vagrant-site/security-headers-base.conf "$STAGE/frontend/"
      cp /vagrant-site/docker-entrypoint.sh "$STAGE/frontend/"

      # Build into containerd (nerdctl uses the default containerd socket)
      sudo nerdctl --namespace k8s.io \
        build -t monitor:local "$STAGE/backend/"
      sudo nerdctl --namespace k8s.io \
        build -t monitor-frontend:local "$STAGE/frontend/"
      rm -rf "$STAGE"

      echo ""
      echo "=========================================="
      echo "  Provisioning complete! Images built."
      echo "  Test playbooks will deploy via Helm."
      echo "=========================================="
    SHELL

    # Run E2E tests with Playwright (run: "never" — invoke explicitly with:
    #   vagrant provision kubeadm --provision-with e2e-tests)
    node.vm.provision "shell", name: "e2e-tests", privileged: false, run: "never", inline: <<-SHELL
      set -e
      cd /vagrant

      # Source nvm (Node.js already installed via install-sdks)
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

      echo "=== Installing Playwright dependencies ==="
      cd frontend
      npm ci
      npx playwright install --with-deps chromium

      echo "=== Waiting for app to be ready ==="
      for i in $(seq 1 30); do
        if curl -sf http://localhost/api/actuator/health >/dev/null 2>&1; then
          echo "App is ready!"
          break
        fi
        echo "Waiting for app... ($i/30)"
        sleep 10
      done

      echo "=== Running E2E tests ==="
      BASE_URL=http://localhost npx playwright test --reporter=list --workers=1

      echo ""
      echo "=========================================="
      echo "  E2E Tests passed!"
      echo "=========================================="
    SHELL
  end

end
