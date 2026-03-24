# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Two-VM test environment for Monitor application + Vault HA
#
#   k3s      192.168.56.10  — k3s node (monitor app, Vault cluster, ESO, Sealed Secrets)
#   vault-pi 192.168.56.20  — simulates Raspberry Pi unseal Vault (transit engine)
#
# Host requirements:
#   - Vagrant with libvirt or VirtualBox provider
#   - Tuned for: Intel Core Ultra 125H (14C/18T) + 32GB RAM
#     k3s: 10 CPUs, 20GB — vault-pi: 2 CPUs, 4GB — leaves 6 threads + 8GB for host
#
# Usage:
#   vagrant up                          # Start both VMs
#   vagrant up k3s                      # Start k3s VM only
#   vagrant up vault-pi                 # Start vault-pi VM only
#   vagrant ssh k3s                     # SSH into k3s node
#   vagrant ssh vault-pi                # SSH into vault-pi
#   vagrant destroy -f                  # Destroy both VMs
#
# After 'vagrant up', run Ansible playbooks for Vault:
#   cd deploy/ansible
#   ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault-pi.yml \
#     -e @vars/vault.yml -e vault_arch=amd64 -e vault_pi_ip=192.168.56.20
#   ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault.yml \
#     -e @vars/vault.yml -e @vars/vault-pi-runtime.yml

Vagrant.configure("2") do |config|

  # ══════════════════════════════════════════════════════════════════
  # vault-pi VM — simulates Raspberry Pi transit unseal Vault
  # Lightweight: only needs Vault binary + systemd
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "vault-pi" do |vpi|
    vpi.vm.box = "debian/trixie64"
    vpi.vm.hostname = "vault-pi"

    # vault-pi needs no project files — disable default /vagrant synced_folder
    vpi.vm.synced_folder ".", "/vagrant", disabled: true

    # Private network for vault-pi ↔ k3s communication
    vpi.vm.network "private_network", ip: "192.168.56.20"

    # Optional: forward Vault port for debugging from host
    vpi.vm.network "forwarded_port", guest: 8200, host: 8300

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
      apt-get install -y curl unzip jq ufw openssl python3

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

      echo "vault-pi bootstrap complete"
    SHELL
  end

  # ══════════════════════════════════════════════════════════════════
  # k3s VM — k3s cluster with monitor app + Vault cluster
  # Sized for Intel Core 125H dev laptop (32GB RAM): 20GB VM + 8GB host
  # ══════════════════════════════════════════════════════════════════
  config.vm.define "k3s", primary: true do |k3s|
    k3s.vm.box = "debian/trixie64"
    k3s.vm.hostname = "monitor-test"

    # NAT port forwards (host → guest)
    k3s.vm.network "forwarded_port", guest: 80, host: 8080
    k3s.vm.network "forwarded_port", guest: 6443, host: 6443   # k3s API
    k3s.vm.network "forwarded_port", guest: 9090, host: 9090   # Prometheus
    k3s.vm.network "forwarded_port", guest: 30000, host: 30000 # Grafana NodePort

    # Private network for k3s ↔ vault-pi communication
    k3s.vm.network "private_network", ip: "192.168.56.10"

    # Sized for Core Ultra 125H (14C/18T) + 32GB: 10 CPUs + 20GB for k3s
    k3s.vm.provider "libvirt" do |lv|
      lv.memory = 22528  # 22GB — k3s + Vault + full monitor stack (host has 30GB, vault-pi uses 4GB)
      lv.cpus = 10       # 10 of 18 threads — leaves 7 for host + 1 for vault-pi
      lv.driver = "kvm"
      lv.machine_type = "q35"
      lv.cpu_mode = "host-passthrough"  # expose AVX/SSE for JVM + postgres
    end

    k3s.vm.provider "virtualbox" do |vb|
      vb.memory = 22528
      vb.cpus = 10
      vb.name = "monitor-test"
    end

    # DNS: resolve vault.schnappy.io to vault-pi VM
    k3s.vm.provision "shell", name: "hosts-vault", inline: <<-SHELL
      grep -q "vault.schnappy.io" /etc/hosts || \
        echo "192.168.56.20 vault.schnappy.io" >> /etc/hosts
      echo "DNS: vault.schnappy.io -> 192.168.56.20"
    SHELL

    # Sync project
    k3s.vm.synced_folder ".", "/vagrant", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"]

    # Sync sibling repos for integration testing
    k3s.vm.synced_folder "../platform", "/vagrant-platform", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    k3s.vm.synced_folder "../monitor", "/vagrant-monitor", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"],
      create: true
    k3s.vm.synced_folder "../site", "/vagrant-site", type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "build/", "dist/"],
      create: true
    k3s.vm.synced_folder "../api-gateway", "/vagrant-gateway", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    k3s.vm.synced_folder "../admin", "/vagrant-admin", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    k3s.vm.synced_folder "../chat", "/vagrant-chat", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true
    k3s.vm.synced_folder "../chess", "/vagrant-chess", type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"],
      create: true

    # Install system dependencies
    k3s.vm.provision "shell", name: "install-deps", inline: <<-SHELL
      set -e
      export DEBIAN_FRONTEND=noninteractive

      echo "=== Installing dependencies ==="
      apt-get update
      apt-get install -y curl wget gnupg2 ca-certificates zip unzip git

      # Registry mirror — cache Docker Hub, Elastic, Quay via Pi pull-through cache
      echo "=== Configuring registry mirrors ==="
      mkdir -p /etc/rancher/k3s
      cat > /etc/rancher/k3s/registries.yaml << 'REGEOF'
