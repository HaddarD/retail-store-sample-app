#!/bin/bash

################################################################################
# Kubernetes kubeadm Cluster - GitOps Repository Setup Script
# Chat 5: Create GitOps repository and generate configuration files
#
# This script:
# 1. Installs GitHub CLI (if needed)
# 2. Authenticates with GitHub
# 3. Creates the retail-store-gitops repository
# 4. Generates all Helm charts and ArgoCD Application manifests
# 5. Pushes everything to the new repository
################################################################################

set -e  # Exit on any error

# Load environment variables
if [ ! -f deployment-info.txt ]; then
    echo "❌ ERROR: deployment-info.txt not found!"
    echo "Please run 01-infrastructure.sh first"
    exit 1
fi

source deployment-info.txt

# Configuration
GITOPS_REPO_NAME="retail-store-gitops"
GITOPS_BRANCH="main"
TEMP_DIR="/tmp/gitops-setup-$$"
NAMESPACE="retail-store"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Main header
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   Kubernetes kubeadm Cluster - GitOps Repo Setup     ║"
echo "║   Phase 5.1: Create Configuration Repository         ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Check and install GitHub CLI
install_github_cli() {
    print_header "Checking GitHub CLI"
    
    if command -v gh &> /dev/null; then
        GH_VERSION=$(gh --version | head -n1)
        print_success "GitHub CLI installed: ${GH_VERSION}"
    else
        print_info "Installing GitHub CLI..."
        
        # Install GitHub CLI
        type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
        
        print_success "GitHub CLI installed"
    fi
}

# Authenticate with GitHub
authenticate_github() {
    print_header "GitHub Authentication"
    
    # Check if already authenticated
    if gh auth status &> /dev/null; then
        GITHUB_USER=$(gh api user --jq '.login')
        print_success "Already authenticated as: ${GITHUB_USER}"
    else
        print_warning "Not authenticated with GitHub"
        print_info "Please authenticate with GitHub..."
        echo ""
        echo -e "${YELLOW}A browser window will open. Follow these steps:${NC}"
        echo "  1. Press Enter to open browser"
        echo "  2. Enter the code shown in terminal"
        echo "  3. Authorize GitHub CLI"
        echo ""
        read -p "Press Enter to continue..."
        
        gh auth login --web --git-protocol https
        
        GITHUB_USER=$(gh api user --jq '.login')
        print_success "Authenticated as: ${GITHUB_USER}"
    fi
    
    # Export for later use
    export GITHUB_USER
}

# Check if repo already exists
check_existing_repo() {
    print_header "Checking for Existing Repository"
    
    if gh repo view "${GITHUB_USER}/${GITOPS_REPO_NAME}" &> /dev/null; then
        print_warning "Repository ${GITOPS_REPO_NAME} already exists!"
        echo ""
        echo -n "Do you want to delete and recreate it? (y/n): "
        read -r response
        
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            print_info "Deleting existing repository..."
            gh repo delete "${GITHUB_USER}/${GITOPS_REPO_NAME}" --yes
            print_success "Repository deleted"
            sleep 2
        else
            print_error "Cannot continue with existing repository"
            print_info "Please delete the repository manually or rename GITOPS_REPO_NAME"
            exit 1
        fi
    else
        print_success "Repository name is available: ${GITOPS_REPO_NAME}"
    fi
}

# Create GitOps repository
create_gitops_repo() {
    print_header "Creating GitOps Repository"
    
    print_info "Creating repository: ${GITOPS_REPO_NAME}"
    
    gh repo create "${GITOPS_REPO_NAME}" \
        --public \
        --description "GitOps configuration repository for Retail Store Kubernetes deployment" \
        --clone=false
    
    print_success "Repository created: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}"
}

