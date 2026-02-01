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
  config.vm.network "forwarded_port", guest: 6443, host: 6443   # k0s API
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

  # Install k0s and dependencies
  config.vm.provision "shell", name: "install-deps", inline: <<-SHELL
    set -e
    export DEBIAN_FRONTEND=noninteractive

    echo "=== Installing dependencies ==="
    apt-get update
    apt-get install -y curl wget gnupg2 ca-certificates

    # Install Docker
    echo "=== Installing Docker ==="
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker vagrant

    # Install k0s
    echo "=== Installing k0s ==="
    curl -sSLf https://get.k0s.sh | sh

    # Install Helm
    echo "=== Installing Helm ==="
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    echo "=== Dependencies installed ==="
  SHELL

  # Setup k0s cluster
  config.vm.provision "shell", name: "setup-k0s", inline: <<-SHELL
    set -e

    echo "=== Setting up k0s cluster ==="
    k0s install controller --single
    k0s start

    # Wait for k0s
    echo "Waiting for k0s to be ready..."
    sleep 30
    for i in $(seq 1 30); do
      if k0s kubectl get nodes 2>/dev/null | grep -q "Ready"; then
        echo "Node is ready!"
        break
      fi
      echo "Waiting... ($i/30)"
      sleep 5
    done

    # Setup kubeconfig for vagrant user
    mkdir -p /home/vagrant/.kube
    k0s kubeconfig admin > /home/vagrant/.kube/config
    chown -R vagrant:vagrant /home/vagrant/.kube
    chmod 600 /home/vagrant/.kube/config

    # Install Traefik ingress
    echo "=== Installing Traefik ==="
    sudo -u vagrant helm repo add traefik https://traefik.github.io/charts
    sudo -u vagrant helm repo update
    sudo -u vagrant helm install traefik traefik/traefik \
      --namespace kube-system \
      --set ports.web.hostPort=80 \
      --set ports.websecure.hostPort=443

    # Install local-path-provisioner for PVC support
    echo "=== Installing local-path-provisioner ==="
    k0s kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

    # Configure local-path-provisioner to use /mnt/nvme (simulated in test)
    mkdir -p /mnt/nvme
    k0s kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
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

    k0s kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    k0s kubectl rollout restart deployment local-path-provisioner -n local-path-storage

    k0s kubectl get nodes
    k0s kubectl get sc
    echo "=== k0s cluster ready ==="
  SHELL

  # Build and deploy application
  config.vm.provision "shell", name: "deploy-app", privileged: false, inline: <<-SHELL
    set -e
    cd /vagrant

    echo "=== Building Docker images ==="
    sg docker -c "docker build -t ghcr.io/schnappy/monitor:latest backend/"
    sg docker -c "docker build -t ghcr.io/schnappy/monitor-frontend:latest frontend/"

    # Import to k0s containerd
    echo "=== Importing images to k0s ==="
    sg docker -c "docker save ghcr.io/schnappy/monitor:latest" | sudo k0s ctr images import -
    sg docker -c "docker save ghcr.io/schnappy/monitor-frontend:latest" | sudo k0s ctr images import -

    # Deploy with Helm
    echo "=== Deploying application ==="
    helm upgrade --install monitor backend/helm/monitor \
      --namespace monitor \
      --create-namespace \
      --set postgres.password=vagrant \
      --set app.image.pullPolicy=Never \
      --set frontend.image.pullPolicy=Never \
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

    echo "=== Installing Node.js for Playwright ==="
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs

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
    BASE_URL=http://localhost npx playwright test --reporter=list

    echo ""
    echo "=========================================="
    echo "  E2E Tests passed!"
    echo "=========================================="
  SHELL
end
