#!/usr/bin/env bash
set -euo pipefail

# Environment variables with defaults
MASTER_IP="${MASTER_IP:-192.168.6.10}"
WORKER1_IP="${WORKER1_IP:-192.168.6.11}"
WORKER2_IP="${WORKER2_IP:-192.168.6.12}"
SSH_KEY="${SSH_KEY:-$(cd "$(dirname "$0")"/.. && pwd)/out/ssh/id_rsa}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check SSH key
check_ssh_key() {
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH private key not found at $SSH_KEY"
        log_error "Please run 00_prep_offline.sh first or set SSH_KEY env var"
        exit 1
    fi

    # If key is on Windows filesystem (/mnt/*), copy to ~/.ssh with secure perms
    if [[ "$SSH_KEY" == /mnt/* ]]; then
        log_info "Detected key on Windows mount. Copying to ~/.ssh with secure permissions..."
        local dest="$HOME/.ssh/airgap_k3s"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        install -m 600 "$SSH_KEY" "$dest"
        SSH_KEY="$dest"
        export SSH_KEY
        log_success "SSH key copied to $SSH_KEY"
    else
        chmod 600 "$SSH_KEY"
        log_success "SSH key configured: $SSH_KEY"
    fi
}

# Wait for SSH to be available
wait_for_ssh() {
    local ip="$1"
    local hostname="$2"
    local max_attempts=60
    local attempt=1
    
    log_info "Waiting for SSH on $hostname ($ip)..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if timeout 5 ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$ip" "echo 'SSH connection successful'" 2>/dev/null; then
            log_success "SSH connection established to $hostname ($ip)"
            return 0
        else
            echo -n "."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "Failed to establish SSH connection to $hostname ($ip) after $max_attempts attempts"
    return 1
}

# Check k3s/bootstrapping status with multiple fallbacks (service, process, port)
check_k3s_service() {
    local ip="$1"
    local hostname="$2"
    
    log_info "Checking k3s status on $hostname..."
    
    # Remote composite check:
    # 0: running (service/process/port)
    # 2: bootstrap failed
    # 1: not up yet
    if ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$ip" "bash -c '
        # service active?
        if systemctl is-active --quiet k3s 2>/dev/null; then exit 0; fi
        # process up?
        if pgrep -x k3s >/dev/null 2>&1; then exit 0; fi
        # master: API port
        if ss -lntp 2>/dev/null | grep -q 6443; then exit 0; fi
        # bootstrap units failed?
        if systemctl is-failed --quiet k3s-bootstrap 2>/dev/null || systemctl is-failed --quiet k3s-agent-bootstrap 2>/dev/null; then exit 2; fi
        exit 1
    '"; then
        log_success "k3s appears to be running on $hostname"
        return 0
    else
        local rc=$?
        if [[ $rc -eq 2 ]]; then
            log_error "Bootstrap service failed on $hostname (check: systemctl status k3s-bootstrap|k3s-agent-bootstrap)"
        else
            log_warning "k3s not up yet on $hostname"
        fi
        return 1
    fi
}

# Check cluster status
check_cluster_status() {
    log_info "Checking cluster status on master ($MASTER_IP)..."
    
    local attempts=30
    local delay=10
    local kubectl_cmd=""
    
    for ((i=1;i<=attempts;i++)); do
        # Try different kubectl commands each attempt
        for cmd in "kubectl" "/usr/local/bin/k3s kubectl" "sudo kubectl" "sudo /usr/local/bin/k3s kubectl"; do
            if ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "$cmd get nodes -o wide" 2>/dev/null; then
                kubectl_cmd="$cmd"
                break
            fi
        done
        if [[ -n "$kubectl_cmd" ]]; then
            break
        fi
        echo -n "."
        sleep "$delay"
    done
    
    if [[ -z "$kubectl_cmd" ]]; then
        log_error "Failed to find working kubectl command on master after $((attempts*delay))s"
        return 1
    fi
    
    log_success "Using kubectl command: $kubectl_cmd"
    
    # Check nodes
    log_info "Cluster nodes:"
    ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "$kubectl_cmd get nodes -o wide"
    
    # Check pods
    log_info "System pods:"
    ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "$kubectl_cmd get pods -A"
    
    # Check cluster info
    log_info "Cluster info:"
    ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "$kubectl_cmd cluster-info"
    
    return 0
}

# Install KubeSphere (optional)
install_kubesphere() {
    local response
    log_info "KubeSphere installation is available. Would you like to install it? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Installing KubeSphere..."
        
        # Download KubeSphere installer
        ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "
            curl -fL -o kubesphere-installer.yaml https://github.com/kubesphere/ks-installer/releases/download/v4.1.3/kubesphere-installer.yaml
            curl -fL -o cluster-configuration.yaml https://github.com/kubesphere/ks-installer/releases/download/v4.1.3/cluster-configuration.yaml
        "
        
        # Apply KubeSphere installer
        ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$MASTER_IP" "
            kubectl apply -f kubesphere-installer.yaml
            kubectl apply -f cluster-configuration.yaml
        "
        
        log_success "KubeSphere installation started. Check status with: kubectl get pod -n kubesphere-system"
        log_info "Access KubeSphere console at: http://$MASTER_IP:30880 (default: admin/P@88w0rd)"
    else
        log_info "Skipping KubeSphere installation"
    fi
}

# Main execution
main() {
    log_info "Starting cluster verification process..."
    
    # Check SSH key
    check_ssh_key
    
    # Wait for all nodes to be SSH accessible
    local nodes=(
        "$MASTER_IP:master1"
        "$WORKER1_IP:worker1"
        "$WORKER2_IP:worker2"
    )
    
    for node in "${nodes[@]}"; do
        IFS=':' read -r ip hostname <<< "$node"
        if ! wait_for_ssh "$ip" "$hostname"; then
            log_error "Failed to connect to $hostname"
            exit 1
        fi
    done
    
    # Check k3s service on all nodes
    for node in "${nodes[@]}"; do
        IFS=':' read -r ip hostname <<< "$node"
        if ! check_k3s_service "$ip" "$hostname"; then
            log_warning "k3s service check failed on $hostname, but continuing..."
        fi
    done
    
    # Check cluster status
    if ! check_cluster_status; then
        log_error "Cluster status check failed"
        exit 1
    fi
    
    log_success "Cluster verification completed successfully!"
    
    # Offer KubeSphere installation
    install_kubesphere
    
    log_info "Cluster is ready for use!"
    log_info "SSH to master: ssh -i $SSH_KEY $SSH_USER@$MASTER_IP"
    log_info "SSH to worker1: ssh -i $SSH_KEY $SSH_USER@$WORKER1_IP"
    log_info "SSH to worker2: ssh -i $SSH_KEY $SSH_USER@$WORKER2_IP"
}

# Run main function
main "$@"
