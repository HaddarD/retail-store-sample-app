#!/bin/bash

################################################################################
# Kubernetes kubeadm Cluster - ECR Setup Script (Terraform Version)
# Chat 3: Create ECR repositories with Terraform and configure imagePullSecrets
#
# This script handles two scenarios:
#   1. FIRST RUN: Creates ECR repos with Terraform + creates regcred secret
#   2. REFRESH RUN: Only refreshes regcred secret (every 12 hours)
#
# Usage:
#   ./03-ecr-setup.sh          # Auto-detect: create or refresh
#   ./03-ecr-setup.sh --refresh # Force refresh only (skip Terraform)
#   ./03-ecr-setup.sh --create  # Force create (run Terraform even if exists)
################################################################################

set -e  # Exit on any error

# Script directory (for finding terraform files)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform/ecr"

# Load environment variables
if [ ! -f "${SCRIPT_DIR}/deployment-info.txt" ]; then
    echo "❌ ERROR: deployment-info.txt not found!"
    echo "Please run 01-infrastructure.sh first"
    exit 1
fi

source "${SCRIPT_DIR}/deployment-info.txt"

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

# Parse command line arguments
FORCE_REFRESH=false
FORCE_CREATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --refresh)
            FORCE_REFRESH=true
            shift
            ;;
        --create)
            FORCE_CREATE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--refresh|--create]"
            exit 1
            ;;
    esac
done

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

    # Check Terraform (only if we might need it)
    if [ "$FORCE_REFRESH" = false ]; then
        if ! command -v terraform &> /dev/null; then
            print_error "Terraform not found. Please run: ./install-terraform.sh"
            exit 1
        fi
        TERRAFORM_VERSION=$(terraform --version | head -n 1)
        print_success "Terraform installed: ${TERRAFORM_VERSION}"
    fi

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

    # Set ECR Registry URL
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
}

# Check if ECR repositories already exist
check_ecr_exists() {
    print_header "Checking ECR Repository Status"

    ECR_EXISTS=true

    for REPO_NAME in "${ECR_REPOSITORIES[@]}"; do
        if aws ecr describe-repositories --repository-names "${REPO_NAME}" --region ${REGION} &> /dev/null; then
            print_info "Repository exists: ${REPO_NAME}"
        else
            print_info "Repository missing: ${REPO_NAME}"
            ECR_EXISTS=false
        fi
    done

    if [ "$ECR_EXISTS" = true ]; then
        print_success "All ECR repositories exist"
        return 0
    else
        print_warning "Some ECR repositories are missing"
        return 1
    fi
}

# Create ECR repositories using Terraform
create_ecr_with_terraform() {
    print_header "Creating ECR Repositories with Terraform"

    # Check if terraform directory exists
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_error "Terraform directory not found: $TERRAFORM_DIR"
        print_info "Please ensure terraform/ecr/ directory exists with .tf files"
        exit 1
    fi

    cd "$TERRAFORM_DIR"

    # Update terraform.tfvars with current region
    print_info "Updating Terraform variables..."
    sed -i "s|^aws_region.*|aws_region   = \"${REGION}\"|" terraform.tfvars

    # Initialize Terraform
    print_info "Initializing Terraform..."
    terraform init -input=false
    print_success "Terraform initialized"

    # Plan
    print_info "Creating Terraform plan..."
    terraform plan -input=false -out=tfplan
    print_success "Plan created"

    # Apply
    print_info "Applying Terraform configuration..."
    terraform apply -input=false -auto-approve tfplan
    print_success "Terraform apply complete"

    # Clean up plan file
    rm -f tfplan

    # Show outputs
    print_info "ECR Resources created:"
    terraform output -json ecr_repository_urls | jq -r 'to_entries[] | "  ✓ \(.key): \(.value)"'

    cd "$SCRIPT_DIR"

    print_success "ECR repositories created with Terraform"
}

