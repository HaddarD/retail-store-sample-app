#!/bin/bash

################################################################################
# Kubernetes kubeadm Cluster - ArgoCD Setup Script
# Chat 5: Install ArgoCD and configure GitOps deployment
#
# This script:
# 1. Installs ArgoCD on the Kubernetes cluster
# 2. Exposes ArgoCD UI via NodePort
# 3. Uninstalls existing Helm releases (retail-store, dependencies)
# 4. Applies ArgoCD Application manifests
# 5. Waits for applications to sync
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
ARGOCD_NAMESPACE="argocd"
ARGOCD_NODEPORT="30090"
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
echo "║   Kubernetes kubeadm Cluster - ArgoCD Setup          ║"
echo "║   Phase 5.2: Install ArgoCD & Configure GitOps       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    print_success "kubectl installed"
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "Helm not found. Please run: ./install-helm-local.sh"
        exit 1
    fi
    print_success "Helm installed"
    
    # Check SSH key
    if [ ! -f "$KEY_FILE" ]; then
        print_error "SSH key not found: $KEY_FILE"
        exit 1
    fi
    print_success "SSH key found"
    
    # Check GitOps variables
    if [ -z "$GITOPS_REPO_URL" ]; then
        print_error "GitOps repository URL not found in deployment-info.txt"
        print_info "Please run ./07-create-gitops-repo.sh first"
        exit 1
    fi
    print_success "GitOps repo configured: ${GITOPS_REPO_URL}"
    
    # Configure kubectl
    print_info "Configuring kubectl..."
    mkdir -p ~/.kube
    scp -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP:~/.kube/config ~/.kube/config-retail-store 2>/dev/null || true
    sed -i "s|server: https://.*:6443|server: https://${MASTER_PUBLIC_IP}:6443|g" ~/.kube/config-retail-store
    export KUBECONFIG=~/.kube/config-retail-store
    kubectl config set-cluster kubernetes --insecure-skip-tls-verify=true 2>/dev/null
    
    # Check cluster connectivity
    print_info "Testing cluster connectivity..."
    if ! kubectl get nodes &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Have you run ./startup.sh to start the instances?"
        exit 1
    fi
    
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    print_success "Cluster connected (${NODE_COUNT} nodes)"
    echo ""
    kubectl get nodes
    echo ""
}

# Uninstall existing Helm releases
uninstall_helm_releases() {
    print_header "Uninstalling Existing Helm Releases"
    
    print_info "This step removes Helm-managed deployments so ArgoCD can take over."
    echo ""
    
    # Uninstall retail-store
    if helm list -n ${NAMESPACE} 2>/dev/null | grep -q "retail-store"; then
        print_info "Uninstalling retail-store..."
        helm uninstall retail-store -n ${NAMESPACE} --wait --timeout 3m 2>/dev/null || print_warning "retail-store uninstall had issues"
        print_success "retail-store uninstalled"
    else
        print_info "retail-store not found (already uninstalled)"
    fi
    
    # Uninstall dependencies
    DEPS=("rabbitmq" "redis" "postgresql")
    for dep in "${DEPS[@]}"; do
        if helm list -n ${NAMESPACE} 2>/dev/null | grep -q "^${dep}"; then
            print_info "Uninstalling ${dep}..."
            helm uninstall ${dep} -n ${NAMESPACE} --wait --timeout 3m 2>/dev/null || print_warning "${dep} uninstall had issues"
            print_success "${dep} uninstalled"
        else
            print_info "${dep} not found (already uninstalled)"
        fi
    done
    
    # Keep ingress-nginx - ArgoCD will not manage it
    print_info "Keeping ingress-nginx (required for external access)"
    
    # Wait for pods to terminate
    print_info "Waiting for pods to terminate..."
    sleep 10
    
    # Check remaining pods
    REMAINING=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING" -gt 0 ]; then
        print_warning "Some pods still terminating..."
        kubectl get pods -n ${NAMESPACE}
        sleep 20
    fi
    
    print_success "Helm releases uninstalled - ArgoCD will manage deployments now"
}

