#!/bin/bash

################################################################################
# Kubernetes kubeadm Cluster - ECR Setup Script
# Chat 3: Create ECR repositories and configure Kubernetes imagePullSecrets
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
ECR_REPOSITORIES=(
    "retail-store-ui"
    "retail-store-catalog"
    "retail-store-cart"
    "retail-store-orders"
    "retail-store-checkout"
)

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
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    print_success "AWS CLI installed"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials configured (Account: ${AWS_ACCOUNT_ID})"
    
    # Check if cluster is initialized
    if [ -z "$MASTER_PUBLIC_IP" ]; then
        print_error "Master node IP not found. Run 01-infrastructure.sh first."
        exit 1
    fi
    print_success "Master node IP found: ${MASTER_PUBLIC_IP}"
    
    # Check SSH key
    if [ ! -f "$KEY_FILE" ]; then
        print_error "SSH key not found: $KEY_FILE"
        exit 1
    fi
    print_success "SSH key found"
    
    # Test SSH connectivity
    print_info "Testing SSH connectivity to master..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP "echo 'SSH OK'" &> /dev/null; then
        print_success "Master node reachable"
    else
        print_error "Cannot connect to master node"
        exit 1
    fi
    
    # Verify kubectl access
    print_info "Verifying Kubernetes cluster access..."
    CLUSTER_STATUS=$(ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP "kubectl get nodes 2>/dev/null | wc -l" || echo "0")
    
    if [ "$CLUSTER_STATUS" -lt "2" ]; then
        print_error "Kubernetes cluster not initialized. Run 02-k8s-init.sh first."
        exit 1
    fi
    print_success "Kubernetes cluster is accessible"
}

# Create ECR repositories
create_ecr_repositories() {
    print_header "Creating ECR Repositories"
    
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
    
    print_info "ECR Registry: ${ECR_REGISTRY}"
    echo ""
    
    for REPO_NAME in "${ECR_REPOSITORIES[@]}"; do
        # Check if repository exists
        if aws ecr describe-repositories --repository-names "${REPO_NAME}" --region ${REGION} &> /dev/null; then
            print_warning "Repository already exists: ${REPO_NAME}"
        else
            print_info "Creating repository: ${REPO_NAME}"
            aws ecr create-repository \
                --repository-name "${REPO_NAME}" \
                --region ${REGION} \
                --image-scanning-configuration scanOnPush=true \
                --encryption-configuration encryptionType=AES256 \
                > /dev/null
            
            print_success "Created: ${REPO_NAME}"
        fi
        
        # Get repository URI
        REPO_URI=$(aws ecr describe-repositories \
            --repository-names "${REPO_NAME}" \
            --region ${REGION} \
            --query 'repositories[0].repositoryUri' \
            --output text)
        
        print_info "URI: ${REPO_URI}"
        echo ""
    done
    
    print_success "All ECR repositories ready"
}

# Create Kubernetes imagePullSecret
create_image_pull_secret() {
    print_header "Creating Kubernetes imagePullSecret"
    
    print_info "Getting ECR login credentials..."
    
    # Get ECR login password
    ECR_PASSWORD=$(aws ecr get-login-password --region ${REGION})
    
    if [ -z "$ECR_PASSWORD" ]; then
        print_error "Failed to get ECR login password"
        exit 1
    fi
    print_success "ECR credentials retrieved"
    
    # Check if secret already exists
    print_info "Checking if imagePullSecret 'regcred' exists..."
    SECRET_EXISTS=$(ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP \
        "kubectl get secret regcred 2>/dev/null | wc -l" || echo "0")
    
    if [ "$SECRET_EXISTS" -gt "0" ]; then
        print_warning "Secret 'regcred' already exists. Deleting old secret..."
        ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP << EOF
            kubectl delete secret regcred 2>/dev/null || true
EOF
        print_success "Old secret deleted"
    fi
    
    print_info "Creating new imagePullSecret 'regcred'..."
    
# Create the secret in default namespace
ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP << EOF
    kubectl create secret docker-registry regcred \
        --docker-server=${ECR_REGISTRY} \
        --docker-username=AWS \
        --docker-password='${ECR_PASSWORD}' \
        --docker-email=none@example.com
EOF

print_success "imagePullSecret 'regcred' created in default namespace"

# Create the secret in retail-store namespace (for ArgoCD deployments)
print_info "Creating imagePullSecret in retail-store namespace..."
ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP << EOF
    kubectl create namespace retail-store 2>/dev/null || true
    kubectl delete secret regcred -n retail-store 2>/dev/null || true
    kubectl create secret docker-registry regcred \
        --namespace=retail-store \
        --docker-server=${ECR_REGISTRY} \
        --docker-username=AWS \
        --docker-password='${ECR_PASSWORD}' \
        --docker-email=none@example.com
EOF

print_success "imagePullSecret 'regcred' created in retail-store namespace"
    
    # Verify secret creation
    print_info "Verifying secret..."
    ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP << 'EOF'
        echo "Secret details:"
        kubectl get secret regcred
        echo ""
        echo "✓ Secret is ready for use by Helm charts"
EOF
    
    print_success "Secret verification complete"
}

