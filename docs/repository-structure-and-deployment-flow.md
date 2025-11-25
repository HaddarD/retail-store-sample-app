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
├── helm-chart/                       # 📋 Original Helm Chart (Phase 4)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│
├── docs/                             # 📚 Documentation
│   ├── environment-configurations.md
│   └── repository-structure-and-deployment-flow.md
│
├── ─────────────────────────────────  # 🛠️ Infrastructure Scripts
├── 01-infrastructure.sh              # Create AWS resources
├── 02-k8s-init.sh                    # Initialize Kubernetes cluster
├── 03-ecr-setup.sh                   # Setup ECR + imagePullSecret
├── 05-dynamodb-setup.sh              # Create DynamoDB table
├── 06-helm-deploy.sh                 # Deploy with Helm (pre-ArgoCD)
├── 07-create-gitops-repo.sh          # Create GitOps repository
├── 08-argocd-setup.sh                # Install and configure ArgoCD
│
├── ─────────────────────────────────  # 🔧 Utility Scripts
├── startup.sh                        # Start EC2s, update IPs
├── restore-vars.sh                   # Restore environment variables
├── install-helm-local.sh             # Install Helm locally
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
| `*.sh` scripts | Infrastructure automation |
| `helm-chart/` | Original Helm chart (used before ArgoCD) |
| `docs/` | Project documentation |

---

## Repository 2: GitOps Repository

**URL:** `https://github.com/<username>/retail-store-gitops`

**Purpose:** Single source of truth for Kubernetes deployments. ArgoCD watches this repository.

### Structure:
```
retail-store-gitops/
│
├── apps/                             # 📦 Application Helm Charts
│   │
│   ├── ui/                           # UI Service
│   │   ├── Chart.yaml                # Helm chart metadata
│   │   ├── values.yaml               # Configuration values
│   │   └── templates/                # Kubernetes manifests
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── ingress.yaml
│   │
│   ├── catalog/                      # Catalog Service
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   ├── cart/                         # Cart Service
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   ├── orders/                       # Orders Service
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   ├── checkout/                     # Checkout Service
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   │
│   └── dependencies/                 # Infrastructure Dependencies
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── postgresql.yaml       # PostgreSQL database
│           ├── redis.yaml            # Redis cache
│           └── rabbitmq.yaml         # RabbitMQ message broker
│
└── argocd/                           # 🔄 ArgoCD Configuration
    └── applications/                 # Application manifests
        ├── application-ui.yaml
        ├── application-catalog.yaml
        ├── application-cart.yaml
        ├── application-orders.yaml
        ├── application-checkout.yaml
        └── application-dependencies.yaml
```

### Key Components:

| Directory | Purpose |
|-----------|---------|
| `apps/` | Helm charts for each microservice |
| `apps/dependencies/` | Database and messaging infrastructure |
| `argocd/applications/` | ArgoCD Application CRDs |

### values.yaml Structure:

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
         │                    7. Commit & Push                      │
         │                       to GitOps repo                     │
         │                           │                              │
         │                           │                              │
         │                    ┌──────┴──────┐                       │
         │                    │   ArgoCD    │                       │
         │                    │  (watching) │                       │
         │                    └──────┬──────┘                       │
         │                           │                              │
         │                    8. Detect                             │
         │                       Changes                            │
         │                           │                              │
         │                           ├─────────────────────────────▶│
         │                           │     9. Sync to Cluster       │
         │                           │                              │
         │                           │                       10. Pull new
         │                           │                           images
         │                           │                           from ECR
         │                           │                              │
         │                           │                       11. Deploy
         │                           │                           new pods
         │                           │                              │
         │◀──────────────────────────┼──────────────────────────────│
         │              12. Application Updated                     │
         │                                                          │
```

### Step-by-Step Breakdown:

| Step | Component | Action | Details |
|------|-----------|--------|---------|
| 1 | Developer | Push code | `git push origin main` |
| 2 | GitHub | Trigger workflow | `on: push: branches: [main]` |
| 3 | GitHub Actions | Build images | `docker build` for each service |
| 4 | GitHub Actions | Push to ECR | `docker push` with commit SHA tag |
| 5 | GitHub Actions | Clone GitOps repo | Using `GITOPS_PAT` secret |
| 6 | GitHub Actions | Update values | `sed -i` to update image tags |
| 7 | GitHub Actions | Push changes | Commit and push to GitOps repo |
| 8 | ArgoCD | Detect changes | Polls GitOps repo every 3 minutes |
| 9 | ArgoCD | Sync to cluster | Apply Helm charts to Kubernetes |
| 10 | Kubernetes | Pull images | Using `regcred` imagePullSecret |
| 11 | Kubernetes | Deploy pods | Rolling update of deployments |
| 12 | Application | Updated | New version running |

---

## GitHub Actions Workflow Details

### Workflow File: `.github/workflows/build-and-deploy.yml`
```yaml
name: Build and Deploy to ECR