# Install ArgoCD
install_argocd() {
    print_header "Installing ArgoCD"
    
    # Check if ArgoCD is already installed
    if kubectl get namespace ${ARGOCD_NAMESPACE} &> /dev/null; then
        ARGOCD_PODS=$(kubectl get pods -n ${ARGOCD_NAMESPACE} --no-headers 2>/dev/null | grep "Running" | wc -l)
        if [ "$ARGOCD_PODS" -gt 0 ]; then
            print_warning "ArgoCD already installed (${ARGOCD_PODS} pods running)"
            return
        fi
    fi
    
    # Create namespace
    print_info "Creating argocd namespace..."
    kubectl create namespace ${ARGOCD_NAMESPACE} 2>/dev/null || print_info "Namespace already exists"
    
    # Install ArgoCD
    print_info "Installing ArgoCD (stable release)..."
    kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    print_success "ArgoCD installation initiated"
    
    # Wait for ArgoCD to be ready
    print_info "Waiting for ArgoCD pods to be ready (this may take 2-3 minutes)..."
    
    # Wait for deployments
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${ARGOCD_NAMESPACE} 2>/dev/null || true
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n ${ARGOCD_NAMESPACE} 2>/dev/null || true
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n ${ARGOCD_NAMESPACE} 2>/dev/null || true
    
    # Verify pods
    TIMEOUT=180
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        READY_PODS=$(kubectl get pods -n ${ARGOCD_NAMESPACE} --no-headers 2>/dev/null | grep "Running" | wc -l)
        TOTAL_PODS=$(kubectl get pods -n ${ARGOCD_NAMESPACE} --no-headers 2>/dev/null | wc -l)
        
        if [ "$READY_PODS" -ge 5 ]; then
            print_success "ArgoCD pods ready (${READY_PODS}/${TOTAL_PODS})"
            break
        fi
        
        print_info "Waiting for ArgoCD pods... (${READY_PODS}/${TOTAL_PODS} ready)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    echo ""
    kubectl get pods -n ${ARGOCD_NAMESPACE}
    echo ""
}

