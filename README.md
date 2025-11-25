# Retail Store Sample App - Kubernetes kubeadm Cluster 🛒

A microservices e-commerce application deployed on a self-managed Kubernetes cluster using kubeadm, with GitOps continuous deployment via ArgoCD.

## Features

- 🏗️ **Self-managed Kubernetes** cluster using kubeadm (not EKS)
- 🐳 **5 Microservices**: UI, Catalog, Cart, Orders, Checkout
- 📦 **AWS ECR** for private container registry
- 🔄 **GitHub Actions CI/CD** pipeline
- 🚀 **ArgoCD GitOps** for automated deployments
- 📊 **Infrastructure as Code** with automated bash scripts

## Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│                                                                  │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐               │
│   │  Master  │     │ Worker1  │     │ Worker2  │               │
│   │ t3.medium│     │ t3.medium│     │ t3.medium│               │
│   └────┬─────┘     └────┬─────┘     └────┬─────┘               │
│        └────────────────┴────────────────┘                      │
│                    Kubernetes Cluster                            │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  UI → Catalog → Cart → Checkout → Orders                │  │
│   │        ↓          ↓        ↓          ↓                 │  │
│   │   PostgreSQL    Redis   RabbitMQ   PostgreSQL           │  │
│   │                   ↓                                      │  │
│   │               DynamoDB (AWS)                             │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                  │
│   ┌──────────┐              ┌──────────┐                       │
│   │   ECR    │              │  ArgoCD  │                       │
│   └──────────┘              └──────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- GitHub account with repository fork
- Bash terminal (Linux/macOS/WSL)
- ~$2-5/day AWS costs (3x t3.medium EC2 instances)

## Quick Start 🚀

### First Time Setup
```bash
# 1. Clone the repository
git clone https://github.com/YOUR-USERNAME/retail-store-sample-app.git
cd retail-store-sample-app

# 2. Create AWS infrastructure (EC2 instances, security groups, IAM)
./01-infrastructure.sh

# 3. Initialize Kubernetes cluster
./02-k8s-init.sh

# 4. Setup ECR repositories and credentials
./03-ecr-setup.sh

# 5. Create DynamoDB table for Cart service
./05-dynamodb-setup.sh

# 6. (Option A) Deploy with Helm only
./06-helm-deploy.sh

# 6. (Option B) Deploy with GitOps/ArgoCD
./07-create-gitops-repo.sh
# Add GITOPS_PAT secret to GitHub repository settings
./08-argocd-setup.sh
```

### Daily Startup
```bash
./startup.sh && source deployment-info.txt && ./03-ecr-setup.sh
```

### Access the Application
```bash
# Retail Store App
echo "http://${MASTER_PUBLIC_IP}:30080"

# ArgoCD UI (if using GitOps)
echo "https://${MASTER_PUBLIC_IP}:30090"
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Project Structure
```
retail-store-sample-app/
├── src/                          # Microservices source code
│   ├── ui/                       # Java Spring Boot frontend
│   ├── catalog/                  # Go REST API
│   ├── cart/                     # Java Spring Boot
│   ├── orders/                   # Java Spring Boot
│   └── checkout/                 # Node.js
│
├── .github/workflows/            # CI/CD pipeline
│   └── build-and-deploy.yml
│
├── helm-chart/                   # Kubernetes Helm chart
│
├── docs/                         # Documentation
│   ├── environment-configurations.md
│   ├── repository-structure-and-deployment-flow.md
│   └── reflections.md
│
├── 01-infrastructure.sh          # Create AWS resources
├── 02-k8s-init.sh                # Initialize K8s cluster
├── 03-ecr-setup.sh               # Setup ECR + credentials
├── 05-dynamodb-setup.sh          # Create DynamoDB table
├── 06-helm-deploy.sh             # Deploy with Helm
├── 07-create-gitops-repo.sh      # Create GitOps repository
├── 08-argocd-setup.sh            # Install ArgoCD
├── startup.sh                    # Daily startup script
├── 99-cleanup.sh                 # Delete all resources
│
├── deployment-info.txt           # Generated variables (gitignored)
├── project-cheatsheet.md         # Complete reference guide
└── README.md                     # This file
```

## Scripts Reference

| Script | Purpose | Run Frequency |
|--------|---------|---------------|
| `01-infrastructure.sh` | Create EC2, security groups, IAM | Once |
| `02-k8s-init.sh` | Initialize Kubernetes cluster | Once |
| `03-ecr-setup.sh` | Setup ECR + refresh credentials | Every session |
| `05-dynamodb-setup.sh` | Create DynamoDB table | Once |
| `06-helm-deploy.sh` | Deploy app with Helm | Once (if not using ArgoCD) |
| `07-create-gitops-repo.sh` | Create GitOps repository | Once |
| `08-argocd-setup.sh` | Install and configure ArgoCD | Once |
| `startup.sh` | Start EC2s, update IPs | Every session |
| `99-cleanup.sh` | Delete ALL resources | End of project |

## GitHub Secrets Required

Add these to your GitHub repository settings → Secrets and variables → Actions:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_REGION` | `us-east-1` |
| `AWS_ACCOUNT_ID` | Your AWS account ID |
| `GITOPS_PAT` | GitHub PAT for GitOps repo (if using ArgoCD) |

## Useful Commands
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n retail-store

# Check ArgoCD applications
kubectl get applications -n argocd

# View logs
kubectl logs -n retail-store -l app=ui --tail=50

# Restart deployments (after ECR token refresh)
kubectl rollout restart deployment -n retail-store

# SSH to master node
ssh -i $KEY_FILE ubuntu@$MASTER_PUBLIC_IP
```

## Troubleshooting

### Pods stuck in ImagePullBackOff
ECR credentials expired or missing. Run:
```bash
./03-ecr-setup.sh
kubectl rollout restart deployment -n retail-store
```

### Cannot connect to cluster
EC2 instances stopped or IPs changed. Run:
```bash
./startup.sh && source deployment-info.txt
```

### 503 Service Unavailable
Backend pods not ready yet. Check pod status:
```bash
kubectl get pods -n retail-store
```

### RabbitMQ won't install
Requires 20GB disk space. Check with:
```bash
ssh -i $KEY_FILE ubuntu@$MASTER_PUBLIC_IP "df -h /"
```

## Cleanup

**⚠️ This deletes ALL resources and cannot be undone!**
```bash
./99-cleanup.sh
```

## Technologies Used

| Category | Technology |
|----------|------------|
| Cloud | AWS (EC2, ECR, DynamoDB) |
| Container Runtime | containerd |
| Kubernetes | kubeadm 1.28 |
| CNI | Calico |
| Package Manager | Helm |
| GitOps | ArgoCD |
| CI/CD | GitHub Actions |
| Ingress | nginx-ingress |

## Documentation

- [Project Cheatsheet](project-cheatsheet.md) - Complete reference for presentation
- [Environment Configurations](docs/environment-configurations.md) - Multi-environment strategy
- [Repository Structure & Deployment Flow](docs/repository-structure-and-deployment-flow.md) - Detailed architecture
- [Reflections](docs/reflections.md) - Challenges and learnings

---

*Built as a DevOps class project demonstrating Kubernetes, CI/CD, and GitOps principles* 🎓