mirrors:
  docker.io:
    endpoint:
      - "http://192.168.11.4:8082"
  docker.elastic.co:
    endpoint:
      - "http://192.168.11.4:8082"
  quay.io:
    endpoint:
      - "http://192.168.11.4:8082"
REGEOF

      # Install k3s (includes Traefik ingress and local-path-provisioner)
      # k3s reads registries.yaml on startup and configures containerd mirrors
      echo "=== Installing k3s ==="
      curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

      # Install nerdctl + buildkit (containerd-native image builder, no Docker daemon needed)
      echo "=== Installing nerdctl + buildkit ==="
      NERDCTL_VERSION=2.0.4
      ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
      curl -sSL "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-full-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C /usr/local
      systemctl enable --now buildkit

      # Install Helm
      echo "=== Installing Helm ==="
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      echo "=== Dependencies installed ==="
    SHELL

    # Install sdkman + Java and nvm + Node.js for vagrant user
    k3s.vm.provision "shell", name: "install-sdks", privileged: false, inline: <<-SHELL
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

    # Setup k3s cluster
    k3s.vm.provision "shell", name: "setup-k3s", inline: <<-SHELL
      set -e

      echo "=== Waiting for k3s to be ready ==="
      for i in $(seq 1 30); do
        if k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; then
          echo "Node is ready!"
          break
        fi
        echo "Waiting... ($i/30)"
        sleep 5
      done

      # Setup kubeconfig for vagrant user
      mkdir -p /home/vagrant/.kube
      cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
      chown -R vagrant:vagrant /home/vagrant/.kube
      chmod 600 /home/vagrant/.kube/config

      # Configure local-path-provisioner to use /mnt/nvme (simulated in test)
      mkdir -p /mnt/nvme
      k3s kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: kube-system
data:
  config.json: |-
    {
      "nodePathMap": [
        {
          "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
          "paths": ["/mnt/nvme"]
        }
      ]
    }
  setup: |-
    #!/bin/sh
    set -eu
    mkdir -m 0777 -p "$VOL_DIR"
  teardown: |-
    #!/bin/sh
    set -eu
    rm -rf "$VOL_DIR"
  helperPod.yaml: |-
    apiVersion: v1
    kind: Pod
    metadata:
      name: helper-pod
    spec:
      containers:
      - name: helper-pod
        image: busybox:1.36
EOF

      k3s kubectl get nodes
      k3s kubectl get sc
      echo "=== k3s cluster ready ==="
    SHELL

    # Build artifacts locally and deploy
    k3s.vm.provision "shell", name: "deploy-app", privileged: false, inline: <<-SHELL
      set -e
      cd /vagrant

      # Source sdkman and nvm
      source "$HOME/.sdkman/bin/sdkman-init.sh"
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

      GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

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
      VITE_GIT_HASH=$GIT_HASH VITE_BUILD_TIME=$BUILD_TIME npm run build

      # Stage artifacts and build images with nerdctl (using k3s containerd)
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

      # Build directly into k3s containerd (no Docker daemon, no import step)
      sudo nerdctl --address /run/k3s/containerd/containerd.sock --namespace k8s.io \
        build -t monitor:local "$STAGE/backend/"
      sudo nerdctl --address /run/k3s/containerd/containerd.sock --namespace k8s.io \
        build -t monitor-frontend:local "$STAGE/frontend/"
      rm -rf "$STAGE"

      # Images built — test playbooks handle their own helm deploys
      echo ""
      echo "=========================================="
      echo "  Provisioning complete! Images built."
      echo "  Test playbooks will deploy via Helm."
      echo "=========================================="
    SHELL

    # Run E2E tests with Playwright (run: "never" — invoke explicitly with:
    #   vagrant provision k3s --provision-with e2e-tests)
    k3s.vm.provision "shell", name: "e2e-tests", privileged: false, run: "never", inline: <<-SHELL
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