# Expose ArgoCD UI
expose_argocd() {
    print_header "Exposing ArgoCD UI"
    
    # Check if already exposed
    EXISTING_TYPE=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.spec.type}' 2>/dev/null)
    
    if [ "$EXISTING_TYPE" = "NodePort" ]; then
        EXISTING_PORT=$(kubectl get svc argocd-server -n ${ARGOCD_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        print_warning "ArgoCD already exposed as NodePort on port ${EXISTING_PORT}"
        return
    fi
    
    # Patch service to NodePort
    print_info "Patching argocd-server service to NodePort..."
    kubectl patch svc argocd-server -n ${ARGOCD_NAMESPACE} -p "{\"spec\": {\"type\": \"NodePort\", \"ports\": [{\"port\": 443, \"targetPort\": 8080, \"nodePort\": ${ARGOCD_NODEPORT}}]}}"
    
    print_success "ArgoCD UI exposed on NodePort ${ARGOCD_NODEPORT}"
}

# Get ArgoCD admin password
get_argocd_password() {
    print_header "Retrieving ArgoCD Admin Password"
    
    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if [ -z "$ARGOCD_PASSWORD" ]; then
        print_warning "Could not retrieve initial admin password"
        print_info "The secret may have been deleted. Try resetting the password:"
        echo "  kubectl -n argocd patch secret argocd-secret -p '{\"stringData\": {\"admin.password\": \"<bcrypt-hash>\"}}'"
        ARGOCD_PASSWORD="(manual reset required)"
    else
        print_success "Admin password retrieved"
    fi
    
    export ARGOCD_PASSWORD
}

# Apply ArgoCD Applications
apply_argocd_applications() {
    print_header "Applying ArgoCD Applications"
    
    print_info "Cloning GitOps repository to get Application manifests..."
    
    TEMP_DIR="/tmp/argocd-apps-$$"
    rm -rf ${TEMP_DIR}
    
    git clone ${GITOPS_REPO_URL} ${TEMP_DIR}
    
    # Ensure namespace exists
    kubectl create namespace ${NAMESPACE} 2>/dev/null || print_info "Namespace ${NAMESPACE} already exists"
    
    # Apply all Application manifests
    print_info "Applying ArgoCD Application manifests..."
    
    for app_file in ${TEMP_DIR}/argocd/applications/*.yaml; do
        app_name=$(basename ${app_file} .yaml)
        print_info "Applying ${app_name}..."
        kubectl apply -f ${app_file}
    done
    
    print_success "All ArgoCD Applications applied"
    
    # Cleanup
    rm -rf ${TEMP_DIR}
}

# Wait for applications to sync
wait_for_sync() {
    print_header "Waiting for Applications to Sync"
    
    print_info "ArgoCD is now syncing applications from the GitOps repository..."
    print_info "This may take 5-10 minutes for all services to start."
    echo ""
    
    # List applications
    echo -e "${BLUE}ArgoCD Applications:${NC}"
    kubectl get applications -n ${ARGOCD_NAMESPACE}
    echo ""
    
    # Wait for sync
    TIMEOUT=600
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        SYNCED=$(kubectl get applications -n ${ARGOCD_NAMESPACE} -o jsonpath='{range .items[*]}{.status.sync.status}{"\n"}{end}' 2>/dev/null | grep -c "Synced" || echo "0")
        TOTAL=$(kubectl get applications -n ${ARGOCD_NAMESPACE} --no-headers 2>/dev/null | wc -l)
        
        if [ "$SYNCED" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
            print_success "All applications synced (${SYNCED}/${TOTAL})"
            break
        fi
        
        print_info "Syncing... (${SYNCED}/${TOTAL} synced)"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    done
    
    echo ""
    print_info "Application Status:"
    kubectl get applications -n ${ARGOCD_NAMESPACE}
    echo ""
    
    print_info "Pods in ${NAMESPACE} namespace:"
    kubectl get pods -n ${NAMESPACE}
    echo ""
}

# Update deployment-info.txt
update_deployment_info() {
    print_header "Updating deployment-info.txt"
    
    # Add ArgoCD section marker if it doesn't exist
    if ! grep -q "# ArgoCD Configuration" deployment-info.txt; then
        echo "" >> deployment-info.txt
        echo "# ArgoCD Configuration" >> deployment-info.txt
    fi
    
    # Update or add ArgoCD variables
    if grep -q "^export ARGOCD_NAMESPACE=" deployment-info.txt; then
        sed -i "s|^export ARGOCD_NAMESPACE=.*|export ARGOCD_NAMESPACE=\"${ARGOCD_NAMESPACE}\"|" deployment-info.txt
    else
        echo "export ARGOCD_NAMESPACE=\"${ARGOCD_NAMESPACE}\"" >> deployment-info.txt
    fi
    
    if grep -q "^export ARGOCD_NODEPORT=" deployment-info.txt; then
        sed -i "s|^export ARGOCD_NODEPORT=.*|export ARGOCD_NODEPORT=\"${ARGOCD_NODEPORT}\"|" deployment-info.txt
    else
        echo "export ARGOCD_NODEPORT=\"${ARGOCD_NODEPORT}\"" >> deployment-info.txt
    fi
    
    if grep -q "^export ARGOCD_URL=" deployment-info.txt; then
        sed -i "s|^export ARGOCD_URL=.*|export ARGOCD_URL=\"https://${MASTER_PUBLIC_IP}:${ARGOCD_NODEPORT}\"|" deployment-info.txt
    else
        echo "export ARGOCD_URL=\"https://${MASTER_PUBLIC_IP}:${ARGOCD_NODEPORT}\"" >> deployment-info.txt
    fi
    
    if grep -q "^export ARGOCD_ADMIN_PASSWORD=" deployment-info.txt; then
        sed -i "s|^export ARGOCD_ADMIN_PASSWORD=.*|export ARGOCD_ADMIN_PASSWORD=\"${ARGOCD_PASSWORD}\"|" deployment-info.txt
    else
        echo "export ARGOCD_ADMIN_PASSWORD=\"${ARGOCD_PASSWORD}\"" >> deployment-info.txt
    fi
    
    print_success "deployment-info.txt updated with ArgoCD information"
}

# Print summary
print_summary() {
    print_header "ArgoCD Setup Complete!"
    
    echo -e "${GREEN}✅ ArgoCD is installed and configured!${NC}"
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ArgoCD Access Information                             ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}ArgoCD UI:${NC}"
    echo -e "  URL:      ${YELLOW}https://${MASTER_PUBLIC_IP}:${ARGOCD_NODEPORT}${NC}"
    echo -e "  Username: ${YELLOW}admin${NC}"
    echo -e "  Password: ${YELLOW}${ARGOCD_PASSWORD}${NC}"
    echo ""
    echo -e "${CYAN}Note:${NC} Your browser will show a security warning (self-signed cert)."
    echo "      Click 'Advanced' → 'Proceed' to access the UI."
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Application Access                                    ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Retail Store App:${NC}"
    echo -e "  URL:      ${YELLOW}http://${MASTER_PUBLIC_IP}:30080${NC}"
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  GitOps Workflow Test                                  ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "To test the GitOps workflow:"
    echo ""
    echo "  1. Make a code change in your main repo (e.g., edit src/ui/...)"
    echo "  2. Commit and push:"
    echo "     git add . && git commit -m 'Test GitOps' && git push"
    echo "  3. Watch GitHub Actions build the image"
    echo "  4. Watch ArgoCD automatically sync the new version"
    echo "  5. Refresh the app in your browser to see the change!"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  # Check ArgoCD applications"
    echo "  kubectl get applications -n argocd"
    echo ""
    echo "  # Check application pods"
    echo "  kubectl get pods -n retail-store"
    echo ""
    echo "  # View ArgoCD logs"
    echo "  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    uninstall_helm_releases
    install_argocd
    expose_argocd
    get_argocd_password
    apply_argocd_applications
    wait_for_sync
    update_deployment_info
    print_summary
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       ArgoCD Setup Completed Successfully! 🎉         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}\n"
}

# Run main function
main
