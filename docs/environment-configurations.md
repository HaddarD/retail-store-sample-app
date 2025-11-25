# Environment-Specific Configurations

## Overview

This document describes how the Retail Store application supports multiple deployment environments using GitOps principles.

## Environment Strategy

### Current Implementation (Learning/Development)

For this class project, we use a **single environment** deployed to our kubeadm cluster:
```
retail-store-gitops/
└── apps/
    ├── ui/
    ├── catalog/
    ├── cart/
    ├── orders/
    ├── checkout/
    └── dependencies/
```

### Production-Ready Structure (Multi-Environment)

In a real-world scenario, we would implement environment-specific configurations:
```
retail-store-gitops/
├── base/                          # Shared configurations
│   ├── ui/
│   │   ├── Chart.yaml
│   │   ├── values.yaml            # Default values
│   │   └── templates/
│   ├── catalog/
│   ├── cart/
│   ├── orders/
│   ├── checkout/
│   └── dependencies/
│
├── overlays/                      # Environment-specific overrides
│   ├── dev/
│   │   ├── ui-values.yaml
│   │   ├── catalog-values.yaml
│   │   ├── cart-values.yaml
│   │   ├── orders-values.yaml
│   │   ├── checkout-values.yaml
│   │   └── kustomization.yaml
│   │
│   ├── staging/
│   │   ├── ui-values.yaml
│   │   ├── catalog-values.yaml
│   │   └── ...
│   │
│   └── prod/
│       ├── ui-values.yaml
│       ├── catalog-values.yaml
│       └── ...
│
└── argocd/
    └── applications/
        ├── dev/
        │   ├── application-ui.yaml
        │   └── ...
        ├── staging/
        │   └── ...
        └── prod/
            └── ...
```

---

## Environment Differences

### Development Environment

| Setting | Value | Reason |
|---------|-------|--------|
| Replicas | 1 | Cost savings |
| Resources | Low (256Mi RAM) | Minimal footprint |
| Image Tag | `latest` or commit SHA | Fast iteration |
| Logging | Debug level | Troubleshooting |
| Database | In-cluster PostgreSQL | Simplicity |

**Example dev values override (`overlays/dev/ui-values.yaml`):**
```yaml
replicaCount: 1

image:
  tag: "latest"
  pullPolicy: Always

resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "250m"

env:
  LOG_LEVEL: "debug"
```

### Staging Environment

| Setting | Value | Reason |
|---------|-------|--------|
| Replicas | 2 | Test load balancing |
| Resources | Medium | Production-like |
| Image Tag | Release candidate | Pre-production testing |
| Logging | Info level | Balance visibility/noise |
| Database | In-cluster or RDS | Test external connections |

**Example staging values override (`overlays/staging/ui-values.yaml`):**
```yaml
replicaCount: 2

image:
  tag: "v1.2.0-rc1"
  pullPolicy: IfNotPresent

resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"

env:
  LOG_LEVEL: "info"
```

### Production Environment

| Setting | Value | Reason |
|---------|-------|--------|
| Replicas | 3+ | High availability |
| Resources | High | Handle real traffic |
| Image Tag | Semantic version | Stability |
| Logging | Warn level | Reduce noise |
| Database | AWS RDS | Managed, backed up |

**Example prod values override (`overlays/prod/ui-values.yaml`):**
```yaml
replicaCount: 3

image:
  tag: "v1.2.0"
  pullPolicy: IfNotPresent

resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"

env:
  LOG_LEVEL: "warn"

# Production-specific settings
podDisruptionBudget:
  enabled: true
  minAvailable: 2

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilization: 70
```

---

## ArgoCD Application Per Environment

Each environment has its own ArgoCD Application pointing to the correct overlay:

**Development (`argocd/applications/dev/application-ui.yaml`):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-retail-store-ui
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/USER/retail-store-gitops.git
    targetRevision: main
    path: overlays/dev
    helm:
      valueFiles:
        - ui-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: retail-store-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Production (`argocd/applications/prod/application-ui.yaml`):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-retail-store-ui
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/USER/retail-store-gitops.git
    targetRevision: main
    path: overlays/prod
    helm:
      valueFiles:
        - ui-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: retail-store-prod
  syncPolicy:
    automated:
      prune: false          # Don't auto-delete in prod!
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Promotion Workflow
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│     DEV     │────▶│   STAGING   │────▶│    PROD     │
└─────────────┘     └─────────────┘     └─────────────┘
     │                    │                    │
     │ Auto-deploy        │ Auto-deploy        │ Manual approve
     │ on push            │ on PR merge        │ + deploy
     │                    │                    │
     ▼                    ▼                    ▼
  latest              v1.2.0-rc1            v1.2.0
```

### Promotion Steps:

1. **Dev → Staging:**
   - Developer creates PR with tested changes
   - PR merged to `main` branch
   - GitHub Actions builds image with RC tag
   - Update staging values with new tag
   - ArgoCD auto-syncs to staging

2. **Staging → Prod:**
   - QA approves staging deployment
   - Create Git tag (e.g., `v1.2.0`)
   - GitHub Actions builds image with release tag
   - Create PR to update prod values
   - Manual approval required
   - Merge PR, ArgoCD syncs to prod

---

## Branch Strategy Alternative

Instead of directories, environments can use branches:

| Branch | Environment | Auto-Deploy |
|--------|-------------|-------------|
| `develop` | Development | ✅ Yes |
| `staging` | Staging | ✅ Yes |
| `main` | Production | ❌ Manual |

**ArgoCD points to different branches:**
```yaml
# Dev application
spec:
  source:
    targetRevision: develop
    
# Prod application  
spec:
  source:
    targetRevision: main
```

---

## Current Project Implementation

For this class project, we use a simplified single-environment approach:

| Aspect | Our Implementation |
|--------|-------------------|
| Environments | Single (dev/learning) |
| Namespace | `retail-store` |
| Image Tags | Commit SHA |
| Auto-sync | Enabled |
| Replicas | 1 per service |

This demonstrates GitOps principles while keeping the project manageable for learning purposes.

---

## Future Enhancements

To make this production-ready:

1. **Add environment overlays** - Create dev/staging/prod directories
2. **Implement promotion workflow** - PR-based promotions between environments
3. **Add approval gates** - Manual approval for production deployments
4. **Configure RBAC** - Limit who can deploy to each environment
5. **Add monitoring per environment** - Separate dashboards and alerts
6. **Implement secrets management** - Use Sealed Secrets or External Secrets Operator
