# Monitor Application Deployment

Deploy the Monitor application using Helm charts via Ansible on k0s.

## Directory Structure

```
deploy/
├── ansible/
│   ├── deploy.yml              # Main deployment playbook
│   ├── uninstall.yml           # Uninstall playbook
│   ├── ansible.cfg             # Ansible configuration
│   ├── requirements.yml        # Ansible collection dependencies
│   ├── inventory/
│   │   ├── localhost.yml       # Local inventory (development)
│   │   └── production.yml      # Production inventory (Pi 5)
│   ├── playbooks/
│   │   ├── setup-k0s.yml       # Setup k0s with Traefik on fresh Pi
│   │   └── full-deploy.yml     # Full deployment (k0s + app)
│   ├── roles/
│   │   └── monitor/            # Monitor deployment role
│   │       ├── tasks/main.yml
│   │       ├── defaults/main.yml
│   │       └── templates/values.yml.j2
│   └── vars/
│       ├── development.yml     # Development environment values
│       └── production.yml      # Production environment values
└── README.md
```

## Prerequisites

- Ansible installed
- `kubernetes.core` Ansible collection
- `kubectl` configured with cluster access
- `helm` installed

```bash
# Install Ansible (if needed)
pip install ansible

# Install required Ansible collection
cd deploy/ansible
ansible-galaxy collection install -r requirements.yml
```

## Quick Start

### Deploy with defaults

```bash
cd deploy/ansible
ansible-playbook deploy.yml
```

### Deploy to development

```bash
ansible-playbook deploy.yml -e @vars/development.yml
```

### Deploy to production (Raspberry Pi 5)

```bash
# Configure Pi 5 address (edit inventory/production.yml or use env vars)
export PI5_HOST=192.168.1.100
export PI5_USER=pi

# Set credentials
export MONITOR_DB_PASSWORD=your-secure-password
export GRAFANA_ADMIN_PASSWORD=your-secure-password

# Deploy using Ansible
ansible-playbook -i inventory/production.yml deploy.yml -e @vars/production.yml

# Or using Gradle
./gradlew deployProd
```

### Fresh Pi 5 Setup (Full Deployment)

For a fresh Raspberry Pi 5 without k0s installed:

```bash
# Configure Pi 5 address
export PI5_HOST=192.168.1.100
export PI5_USER=pi

# Set credentials
export MONITOR_DB_PASSWORD=your-secure-password
export GRAFANA_ADMIN_PASSWORD=your-secure-password

# Full deployment: installs k0s + Traefik + deploys the app
./gradlew fullDeploy

# Or using Ansible directly
ansible-playbook -i inventory/production.yml playbooks/full-deploy.yml
```

This will:
1. Install k0s (single-node mode with controller + worker)
2. Install Traefik ingress controller via Helm
3. Wait for Traefik to be ready
4. Install Helm
5. Deploy the Monitor application
6. Display access instructions

### Setup k0s Only

To only setup k0s without deploying the app:

```bash
./gradlew setupK0s

# Or
ansible-playbook -i inventory/production.yml playbooks/setup-k0s.yml
```

## k0s vs k3s

This deployment uses **k0s** instead of k3s. Key differences:

| Feature | k0s | k3s |
|---------|-----|-----|
| Architecture | Single binary, all components bundled | Single binary, SQLite by default |
| Storage Class | `openebs-hostpath` | `local-path` |
| Ingress | Traefik (installed via Helm) | Traefik (bundled) |
| Config Location | `/etc/k0s/k0s.yaml` | `/etc/rancher/k3s/` |
| Kubeconfig | `/var/lib/k0s/pki/admin.conf` | `/etc/rancher/k3s/k3s.yaml` |
| kubectl | `k0s kubectl` | `k3s kubectl` |

## Configuration

### Default values

The default configuration is in `roles/monitor/defaults/main.yml`. Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `monitor_release_name` | monitor | Helm release name |
| `monitor_namespace` | monitor | Kubernetes namespace |
| `monitor_chart_path` | ../helm/monitor | Path to Helm chart |
| `monitor_wait` | true | Wait for deployment |
| `monitor_wait_timeout` | 600s | Deployment timeout |