# Update deployment-info.txt
update_deployment_info() {
    print_header "Updating deployment-info.txt"
    
    # Add ECR section marker if it doesn't exist
    if ! grep -q "# ECR Configuration" deployment-info.txt; then
        echo "" >> deployment-info.txt
        echo "# ECR Configuration" >> deployment-info.txt
    fi
    
    # Update or add AWS Account ID
    if grep -q "^export AWS_ACCOUNT_ID=" deployment-info.txt; then
        sed -i "s|^export AWS_ACCOUNT_ID=.*|export AWS_ACCOUNT_ID=\"${AWS_ACCOUNT_ID}\"|" deployment-info.txt
    else
        echo "export AWS_ACCOUNT_ID=\"${AWS_ACCOUNT_ID}\"" >> deployment-info.txt
    fi
    
    # Update or add ECR Registry
    if grep -q "^export ECR_REGISTRY=" deployment-info.txt; then
        sed -i "s|^export ECR_REGISTRY=.*|export ECR_REGISTRY=\"${ECR_REGISTRY}\"|" deployment-info.txt
    else
        echo "export ECR_REGISTRY=\"${ECR_REGISTRY}\"" >> deployment-info.txt
    fi
    
    # Add individual repository URIs
    for REPO_NAME in "${ECR_REPOSITORIES[@]}"; do
        REPO_URI="${ECR_REGISTRY}/${REPO_NAME}"
        VAR_NAME="ECR_$(echo ${REPO_NAME##*-} | tr '[:lower:]' '[:upper:]')_REPO"
        
        if grep -q "^export ${VAR_NAME}=" deployment-info.txt; then
            sed -i "s|^export ${VAR_NAME}=.*|export ${VAR_NAME}=\"${REPO_URI}\"|" deployment-info.txt
        else
            echo "export ${VAR_NAME}=\"${REPO_URI}\"" >> deployment-info.txt
        fi
    done
    
    print_success "deployment-info.txt updated with ECR information"
    print_info "Load variables with: source deployment-info.txt"
}

# Print summary
print_summary() {
    print_header "ECR Setup Complete!"
    
    echo -e "${GREEN}✅ All ECR resources created successfully!${NC}"
    echo ""
    echo -e "${BLUE}ECR Registry:${NC}"
    echo -e "  ${CYAN}${ECR_REGISTRY}${NC}"
    echo ""
    echo -e "${BLUE}Repositories Created:${NC}"
    for REPO_NAME in "${ECR_REPOSITORIES[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${REPO_NAME}"
        echo -e "    ${CYAN}${ECR_REGISTRY}/${REPO_NAME}${NC}"
    done
    echo ""
    echo -e "${BLUE}Kubernetes Resources:${NC}"
    echo -e "  ${GREEN}✓${NC} imagePullSecret 'regcred' created"
    echo -e "    ${CYAN}kubectl get secret regcred${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  1. ECR repositories are ready for Docker images"
    echo "  2. Kubernetes imagePullSecret 'regcred' is configured"
    echo "  3. Helm charts will use 'regcred' to pull images from ECR"
    echo "  4. ECR login tokens expire after 12 hours"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Configure GitHub Secrets for CI/CD:"
    echo -e "     ${CYAN}AWS_ACCESS_KEY_ID${NC}      - Run: aws configure get aws_access_key_id"
    echo -e "     ${CYAN}AWS_SECRET_ACCESS_KEY${NC}  - Run: aws configure get aws_secret_access_key"
    echo -e "     ${CYAN}AWS_REGION${NC}             - Value: ${REGION}"
    echo -e "     ${CYAN}AWS_ACCOUNT_ID${NC}         - Value: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "  2. Set up GitHub Actions workflow:"
    echo -e "     ${CYAN}.github/workflows/build-and-deploy.yml${NC}"
    echo ""
    echo "  3. Push code to trigger builds:"
    echo -e "     ${CYAN}git push origin main${NC}"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  • List repositories:     aws ecr describe-repositories --region ${REGION}"
    echo "  • List images in repo:   aws ecr list-images --repository-name retail-store-ui --region ${REGION}"
    echo "  • View secret:           kubectl get secret regcred -o yaml"
    echo "  • Delete secret:         kubectl delete secret regcred"
    echo "  • Recreate secret:       Run this script again"
    echo ""
    echo -e "${YELLOW}💡 Tip: ECR tokens expire after 12 hours. If image pulls fail, rerun this script.${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║   Kubernetes kubeadm Cluster - ECR Setup             ║"
    echo "║   Phase 3: Container Registry & Image Pull Secrets   ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    create_ecr_repositories
    create_image_pull_secret
    update_deployment_info
    print_summary
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ECR Setup Completed Successfully! 🎉          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}\n"
}

# Run main function
main