# Generate all GitOps files
generate_gitops_files() {
    print_header "Generating GitOps Configuration Files"
    
    # Clean up temp directory
    rm -rf ${TEMP_DIR}
    mkdir -p ${TEMP_DIR}
    cd ${TEMP_DIR}
    
    # Initialize git repo
    git init
    git checkout -b ${GITOPS_BRANCH}
    
    print_info "Generating directory structure..."
    
    # Create directory structure
    mkdir -p apps/ui/templates
    mkdir -p apps/catalog/templates
    mkdir -p apps/cart/templates
    mkdir -p apps/orders/templates
    mkdir -p apps/checkout/templates
    mkdir -p apps/dependencies/templates
    mkdir -p argocd/applications
    
    print_info "Generating Helm charts..."
    
    #===========================================================================
    # UI Service
    #===========================================================================
    cat > apps/ui/Chart.yaml << 'EOF'
apiVersion: v2
name: ui
description: Retail Store UI Service
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > apps/ui/values.yaml << EOF
replicaCount: 1

image:
  repository: ${ECR_REGISTRY}/retail-store-ui
  tag: latest
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
EOF

    cat > apps/ui/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ui
  labels:
    app: ui
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: ui
  template:
    metadata:
      labels:
        app: ui
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: ui
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            - name: ENDPOINTS_CATALOG
              value: "{{ .Values.env.ENDPOINTS_CATALOG }}"
            - name: ENDPOINTS_CARTS
              value: "{{ .Values.env.ENDPOINTS_CARTS }}"
            - name: ENDPOINTS_ORDERS
              value: "{{ .Values.env.ENDPOINTS_ORDERS }}"
            - name: ENDPOINTS_CHECKOUT
              value: "{{ .Values.env.ENDPOINTS_CHECKOUT }}"
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 60
            periodSeconds: 30
EOF

    cat > apps/ui/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: ui
  labels:
    app: ui
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: ui
EOF

    cat > apps/ui/templates/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ui-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ui
                port:
                  number: {{ .Values.service.port }}
EOF

    #===========================================================================
    # Catalog Service
    #===========================================================================
    cat > apps/catalog/Chart.yaml << 'EOF'
apiVersion: v2
name: catalog
description: Retail Store Catalog Service
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > apps/catalog/values.yaml << EOF
replicaCount: 1

image:
  repository: ${ECR_REGISTRY}/retail-store-catalog
  tag: latest
  pullPolicy: Always

imagePullSecrets:
  - name: regcred

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"

database:
  endpoint: "postgresql:5432"
  name: "catalog"
  user: "postgres"
  password: "postgres"
EOF

    cat > apps/catalog/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  labels:
    app: catalog
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: catalog
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            - name: DB_ENDPOINT
              value: "{{ .Values.database.endpoint }}"
            - name: DB_NAME
              value: "{{ .Values.database.name }}"
            - name: DB_USER
              value: "{{ .Values.database.user }}"
            - name: DB_PASSWORD
              value: "{{ .Values.database.password }}"
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: /health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 30
EOF

    cat > apps/catalog/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: catalog
  labels:
    app: catalog
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: catalog
EOF

    #===========================================================================
    # Cart Service
    #===========================================================================
    cat > apps/cart/Chart.yaml << 'EOF'
apiVersion: v2
name: cart
description: Retail Store Cart Service
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > apps/cart/values.yaml << EOF
replicaCount: 1

image:
  repository: ${ECR_REGISTRY}/retail-store-cart
  tag: latest
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

dynamodb:
  tableName: "${DYNAMODB_TABLE_NAME}"
  region: "${REGION}"

redis:
  endpoint: "redis-master:6379"
EOF

    cat > apps/cart/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
  labels:
    app: cart
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: cart
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            - name: CARTS_DYNAMODB_TABLENAME
              value: "{{ .Values.dynamodb.tableName }}"
            - name: AWS_DEFAULT_REGION
              value: "{{ .Values.dynamodb.region }}"
            - name: SPRING_REDIS_HOST
              value: "redis-master"
            - name: SPRING_REDIS_PORT
              value: "6379"
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 60
            periodSeconds: 30
EOF

    cat > apps/cart/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: cart
  labels:
    app: cart
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: cart
EOF

    #===========================================================================
    # Orders Service
    #===========================================================================
    cat > apps/orders/Chart.yaml << 'EOF'
apiVersion: v2
name: orders
description: Retail Store Orders Service
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > apps/orders/values.yaml << EOF
replicaCount: 1

image:
  repository: ${ECR_REGISTRY}/retail-store-orders
  tag: latest
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

database:
  endpoint: "postgresql:5432"
  name: "catalog"
  user: "postgres"
  password: "postgres"

rabbitmq:
  endpoint: "rabbitmq:5672"
  user: "guest"
  password: "guest"
EOF

    cat > apps/orders/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  labels:
    app: orders
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: orders
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            - name: RETAIL_ORDERS_PERSISTENCE_ENDPOINT
              value: "{{ .Values.database.endpoint }}"
            - name: RETAIL_ORDERS_PERSISTENCE_NAME
              value: "{{ .Values.database.name }}"
            - name: RETAIL_ORDERS_PERSISTENCE_USERNAME
              value: "{{ .Values.database.user }}"
            - name: RETAIL_ORDERS_PERSISTENCE_PASSWORD
              value: "{{ .Values.database.password }}"
            - name: RETAIL_ORDERS_MESSAGING_RABBITMQ_ADDRESSES
              value: "{{ .Values.rabbitmq.endpoint }}"
            - name: RETAIL_ORDERS_MESSAGING_RABBITMQ_USERNAME
              value: "{{ .Values.rabbitmq.user }}"
            - name: RETAIL_ORDERS_MESSAGING_RABBITMQ_PASSWORD
              value: "{{ .Values.rabbitmq.password }}"
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 60
            periodSeconds: 30
EOF

    cat > apps/orders/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: orders
  labels:
    app: orders
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: orders
EOF

    #===========================================================================
    # Checkout Service
    #===========================================================================
    cat > apps/checkout/Chart.yaml << 'EOF'
apiVersion: v2
name: checkout
description: Retail Store Checkout Service
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > apps/checkout/values.yaml << EOF
replicaCount: 1

image:
  repository: ${ECR_REGISTRY}/retail-store-checkout
  tag: latest
  pullPolicy: Always

imagePullSecrets:
  - name: regcred

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"

endpoints:
  orders: "http://orders:80"
  carts: "http://cart:80"

rabbitmq:
  endpoint: "rabbitmq:5672"
  user: "guest"
  password: "guest"
EOF

    cat > apps/checkout/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  labels:
    app: checkout
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: checkout
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            - name: ENDPOINTS_ORDERS
              value: "{{ .Values.endpoints.orders }}"
            - name: ENDPOINTS_CARTS
              value: "{{ .Values.endpoints.carts }}"
            - name: RETAIL_CHECKOUT_MESSAGING_RABBITMQ_ADDRESSES
              value: "{{ .Values.rabbitmq.endpoint }}"
            - name: RETAIL_CHECKOUT_MESSAGING_RABBITMQ_USERNAME
              value: "{{ .Values.rabbitmq.user }}"
            - name: RETAIL_CHECKOUT_MESSAGING_RABBITMQ_PASSWORD
              value: "{{ .Values.rabbitmq.password }}"
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: /health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 30
EOF

    cat > apps/checkout/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: checkout
  labels:
    app: checkout
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: checkout
EOF

    #===========================================================================
    # Dependencies (PostgreSQL, Redis, RabbitMQ)
    #===========================================================================
    cat > apps/dependencies/Chart.yaml << 'EOF'
apiVersion: v2
name: dependencies
description: Retail Store Dependencies (PostgreSQL, Redis, RabbitMQ)
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > apps/dependencies/values.yaml << 'EOF'
postgresql:
  enabled: true
  auth:
    postgresPassword: "postgres"
    database: "catalog"
  primary:
    persistence:
      enabled: false

redis:
  enabled: true
  auth:
    enabled: false
  master:
    persistence:
      enabled: false

rabbitmq:
  enabled: true
  auth:
    username: "guest"
    password: "guest"
  persistence:
    enabled: false
EOF

    cat > apps/dependencies/templates/postgresql.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  labels:
    app: postgresql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
        - name: postgresql
          image: postgres:16.1
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              value: "{{ .Values.postgresql.auth.postgresPassword }}"
            - name: POSTGRES_DB
              value: "{{ .Values.postgresql.auth.database }}"
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - postgres
            initialDelaySeconds: 10
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  labels:
    app: postgresql
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: postgresql
EOF

    cat > apps/dependencies/templates/redis.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-master
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7.2-alpine
          ports:
            - containerPort: 6379
          resources:
            requests:
              memory: "128Mi"
              cpu: "50m"
            limits:
              memory: "256Mi"
              cpu: "200m"
          readinessProbe:
            exec:
              command:
                - redis-cli
                - ping
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: redis-master
  labels:
    app: redis
spec:
  type: ClusterIP
  ports:
    - port: 6379
      targetPort: 6379
  selector:
    app: redis
EOF

    cat > apps/dependencies/templates/rabbitmq.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
  labels:
    app: rabbitmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
        - name: rabbitmq
          image: rabbitmq:3.13-management
          ports:
            - containerPort: 5672
            - containerPort: 15672
          env:
            - name: RABBITMQ_DEFAULT_USER
              value: "{{ .Values.rabbitmq.auth.username }}"
            - name: RABBITMQ_DEFAULT_PASS
              value: "{{ .Values.rabbitmq.auth.password }}"
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          readinessProbe:
            exec:
              command:
                - rabbitmq-diagnostics
                - check_running
            initialDelaySeconds: 30
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  labels:
    app: rabbitmq
spec:
  type: ClusterIP
  ports:
    - name: amqp
      port: 5672
      targetPort: 5672
    - name: management
      port: 15672
      targetPort: 15672
  selector:
    app: rabbitmq
EOF

    print_info "Generating ArgoCD Application manifests..."

    #===========================================================================
    # ArgoCD Applications
    #===========================================================================
    cat > argocd/applications/application-ui.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-ui
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git
    targetRevision: ${GITOPS_BRANCH}
    path: apps/ui
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

    cat > argocd/applications/application-catalog.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-catalog
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git
    targetRevision: ${GITOPS_BRANCH}
    path: apps/catalog
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

    cat > argocd/applications/application-cart.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-cart
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git
    targetRevision: ${GITOPS_BRANCH}
    path: apps/cart
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

    cat > argocd/applications/application-orders.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-orders
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git
    targetRevision: ${GITOPS_BRANCH}
    path: apps/orders
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

    cat > argocd/applications/application-checkout.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-checkout
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git
    targetRevision: ${GITOPS_BRANCH}
    path: apps/checkout
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

    cat > argocd/applications/application-dependencies.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-dependencies
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git
    targetRevision: ${GITOPS_BRANCH}
    path: apps/dependencies
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

    # Create README
    cat > README.md << EOF
# Retail Store GitOps Configuration Repository

This repository contains the Kubernetes manifests and Helm charts for the Retail Store application, managed by ArgoCD.

## Repository Structure

\`\`\`
retail-store-gitops/
├── apps/
│   ├── ui/              # UI Service Helm Chart
│   ├── catalog/         # Catalog Service Helm Chart
│   ├── cart/            # Cart Service Helm Chart
│   ├── orders/          # Orders Service Helm Chart
│   ├── checkout/        # Checkout Service Helm Chart
│   └── dependencies/    # PostgreSQL, Redis, RabbitMQ
│
└── argocd/
    └── applications/    # ArgoCD Application Manifests
\`\`\`

## How It Works

1. **GitHub Actions** builds Docker images and pushes to ECR
2. **GitHub Actions** updates image tags in this repository
3. **ArgoCD** watches this repository for changes
4. **ArgoCD** automatically syncs changes to the Kubernetes cluster

## ArgoCD Applications

| Application | Path | Description |
|-------------|------|-------------|
| retail-store-ui | apps/ui | Store frontend |
| retail-store-catalog | apps/catalog | Product catalog API |
| retail-store-cart | apps/cart | Shopping cart API |
| retail-store-orders | apps/orders | Order management API |
| retail-store-checkout | apps/checkout | Checkout orchestration |
| retail-store-dependencies | apps/dependencies | Databases & messaging |

## Updating Image Tags

Image tags are updated automatically by GitHub Actions in the main application repository.
To manually update, edit the \`values.yaml\` file in the corresponding app directory.

## ECR Registry

Images are stored in: \`${ECR_REGISTRY}\`

## Generated

This repository was generated by \`07-create-gitops-repo.sh\` on $(date).
EOF

    print_success "All GitOps files generated"
}

# Push files to GitHub
push_to_github() {
    print_header "Pushing Files to GitHub"
    
    cd ${TEMP_DIR}
    
    git add .
    git commit -m "Initial GitOps repository setup - generated by 07-create-gitops-repo.sh"
    
    # Use SSH URL instead of HTTPS (works with existing SSH keys)
    git remote add origin "git@github.com:${GITHUB_USER}/${GITOPS_REPO_NAME}.git"

    print_info "Pushing to GitHub via SSH..."
    git push -u origin ${GITOPS_BRANCH}
    
    print_success "Files pushed to GitHub"
}

# Update deployment-info.txt
update_deployment_info() {
    print_header "Updating deployment-info.txt"
    
    cd - > /dev/null  # Return to original directory
    
    # Add GitOps section marker if it doesn't exist
    if ! grep -q "# GitOps Configuration" deployment-info.txt; then
        echo "" >> deployment-info.txt
        echo "# GitOps Configuration" >> deployment-info.txt
    fi
    
    # Update or add GitOps variables
    if grep -q "^export GITHUB_USER=" deployment-info.txt; then
        sed -i "s|^export GITHUB_USER=.*|export GITHUB_USER=\"${GITHUB_USER}\"|" deployment-info.txt
    else
        echo "export GITHUB_USER=\"${GITHUB_USER}\"" >> deployment-info.txt
    fi
    
    if grep -q "^export GITOPS_REPO_NAME=" deployment-info.txt; then
        sed -i "s|^export GITOPS_REPO_NAME=.*|export GITOPS_REPO_NAME=\"${GITOPS_REPO_NAME}\"|" deployment-info.txt
    else
        echo "export GITOPS_REPO_NAME=\"${GITOPS_REPO_NAME}\"" >> deployment-info.txt
    fi
    
    if grep -q "^export GITOPS_REPO_URL=" deployment-info.txt; then
        sed -i "s|^export GITOPS_REPO_URL=.*|export GITOPS_REPO_URL=\"https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git\"|" deployment-info.txt
    else
        echo "export GITOPS_REPO_URL=\"https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}.git\"" >> deployment-info.txt
    fi
    
    print_success "deployment-info.txt updated with GitOps information"
}

# Print summary
print_summary() {
    print_header "GitOps Repository Setup Complete!"
    
    echo -e "${GREEN}✅ GitOps repository created successfully!${NC}"
    echo ""
    echo -e "${BLUE}Repository Details:${NC}"
    echo -e "  Name:   ${CYAN}${GITOPS_REPO_NAME}${NC}"
    echo -e "  URL:    ${CYAN}https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}${NC}"
    echo -e "  Branch: ${CYAN}${GITOPS_BRANCH}${NC}"
    echo ""
    echo -e "${BLUE}Repository Contents:${NC}"
    echo "  • apps/ui/           - UI Service Helm Chart"
    echo "  • apps/catalog/      - Catalog Service Helm Chart"
    echo "  • apps/cart/         - Cart Service Helm Chart"
    echo "  • apps/orders/       - Orders Service Helm Chart"
    echo "  • apps/checkout/     - Checkout Service Helm Chart"
    echo "  • apps/dependencies/ - PostgreSQL, Redis, RabbitMQ"
    echo "  • argocd/applications/ - ArgoCD Application Manifests"
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  NEXT STEP: Create GITOPS_PAT Secret                   ${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}This secret allows GitHub Actions to update the GitOps repo.${NC}"
    echo ""
    echo -e "${BLUE}Step 1: Create Personal Access Token${NC}"
    echo "  1. Go to: https://github.com/settings/tokens"
    echo "  2. Click 'Generate new token' → 'Generate new token (classic)'"
    echo "  3. Settings:"
    echo "     - Note: GitOps automation for retail-store"
    echo "     - Expiration: 90 days (or No expiration)"
    echo "     - Scopes: Check ✅ 'repo' (Full control)"
    echo "  4. Click 'Generate token'"
    echo "  5. COPY THE TOKEN (you won't see it again!)"
    echo ""
    echo -e "${BLUE}Step 2: Add Token as Secret${NC}"
    echo "  1. Go to: https://github.com/${GITHUB_USER}/retail-store-sample-app/settings/secrets/actions"
    echo "  2. Click 'New repository secret'"
    echo "  3. Name: GITOPS_PAT"
    echo "  4. Secret: Paste your token"
    echo "  5. Click 'Add secret'"
    echo ""
    echo -e "${GREEN}After completing these steps, run:${NC}"
    echo -e "  ${YELLOW}./08-argocd-setup.sh${NC}"
    echo ""
}

# Cleanup
cleanup() {
    print_info "Cleaning up temporary files..."
    rm -rf ${TEMP_DIR}
}

# Main execution
main() {
    install_github_cli
    authenticate_github
    check_existing_repo
    create_gitops_repo
    generate_gitops_files
    push_to_github
    update_deployment_info
    print_summary
    cleanup
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     GitOps Repository Setup Completed Successfully!   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}\n"
}

# Run main function
main