# Create Kubernetes imagePullSecret
create_image_pull_secret() {
    print_header "Creating/Refreshing Kubernetes imagePullSecret"

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

    # Create the secret on the cluster
    ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@$MASTER_PUBLIC_IP << EOF
        kubectl create secret docker-registry regcred \
            --docker-server=${ECR_REGISTRY} \
            --docker-username=AWS \
            --docker-password='${ECR_PASSWORD}' \
            --docker-email=none@example.com
EOF

    print_success "imagePullSecret 'regcred' created successfully"

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

    cd "$SCRIPT_DIR"

    # Add ECR section marker if it doesn't exist
    if ! grep -q "# ECR Configuration" deployment-info.txt; then
        echo "" >> deployment-info.txt
        echo "# ECR Configuration (Terraform Managed)" >> deployment-info.txt
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
    local MODE=$1

    print_header "ECR Setup Complete!"

    if [ "$MODE" = "create" ]; then
        echo -e "${GREEN}✅ ECR repositories created with Terraform${NC}"
    else
        echo -e "${GREEN}✅ ECR credentials refreshed${NC}"
    fi

    echo ""
    echo -e "${BLUE}ECR Registry:${NC}"
    echo -e "  ${CYAN}${ECR_REGISTRY}${NC}"
    echo ""
    echo -e "${BLUE}Repositories:${NC}"
    for REPO_NAME in "${ECR_REPOSITORIES[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${REPO_NAME}"
        echo -e "    ${CYAN}${ECR_REGISTRY}/${REPO_NAME}${NC}"
    done
    echo ""
    echo -e "${BLUE}Kubernetes Resources:${NC}"
    echo -e "  ${GREEN}✓${NC} imagePullSecret 'regcred' created/refreshed"
    echo -e "    ${CYAN}kubectl get secret regcred${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • ECR login tokens expire after 12 hours"
    echo "  • Rerun this script to refresh: ./03-ecr-setup.sh --refresh"
    echo "  • Terraform state stored in: terraform/ecr/"
    echo ""

    if [ "$MODE" = "create" ]; then
        echo -e "${BLUE}Next Steps:${NC}"
        echo "  1. Configure GitHub Secrets for CI/CD:"
        echo -e "     ${CYAN}AWS_ACCESS_KEY_ID${NC}      - Run: aws configure get aws_access_key_id"
        echo -e "     ${CYAN}AWS_SECRET_ACCESS_KEY${NC}  - Run: aws configure get aws_secret_access_key"
        echo -e "     ${CYAN}AWS_REGION${NC}             - Value: ${REGION}"
        echo -e "     ${CYAN}AWS_ACCOUNT_ID${NC}         - Value: ${AWS_ACCOUNT_ID}"
        echo ""
        echo "  2. Copy GitHub Actions workflow to your repo:"
        echo -e "     ${CYAN}mkdir -p .github/workflows${NC}"
        echo -e "     ${CYAN}cp .github/workflows/build-and-deploy.yml .github/workflows/${NC}"
        echo ""
        echo "  3. Push code to trigger builds:"
        echo -e "     ${CYAN}git push origin main${NC}"
    else
        echo -e "${BLUE}Token Refresh Complete!${NC}"
        echo "  • regcred secret has been updated with new ECR token"
        echo "  • Valid for the next 12 hours"
        echo "  • Next refresh needed: $(date -d '+12 hours' '+%Y-%m-%d %H:%M:%S')"
    fi
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  • List repositories:     aws ecr describe-repositories --region ${REGION}"
    echo "  • List images in repo:   aws ecr list-images --repository-name retail-store-ui --region ${REGION}"
    echo "  • View secret:           kubectl get secret regcred -o yaml"
    echo "  • Terraform status:      cd terraform/ecr && terraform show"
    echo "  • Refresh token:         ./03-ecr-setup.sh --refresh"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║   Kubernetes kubeadm Cluster - ECR Setup (Terraform) ║"
    echo "║   Phase 3: Container Registry & Image Pull Secrets   ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_prerequisites

    # Determine operation mode
    if [ "$FORCE_REFRESH" = true ]; then
        print_info "Mode: REFRESH ONLY (--refresh flag)"
        create_image_pull_secret
        update_deployment_info
        print_summary "refresh"
    elif [ "$FORCE_CREATE" = true ]; then
        print_info "Mode: FORCE CREATE (--create flag)"
        create_ecr_with_terraform
        create_image_pull_secret
        update_deployment_info
        print_summary "create"
    else
        # Auto-detect mode
        if check_ecr_exists; then
            print_info "Mode: AUTO - ECR exists, refreshing token only"
            create_image_pull_secret
            update_deployment_info
            print_summary "refresh"
        else
            print_info "Mode: AUTO - Creating ECR with Terraform"
            create_ecr_with_terraform
            create_image_pull_secret
            update_deployment_info
            print_summary "create"
        fi
    fi

    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ECR Setup Completed Successfully! 🎉          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}\n"
}

# Run main function
main