on:
  push:
    branches: [main]
  workflow_dispatch:  # Manual trigger

jobs:
  # Job 1: Detect what to build
  detect-changes:
    name: Detect Changed Services
    # Sets all services to build (project requirement)
    
  # Jobs 2-6: Build each service
  build-ui:
    needs: detect-changes
    # Build and push UI image
    
  build-catalog:
    needs: detect-changes
    # Build and push Catalog image
    
  # ... (cart, orders, checkout)
  
  # Job 7: Update GitOps repository
  update-gitops:
    needs: [build-ui, build-catalog, build-cart, build-orders, build-checkout]
    steps:
      - Checkout GitOps repo
      - Update image tags in values.yaml
      - Commit and push
      
  # Job 8: Summary
  build-summary:
    # Print build results
```

### Image Tagging Strategy:

| Tag | Purpose | Example |
|-----|---------|---------|
| Commit SHA | Traceability | `c4ec36469ad95d3eee5a3999108f4839f84d8108` |
| `latest` | Quick reference | Points to most recent build |

---

## ArgoCD Configuration

### Application Definition:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-ui
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/USER/retail-store-gitops.git
    targetRevision: main
    path: apps/ui
    helm:
      valueFiles:
        - values.yaml
        
  destination:
    server: https://kubernetes.default.svc
    namespace: retail-store
    
  syncPolicy:
    automated:
      prune: true       # Delete resources removed from Git
      selfHeal: true    # Revert manual changes
    syncOptions:
      - CreateNamespace=true
```

### Sync Behavior:

| Setting | Value | Effect |
|---------|-------|--------|
| `automated` | enabled | Auto-sync on Git changes |
| `prune` | true | Remove deleted resources |
| `selfHeal` | true | Revert manual cluster changes |
| `CreateNamespace` | true | Create namespace if missing |

---

## Network Flow

### Request Path:
```
┌──────────┐     ┌─────────────┐     ┌──────────────────────────────────────┐
│  User    │────▶│   Ingress   │────▶│           Kubernetes Cluster         │
│ Browser  │     │   :30080    │     │                                      │
└──────────┘     └─────────────┘     │  ┌────┐                              │
                                      │  │ UI │◀───────────────────┐        │
                                      │  └──┬─┘                    │        │
                                      │     │                      │        │
                                      │  ┌──▼──────┐  ┌──────┐  ┌──┴─────┐ │
                                      │  │ Catalog │  │ Cart │  │Checkout│ │
                                      │  └────┬────┘  └──┬───┘  └───┬────┘ │
                                      │       │         │          │       │
                                      │  ┌────▼────┐ ┌──▼───┐ ┌────▼────┐ │
                                      │  │PostgreSQL│ │Redis │ │RabbitMQ │ │
                                      │  └─────────┘ │+Dynamo│ └────┬────┘ │
                                      │              └───────┘      │      │
                                      │                        ┌────▼────┐ │
                                      │                        │ Orders  │ │
                                      │                        └─────────┘ │
                                      └──────────────────────────────────────┘
```

---

## Access Points

| Resource | URL | Port |
|----------|-----|------|
| Retail Store App | `http://MASTER_IP:30080` | 30080 |
| ArgoCD UI | `https://MASTER_IP:30090` | 30090 |
| Kubernetes API | `https://MASTER_IP:6443` | 6443 |

---

## Secrets Management

### GitHub Repository Secrets:

| Secret | Purpose | Used By |
|--------|---------|---------|
| `AWS_ACCESS_KEY_ID` | AWS authentication | GitHub Actions |
| `AWS_SECRET_ACCESS_KEY` | AWS authentication | GitHub Actions |
| `AWS_REGION` | ECR region | GitHub Actions |
| `AWS_ACCOUNT_ID` | ECR registry URL | GitHub Actions |
| `GITOPS_PAT` | Push to GitOps repo | GitHub Actions |

### Kubernetes Secrets:

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `regcred` | retail-store | ECR image pull credentials |
| `argocd-initial-admin-secret` | argocd | ArgoCD admin password |

---

## Rollback Procedure

### Option 1: Git Revert (Recommended)
```bash
# In GitOps repository
git revert HEAD
git push origin main
# ArgoCD auto-syncs to previous state
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
| CI | GitHub Actions |
| CD | ArgoCD |
| Container Registry | AWS ECR |
| Kubernetes | kubeadm on EC2 |
| Ingress | nginx-ingress (NodePort) |
| Databases | PostgreSQL, Redis, RabbitMQ (in-cluster) + DynamoDB (AWS) |
