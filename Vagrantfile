# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Three-VM test environment for Schnappy platform
#
#   pi1      192.168.56.20  — Pi services (full HA stack)
#   pi2      192.168.56.21  — Pi services mirror (full HA stack)
#   kubeadm  192.168.56.10  — kubeadm cluster node
#
# Host requirements (Intel Core Ultra 125H, 32GB RAM):
#   pi1: 2 CPUs, 4GB — pi2: 2 CPUs, 4GB — kubeadm: 8 CPUs, 18GB
#
# VIP: 192.168.56.50 (Keepalived, floats between pi1/pi2)
#
# Provisioning: Vagrant only creates VMs with basic packages.
# Use `task test:dual-pi` or `task test:full` to deploy services via Ansible.
#
# Usage:
#   vagrant up                    # Start all 3 VMs
#   vagrant up pi1 pi2            # Start Pi pair only
#   vagrant destroy -f            # Destroy all

VAGRANTFILE_API_VERSION = "2"

# Shared base provisioning for all VMs
BASE_SCRIPT = <<-'BASESCRIPT'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl unzip zip jq ufw openssl python3 git > /dev/null 2>&1

  # UFW base rules
  ufw allow 22/tcp comment "SSH"
  ufw --force enable
BASESCRIPT

# Pi-specific packages (both pi1 and pi2)
PI_SCRIPT = <<-'PISCRIPT'
  export DEBIAN_FRONTEND=noninteractive
  PI_IP=$1
  PI_NAME=$2

  # Additional Pi packages
  apt-get install -y -qq postgresql postgresql-client default-jre-headless glusterfs-server keepalived golang > /dev/null 2>&1

  # Static IP on private network
  if ! ip addr show eth1 | grep -q "$PI_IP"; then
    ip addr add $PI_IP/24 dev eth1 2>/dev/null || true
  fi

  # UFW for Pi services
  ufw allow 3000/tcp comment "Forgejo"
  ufw allow 8080/tcp comment "Keycloak"
  ufw allow 8200/tcp comment "Vault"
  ufw allow 8201/tcp comment "Vault cluster"
  ufw allow 9000/tcp comment "MinIO"
  ufw allow 5432/tcp comment "Postgres"
  ufw allow 8008/tcp comment "Patroni"
  ufw allow 8081/tcp comment "Nexus"
  ufw allow 8082/tcp comment "Nexus Docker"
  ufw allow 8300/tcp comment "Consul RPC"
  ufw allow 8301/tcp comment "Consul Serf LAN"
  ufw allow 8301/udp comment "Consul Serf LAN UDP"
  ufw allow 8500/tcp comment "Consul HTTP"
  ufw allow 7789/tcp comment "DRBD"
  ufw allow 24007/tcp comment "GlusterFS daemon"
  ufw allow 24008/tcp comment "GlusterFS management"
  ufw allow 49152:49155/tcp comment "GlusterFS bricks"
  ufw allow 80/tcp comment "Caddy HTTP"
  ufw allow 443/tcp comment "Caddy HTTPS"
  ufw allow proto vrrp from 192.168.56.0/24 comment "VRRP"

  echo "$PI_NAME provisioned with IP $PI_IP"
PISCRIPT

