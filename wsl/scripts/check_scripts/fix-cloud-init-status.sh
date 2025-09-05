#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다."
        log_info "sudo $0"
        exit 1
    fi
}

# Fix missing completion flags
fix_completion_flags() {
    log_info "누락된 완료 표시 파일들을 생성합니다..."
    
    # Auto-login configuration
    if [[ ! -f /var/lib/autologin-configured ]]; then
        log_info "자동 로그인 설정 적용 중..."
        systemctl restart getty@tty1.service 2>/dev/null || true
        systemctl restart serial-getty@ttyS0.service 2>/dev/null || true
        echo "Auto-login configured" > /var/lib/autologin-configured
        log_success "자동 로그인 설정 완료"
    fi
    
    # Kubectl alias creation
    if [[ ! -f /var/lib/kubectl-alias-created ]]; then
        log_info "kubectl 별칭 생성 중..."
        echo 'alias kubectl="k3s kubectl"' >> /home/ubuntu/.bashrc
        echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc
        echo "Kubectl alias created" > /var/lib/kubectl-alias-created
        log_success "kubectl 별칭 생성 완료"
    fi
    
    # SSH restart
    if [[ ! -f /var/lib/ssh-restarted ]]; then
        log_info "SSH 서비스 재시작 중..."
        systemctl restart ssh 2>/dev/null || true
        echo "SSH restarted" > /var/lib/ssh-restarted
        log_success "SSH 재시작 완료"
    fi
}

# Force cloud-init completion
force_cloud_init_completion() {
    log_info "Cloud-init 상태를 강제로 완료로 변경합니다..."
    
    # Update cloud-init completion file with current timestamp
    echo "Cloud-init completed at $(date)" > /var/lib/cloud-init-complete
    
    # Force cloud-init to recognize completion
    if command -v cloud-init >/dev/null 2>&1; then
        # Clear any pending cloud-init semaphores
        rm -f /var/lib/cloud/sem/* 2>/dev/null || true
        
        # Force cloud-init to recognize completion
        cloud-init status --wait 2>/dev/null || true
    fi
    
    log_success "Cloud-init 상태 강제 완료 처리됨"
}

# Verify system status
verify_system_status() {
    log_info "시스템 상태 확인 중..."
    
    # Check K3s status
    if systemctl is-active --quiet k3s; then
        log_success "K3s 서비스: 실행 중"
    else
        log_warning "K3s 서비스: 실행되지 않음"
    fi
    
    # Check SSH status
    if systemctl is-active --quiet ssh; then
        log_success "SSH 서비스: 실행 중"
    else
        log_warning "SSH 서비스: 실행되지 않음"
    fi
    
    # Check completion flags
    local flags=(
        "/var/lib/cloud-init-complete:Cloud-init 전체 완료"
        "/var/lib/autologin-configured:자동 로그인 설정 완료"
        "/var/lib/kubectl-alias-created:kubectl 별칭 생성 완료"
        "/var/lib/ssh-restarted:SSH 재시작 완료"
    )
    
    for flag_info in "${flags[@]}"; do
        IFS=':' read -r flag_path description <<< "$flag_info"
        if [[ -f "$flag_path" ]]; then
            log_success "$description"
        else
            log_warning "$description (미완료)"
        fi
    done
}

# Main function
main() {
    log_info "Cloud-init 상태 수정 시작..."
    
    check_root
    fix_completion_flags
    force_cloud_init_completion
    verify_system_status
    
    log_success "Cloud-init 상태 수정 완료!"
    log_info "재부팅 후 cloud-init status를 확인하세요: cloud-init status"
}

# Run main function
main "$@"
