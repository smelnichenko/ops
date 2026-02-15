# Monitor Application Deployment

Deploy the Monitor application using Helm charts via Ansible on k3s.

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
│   │   └── production.yml      # Production inventory
│   ├── playbooks/
│   │   ├── setup-k3s.yml       # Setup k3s on fresh target
│   │   └── full-deploy.yml     # Full deployment (k3s + app)
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

### Deploy to production

```bash
# Configure target address (edit inventory/production.yml or use env vars)
export TARGET_HOST=192.168.1.100
export TARGET_USER=pi

# Set credentials
export MONITOR_DB_PASSWORD=your-secure-password
export JWT_SECRET=your-jwt-secret-at-least-32-chars
export GRAFANA_ADMIN_PASSWORD=your-secure-password

# Deploy using Ansible
ansible-playbook -i inventory/production.yml deploy.yml -e @vars/production.yml

# Or using Gradle
./gradlew deployProd
```

### Fresh Target Setup (Full Deployment)

For a fresh target host without k3s installed:

```bash
# Configure target address
export TARGET_HOST=192.168.1.100
export TARGET_USER=pi

# Set credentials
export MONITOR_DB_PASSWORD=your-secure-password
export JWT_SECRET=your-jwt-secret-at-least-32-chars
export GRAFANA_ADMIN_PASSWORD=your-secure-password

# Full deployment: installs k3s + deploys the app
./gradlew fullDeploy

# Or using Ansible directly
ansible-playbook -i inventory/production.yml playbooks/full-deploy.yml
```

This will:
1. Install k3s (single-node, bundles Traefik + local-path-provisioner)
2. Install Docker and Helm
3. Deploy the Monitor application
4. Display access instructions

### Setup k3s Only

To only setup k3s without deploying the app:

```bash
./gradlew setupK3s

# Or
ansible-playbook -i inventory/production.yml playbooks/setup-k3s.yml
```

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

**Production** (`vars/production.yml`):
- Single replica (single node)
- Conservative memory limits
- `local-path` storage class (k3s)
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

### Uninstall k3s

```bash
# On the target host
/usr/local/bin/k3s-uninstall.sh
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
  --set auth.jwtSecret=secret \
  --set grafana.adminPassword=secret
```

## Post-Deployment

After deployment:

1. **Access the Frontend**:
   ```bash
   k3s kubectl port-forward svc/monitor-monitor-frontend 8080:8080 -n monitor
   # Open http://localhost:8080
   ```

2. **Access the API**:
   ```bash
   k3s kubectl port-forward svc/monitor-monitor-app 8080:8080 -n monitor
   # Open http://localhost:8080/api/actuator/health
   ```

3. **Access Grafana**:
   ```bash
   k3s kubectl port-forward svc/monitor-monitor-grafana 3000:3000 -n monitor
   # Open http://localhost:3000 (admin/admin by default)
   ```

4. **View logs**:
   ```bash
   k3s kubectl logs -f deployment/monitor-monitor-app -n monitor
   ```

## Troubleshooting

### Check k3s status
```bash
sudo systemctl status k3s
k3s kubectl get nodes
```

### Check deployment status
```bash
k3s kubectl get pods -n monitor
k3s kubectl get svc -n monitor
```

### View Helm release
```bash
helm list -n monitor
helm status monitor -n monitor
```

### Check application logs
```bash
k3s kubectl logs -f deployment/monitor-monitor-app -n monitor
k3s kubectl logs -f deployment/monitor-monitor-frontend -n monitor
```

### Restart deployment
```bash
k3s kubectl rollout restart deployment/monitor-monitor-app -n monitor
k3s kubectl rollout restart deployment/monitor-monitor-frontend -n monitor
```

### Check storage
```bash
k3s kubectl get pvc -n monitor
k3s kubectl get pv
```
