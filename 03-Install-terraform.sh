#!/bin/bash

################################################################################
# Terraform Installation Script
# Installs Terraform on Ubuntu/Debian systems
################################################################################

# Don't use set -e, we'll handle errors manually for better messages

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║           Terraform Installation Script               ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if Terraform is already installed
print_header "Checking for Existing Installation"

if command -v terraform &> /dev/null; then
    CURRENT_VERSION=$(terraform --version | head -n 1)
    print_warning "Terraform is already installed: ${CURRENT_VERSION}"
    echo ""
    read -p "Do you want to reinstall/upgrade? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Keeping existing installation"
        echo ""
        terraform --version
        echo ""
        print_success "Terraform is ready to use!"
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    Terraform Already Installed! ✓              ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        echo ""
        exit 0
    fi
fi

# Install required packages
print_header "Installing Prerequisites"

print_info "Updating package list..."
if sudo apt-get update -y; then
    print_success "Package list updated"
else
    print_error "Failed to update package list"
    print_info "Continuing anyway..."
fi

print_info "Installing required packages (gnupg, curl, software-properties-common)..."
if sudo apt-get install -y gnupg software-properties-common curl; then
    print_success "Prerequisites installed"
else
    print_error "Failed to install some prerequisites"
    print_info "Checking if we can continue..."

    # Check if essential tools exist
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed. Cannot continue."
        exit 1
    fi
    if ! command -v gpg &> /dev/null; then
        print_error "gpg is required but not installed. Cannot continue."
        exit 1
    fi
    print_info "Essential tools available, continuing..."
fi

# Add HashiCorp GPG key
print_header "Adding HashiCorp Repository"

print_info "Adding HashiCorp GPG key..."
if wget -O- https://apt.releases.hashicorp.com/gpg 2>/dev/null | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null; then
    print_success "GPG key added"
else
    print_error "Failed to add GPG key"
    print_info "Trying alternative method..."

    # Alternative method
    if curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -; then
        print_success "GPG key added (alternative method)"
    else
        print_error "Could not add HashiCorp GPG key. Cannot continue."
        exit 1
    fi
fi

# Add HashiCorp repository
print_info "Adding HashiCorp repository..."
DISTRO=$(lsb_release -cs)
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${DISTRO} main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

if [ $? -eq 0 ]; then
    print_success "Repository added for: ${DISTRO}"
else
    print_error "Failed to add repository"
    exit 1
fi

# Install Terraform
print_header "Installing Terraform"

print_info "Updating package list with new repository..."
if sudo apt-get update -y; then
    print_success "Package list updated"
else
    print_warning "Package list update had warnings (may be okay)"
fi

print_info "Installing Terraform..."
if sudo apt-get install -y terraform; then
    print_success "Terraform installed"
else
    print_error "Failed to install Terraform via apt"
    print_info "Trying alternative installation method..."

    # Alternative: Download binary directly
    print_info "Downloading Terraform binary directly..."
    TERRAFORM_VERSION="1.6.0"
    cd /tmp
    if curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; then
        print_info "Extracting..."
        unzip -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
        sudo mv terraform /usr/local/bin/
        rm -f "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
        print_success "Terraform installed via direct download"
    else
        print_error "All installation methods failed"
        exit 1
    fi
fi

# Verify installation
print_header "Verifying Installation"

if command -v terraform &> /dev/null; then
    echo -e "${GREEN}Terraform installed successfully!${NC}"
    echo ""
    terraform --version
    echo ""

    # Enable tab completion (optional, don't fail if it doesn't work)
    print_info "Enabling tab completion..."
    terraform -install-autocomplete 2>/dev/null && print_success "Tab completion enabled (restart shell to use)" || print_info "Tab completion skipped (optional)"
else
    print_error "Terraform installation verification failed!"
    print_error "terraform command not found in PATH"
    exit 1
fi

# Summary
print_header "Installation Complete"

echo -e "${GREEN}✅ Terraform is ready to use!${NC}"
echo ""
echo -e "${BLUE}Quick Commands:${NC}"
echo "  terraform --version    # Check version"
echo "  terraform init         # Initialize a project"
echo "  terraform plan         # Preview changes"
echo "  terraform apply        # Apply changes"
echo "  terraform destroy      # Destroy resources"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Navigate to terraform/ecr directory"
echo "  2. Run: terraform init"
echo "  3. Run: terraform plan"
echo "  4. Run: terraform apply"
echo ""
echo -e "${BLUE}Or simply run:${NC}"
echo "  ./03-ecr-setup.sh"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Terraform Installation Complete! 🎉         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""