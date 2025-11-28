# Repository Structure and Deployment Flow

## Overview

This project uses a **two-repository GitOps architecture**:

1. **Application Repository** (`retail-store-sample-app`) - Source code and CI/CD
2. **GitOps Repository** (`retail-store-gitops`) - Kubernetes configurations

---

## Repository 1: Application Repository

**URL:** `https://github.com/<username>/retail-store-sample-app`

**Purpose:** Contains application source code, CI/CD pipeline, and infrastructure scripts.

### Structure:
```
retail-store-sample-app/
│
├── src/                              # 📦 Application Source Code
│   ├── ui/                           # Java Spring Boot - Frontend
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── pom.xml
│   │
│   ├── catalog/                      # Go - Product Catalog API
│   │   ├── main.go
│   │   ├── Dockerfile
│   │   └── go.mod
│   │
│   ├── cart/                         # Java Spring Boot - Shopping Cart
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── pom.xml
│   │
│   ├── orders/                       # Java Spring Boot - Order Management
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── pom.xml
│   │
│   └── checkout/                     # Node.js - Checkout Process
│       ├── src/
│       ├── Dockerfile
│       └── package.json
│
├── .github/                          # 🔄 CI/CD Pipeline
│   └── workflows/
│       └── build-and-deploy.yml      # GitHub Actions workflow
│
├── terraform/                        # 🏗️ Infrastructure as Code
│   └── ecr/                          # ECR Repository Definitions
│       ├── main.tf                   # 5 ECR repositories
│       ├── variables.tf              # Configuration variables
│       ├── outputs.tf                # Repository URLs output
│       └── terraform.tfvars          # Environment values
│
├── helm-chart/                       # 📋 Original Helm Chart (Phase 4)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│
├── docs/                             # 📚 Documentation
│   ├── environment-configurations.md
│   ├── repository-structure-and-deployment-flow.md
│   └── reflections.md
│
├── ─────────────────────────────────  # 🛠️ Infrastructure Scripts
├── 01-infrastructure.sh              # Create AWS resources (EC2, SG, IAM)
├── 02-k8s-init.sh                    # Initialize Kubernetes cluster
├── 03-Install-terraform.sh           # Install Terraform locally
├── 04-ecr-setup.sh                   # Setup ECR (Terraform) + imagePullSecret
├── 05-dynamodb-setup.sh              # Create DynamoDB table
├── 06-install-helm-local.sh          # Install Helm locally
├── 07-helm-deploy.sh                 # Deploy with Helm (pre-ArgoCD)
├── 08-create-gitops-repo.sh          # Create GitOps repository
├── 09-argocd-setup.sh                # Install and configure ArgoCD
│
├── ─────────────────────────────────  # 🔧 Utility Scripts
├── startup.sh                        # Start EC2s, update IPs
├── restore-vars.sh                   # Restore environment variables
├── Display-App-URLs.sh               # Show application URLs
├── 99-cleanup.sh                     # Delete all resources
│
├── ─────────────────────────────────  # 📄 Generated Files
├── deployment-info.txt               # Environment variables (gitignored)
├── k8s-kubeadm-key.pem              # SSH key (gitignored)
│
├── ─────────────────────────────────  # 📖 Documentation
├── README.md                         # Project instructions
├── project-cheatsheet.md             # Complete reference guide
└── .gitignore
```

### Key Components:

| Directory/File | Purpose |
|----------------|---------|
| `src/` | Microservices source code |
| `.github/workflows/` | CI/CD pipeline definitions |
| `terraform/ecr/` | Terraform IaC for ECR repositories |
| `*.sh` scripts | Infrastructure automation |
| `helm-chart/` | Original Helm chart (used before ArgoCD) |
| `docs/` | Project documentation |

---

## Repository 2: GitOps Repository

**URL:** `https://github.com/<username>/retail-store-gitops`

**Purpose:** Single source of truth for Kubernetes deployments.

### Structure:
```
retail-store-gitops/
│
├── apps/                             # 📦 Helm Charts per Service
│   ├── ui/
│   │   ├── Chart.yaml
│   │   ├── values.yaml               # ← Image tags updated by CI/CD
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── _helpers.tpl
│   │
│   ├── catalog/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   ├── cart/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   ├── orders/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   ├── checkout/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   └── dependencies/                 # PostgreSQL, Redis, RabbitMQ
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│
├── argocd/                           # 🚀 ArgoCD Application Definitions
│   └── applications/
│       ├── application-ui.yaml
│       ├── application-catalog.yaml
│       ├── application-cart.yaml
│       ├── application-orders.yaml
│       ├── application-checkout.yaml
│       └── application-dependencies.yaml
│
└── README.md
```

### How Values Files Work:

Each service's `values.yaml` contains:
```yaml
# Example: apps/ui/values.yaml

replicaCount: 1

image:
  repository: 630019796862.dkr.ecr.us-east-1.amazonaws.com/retail-store-ui
  tag: "c4ec36469ad95d3eee5a3999108f4839f84d8108"  # ← Updated by GitHub Actions
  pullPolicy: Always

imagePullSecrets:
  - name: regcred

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"

env:
  ENDPOINTS_CATALOG: "http://catalog:80"
  ENDPOINTS_CARTS: "http://cart:80"
  ENDPOINTS_ORDERS: "http://orders:80"
  ENDPOINTS_CHECKOUT: "http://checkout:80"
```

