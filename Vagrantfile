# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Test environment for Monitor application
# Target: Raspberry Pi 5 with 8GB RAM running Raspbian Trixie Lite
#
# Requirements:
#   - Vagrant with libvirt provider (for ARM64 emulation)
#   - Or run on actual ARM64 host
#
# Usage:
#   vagrant up
#   vagrant ssh
#   vagrant destroy -f

Vagrant.configure("2") do |config|
  # Debian Trixie ARM64 (closest to Raspbian Trixie Lite)
  config.vm.box = "debian/trixie64"
  config.vm.hostname = "monitor-pi5-test"

  # Network
  config.vm.network "forwarded_port", guest: 80, host: 8080
  config.vm.network "forwarded_port", guest: 6443, host: 6443   # k3s API
  config.vm.network "forwarded_port", guest: 30000, host: 30000 # Grafana NodePort

  # Simulate Pi 5 8GB resources
  config.vm.provider "libvirt" do |lv|
    lv.memory = 8192
    lv.cpus = 4
    lv.driver = "kvm"
    lv.machine_type = "q35"
  end

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "8192"
    vb.cpus = 4
    vb.name = "monitor-pi5-test"
  end

  # Sync project
  config.vm.synced_folder ".", "/vagrant", type: "rsync",
    rsync__exclude: [".git/", "node_modules/", "build/", "dist/", ".gradle/"]

  # Install system dependencies
  config.vm.provision "shell", name: "install-deps", inline: <<-SHELL
    set -e
    export DEBIAN_FRONTEND=noninteractive

    echo "=== Installing dependencies ==="
    apt-get update
    apt-get install -y curl wget gnupg2 ca-certificates zip unzip

    # Install k3s (includes Traefik ingress and local-path-provisioner)
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
  config.vm.provision "shell", name: "install-sdks", privileged: false, inline: <<-SHELL
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
  config.vm.provision "shell", name: "setup-k3s", inline: <<-SHELL
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
  config.vm.provision "shell", name: "deploy-app", privileged: false, inline: <<-SHELL
    set -e
    cd /vagrant

    # Source sdkman and nvm
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build backend JAR
    echo "=== Building backend JAR ==="
    cd /vagrant/backend
    ./gradlew bootJar --no-daemon -x test

    # Build frontend dist
    echo "=== Building frontend ==="
    cd /vagrant/frontend
    npm ci --silent
    VITE_GIT_HASH=$GIT_HASH VITE_BUILD_TIME=$BUILD_TIME npm run build

    # Stage artifacts and build images with nerdctl (using k3s containerd)
    echo "=== Building container images ==="
    STAGE=$(mktemp -d)

    # Backend: copy JAR + Dockerfile.runtime
    mkdir -p "$STAGE/backend"
    cp /vagrant/backend/build/libs/*.jar "$STAGE/backend/app.jar"
    cp /vagrant/backend/Dockerfile.runtime "$STAGE/backend/Dockerfile"

    # Frontend: copy dist + runtime files
    mkdir -p "$STAGE/frontend"
    cp -r /vagrant/frontend/dist "$STAGE/frontend/"
    cp /vagrant/frontend/Dockerfile.runtime "$STAGE/frontend/Dockerfile"
    cp /vagrant/frontend/nginx.conf.template "$STAGE/frontend/"
    cp /vagrant/frontend/docker-entrypoint.sh "$STAGE/frontend/"

    # Build directly into k3s containerd (no Docker daemon, no import step)
    sudo nerdctl --address /run/k3s/containerd/containerd.sock --namespace k8s.io \
      build -t ghcr.io/schnappy/monitor:latest "$STAGE/backend/"
    sudo nerdctl --address /run/k3s/containerd/containerd.sock --namespace k8s.io \
      build -t ghcr.io/schnappy/monitor-frontend:latest "$STAGE/frontend/"
    rm -rf "$STAGE"

    # Deploy with Helm
    echo "=== Deploying application ==="
    helm upgrade --install monitor /vagrant/backend/helm/monitor \
      --namespace monitor \
      --create-namespace \
      --set postgres.password=vagrant \
      --set app.image.pullPolicy=Never \
      --set frontend.image.pullPolicy=Never \
      --set "app.gitHash=$GIT_HASH" \
      --set "app.buildTime=$BUILD_TIME" \
      --set "app.ingress.host=" \
      --wait \
      --timeout 10m

    echo ""
    echo "=========================================="
    echo "  Deployment complete!"
    echo "=========================================="
    kubectl get pods -n monitor
    echo ""
    echo "Access: http://localhost:8080"
  SHELL

  # Run E2E tests with Playwright
  config.vm.provision "shell", name: "e2e-tests", privileged: false, inline: <<-SHELL
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
