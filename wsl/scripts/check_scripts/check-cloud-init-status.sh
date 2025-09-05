#!/bin/bash
set -euo pipefail

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

# Check cloud-init status
check_cloud_init_status() {
    log_info "=== Cloud-init 상태 확인 ==="
    
    if command -v cloud-init >/dev/null 2>&1; then
        echo "Cloud-init 버전: $(cloud-init --version)"
        echo ""
        
        echo "Cloud-init 상태:"
        cloud-init status --long
        echo ""
        
        echo "Cloud-init 로그 (최근 20줄):"
        if [ -f /var/log/cloud-init.log ]; then
            tail -n 20 /var/log/cloud-init.log
        else
            log_warning "Cloud-init 로그 파일이 없습니다"
        fi
        echo ""
    else
        log_error "Cloud-init가 설치되지 않았습니다"
    fi
}

# Check completion flag files
check_completion_flags() {
    log_info "=== 완료 표시 파일 확인 ==="
    
    local flags=(
        "/var/lib/iso-copy-complete:ISO 파일 복사 완료"
        "/var/lib/cloud-init-complete:Cloud-init 전체 완료"
        "/var/lib/timezone-set:타임존 설정 완료"
        "/var/lib/sync-time-enabled:시간 동기화 완료"
        "/var/lib/ca-certificates-updated:CA 인증서 업데이트 완료"
        "/var/lib/swap-disabled:스왑 비활성화 완료"
        "/var/lib/sysctl-applied:sysctl 설정 완료"
        "/var/lib/hostname-set:호스트명 설정 완료"
        "/var/lib/kernel-modules-loaded:커널 모듈 로드 완료"
        "/var/lib/k3s-bootstrap.done:K3s 마스터 부트스트랩 완료"
        "/var/lib/k3s-agent-bootstrap.done:K3s 워커 부트스트랩 완료"
        "/var/lib/autologin-configured:자동 로그인 설정 완료"
        "/var/lib/kubectl-alias-created:kubectl 별칭 생성 완료"
        "/var/lib/ssh-restarted:SSH 재시작 완료"
    )
    
    for flag_info in "${flags[@]}"; do
        IFS=':' read -r flag_path description <<< "$flag_info"
        if [ -f "$flag_path" ]; then
            echo -e "${GREEN}✓${NC} $description"
            echo "  파일: $flag_path"
            echo "  내용: $(cat "$flag_path")"
        else
            echo -e "${RED}✗${NC} $description (미완료)"
            echo "  파일: $flag_path (존재하지 않음)"
        fi
        echo ""
    done
}

# Check k3s status
check_k3s_status() {
    log_info "=== K3s 상태 확인 ==="
    
    # Check if k3s binary exists
    if [ -f /usr/local/bin/k3s ]; then
        echo "K3s 바이너리: 존재함"
        echo "K3s 버전: $(/usr/local/bin/k3s --version 2>/dev/null || echo '버전 확인 실패')"
        echo ""
        
        # Check k3s service status
        if systemctl is-active --quiet k3s 2>/dev/null; then
            log_success "K3s 서비스: 실행 중"
            systemctl status k3s --no-pager -l
        elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
            log_success "K3s Agent 서비스: 실행 중"
            systemctl status k3s-agent --no-pager -l
        else
            log_warning "K3s 서비스: 실행되지 않음"
        fi
        echo ""
        
        # Check bootstrap logs
        if [ -f /var/log/k3s-bootstrap.log ]; then
            echo "K3s 부트스트랩 로그 (최근 10줄):"
            tail -n 10 /var/log/k3s-bootstrap.log
        elif [ -f /var/log/k3s-agent-bootstrap.log ]; then
            echo "K3s Agent 부트스트랩 로그 (최근 10줄):"
            tail -n 10 /var/log/k3s-agent-bootstrap.log
        fi
        echo ""
        
        # Check if kubectl works
        if /usr/local/bin/k3s kubectl get nodes >/dev/null 2>&1; then
            log_success "K3s 클러스터: 정상 동작"
            echo "노드 목록:"
            /usr/local/bin/k3s kubectl get nodes -o wide
        else
            log_warning "K3s 클러스터: 응답 없음"
        fi
    else
        log_error "K3s 바이너리가 설치되지 않았습니다"
    fi
}

# Check system time
check_system_time() {
    log_info "=== 시스템 시간 확인 ==="
    
    echo "현재 시간: $(date)"
    echo "UTC 시간: $(date -u)"
    echo "타임존: $(timedatectl show --property=Timezone --value 2>/dev/null || echo '확인 불가')"
    echo "NTP 상태: $(timedatectl show --property=NTP --value 2>/dev/null || echo '확인 불가')"
    echo ""
}

# Main function
main() {
    log_info "Cloud-init 상태 진단 시작..."
    echo ""
    
    check_cloud_init_status
    check_completion_flags
    check_k3s_status
    check_system_time
    
    log_info "진단 완료"
    echo ""
    log_info "문제 해결 방법:"
    echo "1. Cloud-init가 반복 실행되는 경우: sudo touch /var/lib/cloud-init-complete"
    echo "2. K3s 부트스트랩이 실패한 경우: sudo tail -f /var/log/k3s-bootstrap.log"
    echo "3. 시간 동기화 문제: sudo systemctl restart sync-time.service"
    echo "4. 전체 재설치가 필요한 경우: 모든 /var/lib/* 파일 삭제 후 재부팅"
}

# Run main function
main "$@"