---

## Deployment Flow

### Complete CI/CD Pipeline:
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DEPLOYMENT FLOW                                    │
└─────────────────────────────────────────────────────────────────────────────┘

     DEVELOPER                    GITHUB                         AWS/K8S
         │                           │                              │
    1. Push Code                     │                              │
         │                           │                              │
         ├──────────────────────────▶│                              │
         │                           │                              │
         │                    2. GitHub Actions                     │
         │                      Triggered                           │
         │                           │                              │
         │                    3. Build Docker                       │
         │                       Images                             │
         │                           │                              │
         │                           ├─────────────────────────────▶│
         │                           │     4. Push to ECR           │
         │                           │                              │
         │                    5. Clone GitOps                       │
         │                       Repository                         │
         │                           │                              │
         │                    6. Update image                       │
         │                       tags in                            │
         │                       values.yaml                        │
         │                           │                              │
         │                    7. Push to GitOps                     │
         │                       Repository                         │
         │                           │                              │
         │                           │                              │
         │                           │      8. ArgoCD detects       │
         │                           │         changes              │
         │                           │                              │
         │                           │                              │
         │                           │◀─────────────────────────────┤
         │                           │      9. ArgoCD syncs         │
         │                           │         to cluster           │
         │                           │                              │
         │                           │                              │
         │                           ├─────────────────────────────▶│
         │                           │     10. New pods             │
         │                           │         deployed             │
         │                           │                              │
         │                           │                              │
    11. User sees                    │                              │
        updated app                  │                              │
         │                           │                              │
```

### Step-by-Step Breakdown:

1. **Developer pushes code** to `retail-store-sample-app` repository
2. **GitHub Actions workflow** is triggered by push to `main` branch
3. **Docker images are built** for each changed microservice
4. **Images are pushed to ECR** (created via Terraform)
5. **GitHub Actions clones** the GitOps repository
6. **Image tags are updated** in the appropriate `values.yaml` files
7. **Changes are committed and pushed** to the GitOps repository
8. **ArgoCD detects** the change in the GitOps repository
9. **ArgoCD syncs** the new configuration to the Kubernetes cluster
10. **New pods are deployed** with the updated images
11. **User sees the updated application**

---

## Infrastructure Provisioning

### Terraform for ECR (Phase 3)

ECR repositories are created using Terraform for Infrastructure as Code:
```
terraform/ecr/
├── main.tf           # Defines 5 ECR repositories
├── variables.tf      # Input variables (region, naming)
├── outputs.tf        # Outputs repository URLs
└── terraform.tfvars  # Your environment values
```

**What Terraform Creates:**
- `retail-store-ui` repository
- `retail-store-catalog` repository
- `retail-store-cart` repository
- `retail-store-orders` repository
- `retail-store-checkout` repository

**Features:**
- Image scanning on push (security)
- AES256 encryption
- Lifecycle policies (auto-cleanup old images)
- Proper tagging for management

**Usage:**
```bash
# First time: Creates ECR repos with Terraform + imagePullSecret
./04-ecr-setup.sh

# Subsequent runs: Only refreshes imagePullSecret (12-hour token)
./04-ecr-setup.sh
```

---

## Rollback Procedure

### Option 1: Git Revert
```bash
# In GitOps repository
git revert HEAD
git push
# ArgoCD auto-syncs to previous version
```

### Option 2: ArgoCD UI
1. Open ArgoCD UI
2. Select application
3. Click "History and Rollback"
4. Select previous revision
5. Click "Rollback"

### Option 3: ArgoCD CLI
```bash
argocd app rollback retail-store-ui
```

---

## Monitoring Deployment

### Check ArgoCD Applications:
```bash
kubectl get applications -n argocd
```

### Expected Output:
```
NAME                        SYNC STATUS   HEALTH STATUS
retail-store-ui             Synced        Healthy
retail-store-catalog        Synced        Healthy
retail-store-cart           Synced        Healthy
retail-store-orders         Synced        Healthy
retail-store-checkout       Synced        Healthy
retail-store-dependencies   Synced        Healthy
```

### Check Pods:
```bash
kubectl get pods -n retail-store
```

### Expected Output:
```
NAME                          READY   STATUS    RESTARTS   AGE
ui-xxxxx                      1/1     Running   0          5m
catalog-xxxxx                 1/1     Running   0          5m
cart-xxxxx                    1/1     Running   0          5m
orders-xxxxx                  1/1     Running   0          5m
checkout-xxxxx                1/1     Running   0          5m
postgresql-xxxxx              1/1     Running   0          5m
redis-master-xxxxx            1/1     Running   0          5m
rabbitmq-xxxxx                1/1     Running   0          5m
```

---

## Summary

| Aspect | Implementation |
|--------|----------------|
| Source Code | Application Repository |
| Configurations | GitOps Repository |
| IaC (ECR) | Terraform |
| CI | GitHub Actions |
| CD | ArgoCD |
| Container Registry | AWS ECR |
| Kubernetes | kubeadm on EC2 |
| Ingress | nginx-ingress (NodePort) |
| Databases | PostgreSQL, Redis, RabbitMQ (in-cluster) + DynamoDB (AWS) |