# kubeadm node packages
KUBEADM_SCRIPT = <<-'KUBESCRIPT'
  export DEBIAN_FRONTEND=noninteractive
  KUBEADM_IP=$1

  # Static IP
  if ! ip addr show eth1 | grep -q "$KUBEADM_IP"; then
    ip addr add $KUBEADM_IP/24 dev eth1 2>/dev/null || true
  fi

  # UFW for k8s
  ufw allow 6443/tcp comment "Kubernetes API"
  ufw allow 10250/tcp comment "Kubelet"
  ufw allow 10257/tcp comment "Controller Manager"
  ufw allow 10259/tcp comment "Scheduler"
  ufw allow 30000:32767/tcp comment "NodePort range"

  # Rsync target + build deps for tests that build monitor/gateway/site JARs
  # (test:dr, test:microservices). Skipped cleanly if repos not mounted.
  # Debian's apt nodejs is 18 — too old for the site's Vite. Pull Node 22
  # from NodeSource so `npm run build` succeeds.
  apt-get install -y -qq rsync ca-certificates curl gnupg > /dev/null 2>&1 || true
  if ! command -v node >/dev/null || [ "$(node -v 2>/dev/null | cut -d. -f1)" != "v22" ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list
    apt-get update -qq
    apt-get install -y -qq nodejs > /dev/null 2>&1 || true
  fi

  # SDKMAN + Java 25 + Gradle (for source builds)
  if [ ! -d /home/vagrant/.sdkman ]; then
    sudo -iu vagrant bash <<'VSDK'
set -e
export HOME=/home/vagrant
curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash
set +e
source "$HOME/.sdkman/bin/sdkman-init.sh"
yes | sdk install java 25.0.2-tem
yes | sdk install gradle
VSDK
    [ -f /home/vagrant/.sdkman/bin/sdkman-init.sh ] && echo "SDKMAN ready" || echo "SDKMAN install FAILED"
  fi

  echo "kubeadm node provisioned with IP $KUBEADM_IP"
KUBESCRIPT

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "debian/bookworm64"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ── Pi 1 ─────────────────────────────────────────────────────────────
  config.vm.define "pi1" do |pi1|
    pi1.vm.hostname = "pi1"
    pi1.vm.network "private_network", ip: "192.168.56.20"
    pi1.vm.provider "libvirt" do |v|
      v.memory = 4096
      v.cpus = 2
    end
    pi1.vm.provision "shell", inline: BASE_SCRIPT
    pi1.vm.provision "shell", inline: PI_SCRIPT, args: ["192.168.56.20", "pi1"]
  end

  # ── Pi 2 ─────────────────────────────────────────────────────────────
  config.vm.define "pi2" do |pi2|
    pi2.vm.hostname = "pi2"
    pi2.vm.network "private_network", ip: "192.168.56.21"
    pi2.vm.provider "libvirt" do |v|
      v.memory = 4096
      v.cpus = 2
    end
    pi2.vm.provision "shell", inline: BASE_SCRIPT
    pi2.vm.provision "shell", inline: PI_SCRIPT, args: ["192.168.56.21", "pi2"]
  end

  # ── kubeadm ──────────────────────────────────────────────────────────
  config.vm.define "kubeadm" do |k|
    k.vm.hostname = "ten"
    k.vm.network "private_network", ip: "192.168.56.10"
    k.vm.provider "libvirt" do |v|
      v.memory = 20480
      v.cpus = 8
    end
    # Source repos mounted for in-cluster image builds (test:dr, test:microservices).
    # rsync (not NFS) to avoid cross-host mount races and keep the guest fs fast.
    k.vm.synced_folder "../monitor",     "/vagrant-monitor",  type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/", "node_modules/"], create: true
    k.vm.synced_folder "../api-gateway", "/vagrant-gateway",  type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true
    k.vm.synced_folder "../site",        "/vagrant-site",     type: "rsync",
      rsync__exclude: [".git/", "node_modules/", "dist/"], create: true
    k.vm.synced_folder "../admin",       "/vagrant-admin",    type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true
    k.vm.synced_folder "../chat",        "/vagrant-chat",     type: "rsync",
      rsync__exclude: [".git/", "build/", ".gradle/"], create: true
    k.vm.synced_folder "../platform",    "/vagrant-platform", type: "rsync",
      rsync__exclude: [".git/"], create: true
    k.vm.provision "shell", inline: BASE_SCRIPT
    k.vm.provision "shell", inline: KUBEADM_SCRIPT, args: ["192.168.56.10"]
  end
end
