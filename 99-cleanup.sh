#!/bin/bash

################################################################################
# Kubernetes kubeadm Cluster - Complete Cleanup Script
# This script removes ALL resources created by the project
#
# Updated: Chat 5 - Added ArgoCD cleanup
#
# Cleanup order:
#   Step 0: ArgoCD Applications and ArgoCD itself
#   Step 1: Helm releases and namespaces
#   Step 2: DynamoDB table
#   Step 3: IAM instance profile disassociation
#   Step 4: EC2 instances
#   Step 5: Security group
#   Step 6: IAM resources
#   Step 7: SSH key pair
#   Step 8: ECR repositories
#   Step 9: GitOps repository (optional)
#   Step 10: Local files
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper functions
print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
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

# Load deployment info
if [ -f deployment-info.txt ]; then
    source deployment-info.txt
    print_success "Loaded deployment-info.txt"
else
    print_warning "deployment-info.txt not found - using defaults"
    REGION="us-east-1"
fi

# Main header
echo -e "${RED}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║   ⚠️  COMPLETE PROJECT CLEANUP ⚠️                      ║"
echo "║                                                       ║"
echo "║   This will DELETE all resources:                     ║"
echo "║   - ArgoCD and all Applications                       ║"
echo "║   - Kubernetes deployments                            ║"
echo "║   - EC2 instances (Master + Workers)                  ║"
echo "║   - DynamoDB table                                    ║"
echo "║   - ECR repositories and images                       ║"
echo "║   - IAM roles and policies                            ║"
echo "║   - Security groups                                   ║"
echo "║   - SSH key pairs                                     ║"
echo "║   - GitOps repository (optional)                      ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
read -p "Are you sure you want to delete EVERYTHING? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
read -p "Really sure? Type 'DELETE' to confirm: " CONFIRM2
if [ "$CONFIRM2" != "DELETE" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

################################################################################
# Step 0: ArgoCD Cleanup
################################################################################
cleanup_argocd() {
    print_header "Step 0: Cleaning up ArgoCD"

    # Check if we can access the cluster
    if ! kubectl get nodes &>/dev/null; then
        print_warning "Cannot access Kubernetes cluster - skipping ArgoCD cleanup"
        return
    fi

    # Check if ArgoCD namespace exists
    if kubectl get namespace argocd &>/dev/null; then
        print_info "Deleting ArgoCD Applications..."

        # Delete all ArgoCD applications (this removes managed resources too)
        kubectl delete applications --all -n argocd 2>/dev/null || true

        # Wait for applications to be deleted
        sleep 10

        print_info "Uninstalling ArgoCD..."
        kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || true

        print_info "Deleting ArgoCD namespace..."
        kubectl delete namespace argocd --timeout=60s 2>/dev/null || true

        print_success "ArgoCD cleaned up"
    else
        print_info "ArgoCD namespace not found - skipping"
    fi
}

################################################################################
# Step 1: Helm Releases and Namespaces
################################################################################
cleanup_helm() {
    print_header "Step 1: Cleaning up Helm Releases"

    # Check if we can access the cluster
    if ! kubectl get nodes &>/dev/null; then
        print_warning "Cannot access Kubernetes cluster - skipping Helm cleanup"
        return
    fi

    # Check if Helm is installed
    if ! command -v helm &>/dev/null; then
        print_warning "Helm not installed - skipping Helm cleanup"
        return
    fi

    # Uninstall Helm releases
    RELEASES=("retail-store" "ingress-nginx" "postgresql" "redis" "rabbitmq")
    NAMESPACES=("retail-store" "ingress-nginx")

    for release in "${RELEASES[@]}"; do
        for ns in "${NAMESPACES[@]}" "default"; do
            if helm list -n "$ns" 2>/dev/null | grep -q "^${release}"; then
                print_info "Uninstalling Helm release: ${release} from ${ns}..."
                helm uninstall "$release" -n "$ns" --wait --timeout 2m 2>/dev/null || true
                print_success "Uninstalled ${release}"
            fi
        done
    done

    # Delete namespaces
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            print_info "Deleting namespace: ${ns}..."
            kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || true
            print_success "Deleted namespace ${ns}"
        fi
    done

    print_success "Helm cleanup complete"
}

################################################################################
# Step 2: DynamoDB Table
################################################################################
cleanup_dynamodb() {
    print_header "Step 2: Cleaning up DynamoDB"

    TABLE_NAME="${DYNAMODB_TABLE_NAME:-retail-store-cart}"

    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" &>/dev/null; then
        print_info "Deleting DynamoDB table: ${TABLE_NAME}..."
        aws dynamodb delete-table --table-name "$TABLE_NAME" --region "$REGION"

        print_info "Waiting for table deletion..."
        aws dynamodb wait table-not-exists --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null || true

        print_success "DynamoDB table deleted"
    else
        print_info "DynamoDB table not found - skipping"
    fi
}

################################################################################
# Step 3: IAM Instance Profile Disassociation
################################################################################
cleanup_instance_profile() {
    print_header "Step 3: Disassociating IAM Instance Profiles"

    INSTANCE_IDS=("$MASTER_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID")

    for instance_id in "${INSTANCE_IDS[@]}"; do
        if [ -n "$instance_id" ]; then
            # Get association ID
            ASSOCIATION_ID=$(aws ec2 describe-iam-instance-profile-associations \
                --filters "Name=instance-id,Values=${instance_id}" \
                --query 'IamInstanceProfileAssociations[0].AssociationId' \
                --output text 2>/dev/null)

            if [ -n "$ASSOCIATION_ID" ] && [ "$ASSOCIATION_ID" != "None" ]; then
                print_info "Disassociating profile from ${instance_id}..."
                aws ec2 disassociate-iam-instance-profile --association-id "$ASSOCIATION_ID" 2>/dev/null || true
                print_success "Disassociated from ${instance_id}"
            fi
        fi
    done

    print_success "Instance profile disassociation complete"
}

################################################################################
# Step 4: EC2 Instances
################################################################################
cleanup_ec2() {
    print_header "Step 4: Terminating EC2 Instances"

    INSTANCE_IDS=("$MASTER_INSTANCE_ID" "$WORKER1_INSTANCE_ID" "$WORKER2_INSTANCE_ID")
    VALID_IDS=()

    for instance_id in "${INSTANCE_IDS[@]}"; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            # Check if instance exists
            if aws ec2 describe-instances --instance-ids "$instance_id" &>/dev/null; then
                VALID_IDS+=("$instance_id")
            fi
        fi
    done

    if [ ${#VALID_IDS[@]} -gt 0 ]; then
        print_info "Terminating instances: ${VALID_IDS[*]}..."
        aws ec2 terminate-instances --instance-ids "${VALID_IDS[@]}" --region "$REGION"

        print_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids "${VALID_IDS[@]}" --region "$REGION"

        print_success "EC2 instances terminated"
    else
        print_info "No EC2 instances found - skipping"
    fi
}

################################################################################
# Step 5: Security Group
################################################################################
cleanup_security_group() {
    print_header "Step 5: Deleting Security Group"

    SG_ID="${SECURITY_GROUP_ID}"

    if [ -n "$SG_ID" ]; then
        # Wait a bit for instances to fully terminate
        sleep 10

        if aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" &>/dev/null; then
            print_info "Deleting security group: ${SG_ID}..."
            aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" 2>/dev/null || true
            print_success "Security group deleted"
        else
            print_info "Security group not found - skipping"
        fi
    else
        print_info "No security group ID found - skipping"
    fi
}

################################################################################
# Step 6: IAM Resources
################################################################################
cleanup_iam() {
    print_header "Step 6: Cleaning up IAM Resources"

    ROLE_NAME="${IAM_ROLE_NAME:-k8s-kubeadm-ecr-role}"
    PROFILE_NAME="${IAM_INSTANCE_PROFILE_NAME:-k8s-kubeadm-ecr-profile}"

    # Remove role from instance profile
    if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" &>/dev/null; then
        print_info "Removing role from instance profile..."
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$PROFILE_NAME" \
            --role-name "$ROLE_NAME" 2>/dev/null || true

        print_info "Deleting instance profile..."
        aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME" 2>/dev/null || true
        print_success "Instance profile deleted"
    fi

    # Detach policies and delete role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_info "Detaching policies from role..."

        # Detach managed policies
        POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)

        for policy_arn in $POLICIES; do
            aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" 2>/dev/null || true
        done

        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" \
            --query 'PolicyNames' --output text 2>/dev/null)

        for policy_name in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy_name" 2>/dev/null || true
        done

        print_info "Deleting IAM role..."
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
        print_success "IAM role deleted"
    else
        print_info "IAM role not found - skipping"
    fi
}

################################################################################
# Step 7: SSH Key Pair
################################################################################
cleanup_ssh_key() {
    print_header "Step 7: Deleting SSH Key Pair"

    KEY_NAME="${KEY_NAME:-k8s-kubeadm-key}"

    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
        print_info "Deleting key pair: ${KEY_NAME}..."
        aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
        print_success "Key pair deleted"
    else
        print_info "Key pair not found - skipping"
    fi
}

################################################################################
# Step 8: ECR Repositories (Terraform)
################################################################################
cleanup_ecr() {
    print_header "Step 8: Deleting ECR Repositories"

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    TERRAFORM_DIR="${SCRIPT_DIR}/terraform/ecr"

    REPOS=("retail-store-ui" "retail-store-catalog" "retail-store-cart" "retail-store-orders" "retail-store-checkout")

    # Try Terraform first if state exists
    if [ -d "$TERRAFORM_DIR" ] && [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        print_info "Found Terraform state - using terraform destroy..."

        cd "$TERRAFORM_DIR"
        terraform init -input=false > /dev/null 2>&1

        if terraform destroy -auto-approve -input=false; then
            print_success "ECR repositories destroyed via Terraform"
            cd "$SCRIPT_DIR"
            return
        else
            print_warning "Terraform destroy failed - falling back to AWS CLI"
            cd "$SCRIPT_DIR"
        fi
    else
        print_info "No Terraform state found - using AWS CLI"
    fi

    # Fallback: AWS CLI
    for repo in "${REPOS[@]}"; do
        if aws ecr describe-repositories --repository-names "$repo" --region "$REGION" &>/dev/null; then
            print_info "Deleting ECR repository: ${repo}..."
            aws ecr delete-repository --repository-name "$repo" --region "$REGION" --force
            print_success "Deleted ${repo}"
        else
            print_info "Repository ${repo} not found - skipping"
        fi
    done

    print_success "ECR cleanup complete"
}

################################################################################
# Step 9: GitOps Repository (Optional)
################################################################################
cleanup_gitops_repo() {
    print_header "Step 9: GitOps Repository"

    if [ -n "$GITHUB_USER" ] && [ -n "$GITOPS_REPO_NAME" ]; then
        echo ""
        read -p "Do you want to delete the GitOps repository (${GITOPS_REPO_NAME})? (yes/no): " DELETE_GITOPS

        if [ "$DELETE_GITOPS" = "yes" ]; then
            if command -v gh &>/dev/null; then
                print_info "Deleting GitOps repository..."
                gh repo delete "${GITHUB_USER}/${GITOPS_REPO_NAME}" --yes 2>/dev/null || true
                print_success "GitOps repository deleted"
            else
                print_warning "GitHub CLI not installed - delete manually at:"
                echo "  https://github.com/${GITHUB_USER}/${GITOPS_REPO_NAME}/settings"
            fi
        else
            print_info "Keeping GitOps repository"
        fi
    else
        print_info "No GitOps repository configured - skipping"
    fi
}

################################################################################
# Step 10: Local Files
################################################################################
cleanup_local_files() {
    print_header "Step 10: Cleaning up Local Files"

    # Remove SSH key file
    if [ -f "${KEY_NAME}.pem" ]; then
        print_info "Removing SSH key file..."
        rm -f "${KEY_NAME}.pem"
        print_success "SSH key file removed"
    fi

    # Remove kubeconfig
    if [ -f ~/.kube/config-retail-store ]; then
        print_info "Removing kubeconfig..."
        rm -f ~/.kube/config-retail-store
        print_success "Kubeconfig removed"
    fi

    # Ask about deployment-info.txt
    echo ""
    read -p "Do you want to delete deployment-info.txt? (yes/no): " DELETE_DEPLOYMENT

    if [ "$DELETE_DEPLOYMENT" = "yes" ]; then
        rm -f deployment-info.txt
        print_success "deployment-info.txt removed"
    else
        print_info "Keeping deployment-info.txt"
    fi

    print_success "Local files cleanup complete"
}

################################################################################
# Run Cleanup
################################################################################

cleanup_argocd
cleanup_helm
cleanup_dynamodb
cleanup_instance_profile
cleanup_ec2
cleanup_security_group
cleanup_iam
cleanup_ssh_key
cleanup_ecr
cleanup_gitops_repo
cleanup_local_files

################################################################################
# Summary
################################################################################

print_header "Cleanup Complete!"

echo -e "${GREEN}All resources have been deleted.${NC}"
echo ""
echo -e "${BLUE}To recreate the project from scratch, run:${NC}"
echo "  1. ./01-infrastructure.sh"
echo "  2. ./02-k8s-init.sh"
echo "  3. ./ 03-Install-terraform.sh"
echo "  4. ./04-ecr-setup.sh"
echo "  5. ./05-dynamodb-setup.sh"
echo "  6. ./ 06-install-helm-local.sh"
echo "  7. ./07-helm-deploy.sh      # For Helm-only deployment"
echo "  OR"
echo "  8. ./08-create-gitops-repo.sh  # For GitOps deployment"
echo "  9. ./09-argocd-setup.sh"
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Cleanup Completed Successfully! 🧹            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"