### Override values

Create a custom values file or use the provided environment files:

```bash
# Use development settings
ansible-playbook deploy.yml -e @vars/development.yml

# Use production settings
ansible-playbook deploy.yml -e @vars/production.yml

# Override specific values
ansible-playbook deploy.yml -e monitor_namespace=my-namespace
```

### Environment files

**Development** (`vars/development.yml`):
- Single replica
- Lower resource limits
- Latest image tags
- NodePort for Grafana
- 5-minute monitoring interval

**Production** (`vars/production.yml`) - optimized for Raspberry Pi 5 (8GB):
- Single replica (single node)
- Conservative memory limits (~3.6Gi total)
- Pinned image versions
- `openebs-hostpath` storage class (k0s)
- Reduced Prometheus retention (15d) for SD card longevity
- Credentials from environment variables

## Uninstall

```bash
# Uninstall the Helm release
ansible-playbook uninstall.yml

# Uninstall and delete persistent data
ansible-playbook uninstall.yml -e monitor_delete_pvcs=true

# Uninstall and delete namespace
ansible-playbook uninstall.yml -e monitor_delete_pvcs=true -e monitor_delete_namespace=true
```

### Uninstall k0s

```bash
# On the Pi 5
sudo k0s stop
sudo k0s reset
sudo rm -rf /var/lib/k0s /etc/k0s
```

## Helm Chart

The Helm chart is located at `../helm/monitor/`. You can also use it directly:

```bash
# Using Gradle
./gradlew helmPackage

# Using Helm directly
helm install monitor ../helm/monitor -n monitor --create-namespace

# With custom values
helm install monitor ../helm/monitor -n monitor --create-namespace \
  --set postgres.password=secret \
  --set grafana.adminPassword=secret
```

## Post-Deployment

After deployment:

1. **Access the Frontend**:
   ```bash
   k0s kubectl port-forward svc/monitor-monitor-frontend 8080:8080 -n monitor
   # Open http://localhost:8080
   ```

2. **Access the API**:
   ```bash
   k0s kubectl port-forward svc/monitor-monitor-app 8080:8080 -n monitor
   # Open http://localhost:8080/api/actuator/health
   ```

3. **Access Grafana**:
   ```bash
   k0s kubectl port-forward svc/monitor-monitor-grafana 3000:3000 -n monitor
   # Open http://localhost:3000 (admin/admin by default)
   ```

4. **View logs**:
   ```bash
   k0s kubectl logs -f deployment/monitor-monitor-app -n monitor
   ```

## Building the Docker Images

Before deploying, build and push the Docker images:

### Backend

```bash
cd backend

# Build for local architecture
docker build -t ghcr.io/schnappy/monitor:latest .

# Build multi-arch and push
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/schnappy/monitor:latest --push .
```

### Frontend

```bash
cd frontend

# Build for local architecture
docker build -t ghcr.io/schnappy/monitor-frontend:latest .

# Build multi-arch and push
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/schnappy/monitor-frontend:latest --push .
```

## Troubleshooting

### Check k0s status
```bash
sudo k0s status
sudo systemctl status k0scontroller
```

### Check deployment status
```bash
k0s kubectl get pods -n monitor
k0s kubectl get svc -n monitor
```

### View Helm release
```bash
helm list -n monitor
helm status monitor -n monitor
```

### Check application logs
```bash
k0s kubectl logs -f deployment/monitor-monitor-app -n monitor
k0s kubectl logs -f deployment/monitor-monitor-frontend -n monitor
```

### Check Traefik logs
```bash
k0s kubectl logs -f deployment/traefik -n traefik
```

### Restart deployment
```bash
k0s kubectl rollout restart deployment/monitor-monitor-app -n monitor
k0s kubectl rollout restart deployment/monitor-monitor-frontend -n monitor
```

### Check storage
```bash
k0s kubectl get pvc -n monitor
k0s kubectl get pv
```
