#!/bin/bash
set -euo pipefail

# VM 내부 K8s 운영 패키지 수동 복구 스크립트
# 사용법: ./fix-vm-packages.sh [OPTIONS]
# 
# 이 스크립트는 airgapped 환경에서 생성된 VM 내부에서 실행하여
# K8s 운영 패키지 설치 문제를 수동으로 복구합니다.

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

# Parse command line arguments
FORCE=false
VERBOSE=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --skip-backup|-s)
            SKIP_BACKUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force, -f        강제로 복구 실행 (확인 없이)"
            echo "  --verbose, -v      상세한 출력"
            echo "  --skip-backup, -s  백업 생성을 건너뜀"
            echo "  --help, -h         이 도움말 표시"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# 점검할 패키지 목록 (템플릿과 동일)
PACKAGES=(
    "jq"
    "htop"
    "ethtool"
    "iproute2"
    "dnsutils"
    "telnet"
    "psmisc"
    "sysstat"
)

# 선택적 패키지 목록
OPTIONAL_PACKAGES=(
    "iftop"
    "iotop"
    "dstat"
    "yq"
)

# 복구 시작
log_info "=== VM 내부 K8s 운영 패키지 수동 복구 시작 ==="
log_info "복구 시간: $(date)"
log_info "호스트명: $(hostname)"

# 1. 사전 점검
pre_check() {
    log_info "1. 사전 점검 중..."
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 루트 권한이 필요합니다"
        echo "sudo $0 $*"
        exit 1
    fi
    
    # 시스템 상태 확인
    echo "=== 시스템 상태 확인 ==="
    echo "호스트명: $(hostname)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    echo "커널: $(uname -r)"
    echo "현재 시간: $(date)"
    echo
    
    # 디스크 공간 확인
    local available_space=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $available_space -lt 1 ]]; then
        log_warning "디스크 공간이 부족합니다 (${available_space}GB)"
        if [[ "$FORCE" != "true" ]]; then
            echo "계속하시겠습니까? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_info "복구가 취소되었습니다"
                exit 0
            fi
        fi
    else
        log_success "디스크 공간 충분함 (${available_space}GB)"
    fi
    
    echo
}

# 2. 백업 생성
create_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log_info "2. 백업 생성을 건너뜁니다"
        return 0
    fi
    
    log_info "2. 백업 생성 중..."
    
    local backup_dir="/tmp/vm-packages-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    echo "=== 백업 생성 ==="
    
    # 현재 설치된 패키지 목록 백업
    dpkg -l | grep -E "(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)" > "$backup_dir/installed-packages.txt" 2>/dev/null || true
    
    # 시스템 로그 백업
    if [[ -f "/var/log/k8s-ops-packages.log" ]]; then
        cp "/var/log/k8s-ops-packages.log" "$backup_dir/"
    fi
    
    # cloud-init 로그 백업
    if [[ -f "/var/log/cloud-init.log" ]]; then
        cp "/var/log/cloud-init.log" "$backup_dir/"
    fi
    
    # 시스템 서비스 상태 백업
    systemctl status k8s-ops-packages.service > "$backup_dir/k8s-ops-packages-service-status.txt" 2>/dev/null || true
    
    log_success "백업이 생성되었습니다: $backup_dir"
    echo
}

# 3. 기존 설치 상태 확인
check_current_status() {
    log_info "3. 현재 설치 상태 확인 중..."
    
    echo "=== 현재 설치 상태 ==="
    
    local missing_packages=()
    local installed_count=0
    
    for package in "${PACKAGES[@]}"; do
        if command -v "$package" >/dev/null 2>&1; then
            echo "✓ $package: 이미 설치됨"
            installed_count=$((installed_count + 1))
        else
            echo "✗ $package: 설치되지 않음"
            missing_packages+=("$package")
        fi
    done
    
    echo
    echo "설치된 패키지: $installed_count/${#PACKAGES[@]}"
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_success "모든 필수 패키지가 이미 설치되어 있습니다"
        echo "복구가 필요하지 않습니다"
        exit 0
    else
        echo "설치되지 않은 패키지: ${missing_packages[*]}"
        log_info "복구가 필요합니다"
    fi
    
    echo
}

# 4. Seed 파일 및 설치 스크립트 확인
verify_installation_files() {
    log_info "4. 설치 파일 확인 중..."
    
    echo "=== 설치 파일 확인 ==="
    
    # Seed 디렉토리 확인
    if [[ ! -d "/usr/local/seed" ]]; then
        log_error "Seed 디렉토리가 없습니다"
        echo "해결방안: ISO 재생성이 필요합니다"
        exit 1
    fi
    
    # Packages 디렉토리 확인
    if [[ ! -d "/usr/local/seed/packages" ]]; then
        log_error "Packages 디렉토리가 없습니다"
        echo "해결방안: ISO 재생성이 필요합니다"
        exit 1
    fi
    
    # 압축 패키지 파일 확인
    if [[ ! -f "/usr/local/seed/packages/k8s-ops-packages.tar.gz" ]]; then
        log_error "압축 패키지 파일이 없습니다"
        echo "해결방안: ISO 재생성이 필요합니다"
        exit 1
    fi
    
    # 설치 스크립트 확인
    if [[ ! -f "/usr/local/seed/packages/install-packages.sh" ]]; then
        log_error "설치 스크립트가 없습니다"
        echo "해결방안: ISO 재생성이 필요합니다"
        exit 1
    fi
    
    # 설치 스크립트 실행 권한 확인 및 수정
    if [[ ! -x "/usr/local/seed/packages/install-packages.sh" ]]; then
        log_warning "설치 스크립트가 실행 불가능합니다. 권한을 수정합니다..."
        chmod +x "/usr/local/seed/packages/install-packages.sh"
        log_success "설치 스크립트 실행 권한 수정 완료"
    fi
    
    log_success "모든 설치 파일이 확인되었습니다"
    echo
}

# 5. 기존 설치 정리
cleanup_existing_installation() {
    log_info "5. 기존 설치 정리 중..."
    
    echo "=== 기존 설치 정리 ==="
    
    # 기존 설치 마커 파일 제거
    if [[ -f "/var/lib/k8s-ops-packages-installed" ]]; then
        rm -f "/var/lib/k8s-ops-packages-installed"
        log_info "기존 설치 마커 파일 제거됨"
    fi
    
    # 기존 설치 로그 백업
    if [[ -f "/var/log/k8s-ops-packages.log" ]]; then
        mv "/var/log/k8s-ops-packages.log" "/var/log/k8s-ops-packages.log.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "기존 설치 로그 백업됨"
    fi
    
    # packages 디렉토리 정리
    cd /usr/local/seed/packages
    if [[ -f "k8s-ops-packages.tar.gz" ]]; then
        # 기존 압축 해제된 파일들 정리
        rm -f *.deb 2>/dev/null || true
        log_info "기존 deb 파일들 정리됨"
    fi
    
    log_success "기존 설치 정리 완료"
    echo
}

# 6. 패키지 설치 실행
install_packages() {
    log_info "6. 패키지 설치 실행 중..."
    
    echo "=== 패키지 설치 실행 ==="
    
    cd /usr/local/seed/packages
    
    # 설치 스크립트 실행
    log_info "설치 스크립트 실행 중..."
    if ./install-packages.sh; then
        log_success "패키지 설치 스크립트 실행 완료"
    else
        log_error "패키지 설치 스크립트 실행 실패"
        
        # 수동 설치 시도
        log_info "수동 설치를 시도합니다..."
        
        # 압축 해제
        if [[ -f "k8s-ops-packages.tar.gz" ]]; then
            tar -xzf "k8s-ops-packages.tar.gz"
            log_info "압축 해제 완료"
        fi
        
        # 개별 패키지 설치
        for deb_file in *.deb; do
            if [[ -f "$deb_file" ]]; then
                log_info "설치 중: $deb_file"
                dpkg -i "$deb_file" || log_warning "설치 실패: $deb_file"
            fi
        done
        
        # 의존성 문제 해결
        log_info "의존성 문제 해결 중..."
        apt-get install -f -y || log_warning "의존성 해결 실패"
    fi
    
    echo
}

# 7. 설치 결과 확인
verify_installation() {
    log_info "7. 설치 결과 확인 중..."
    
    echo "=== 설치 결과 확인 ==="
    
    local success_count=0
    local failed_packages=()
    
    for package in "${PACKAGES[@]}"; do
        if command -v "$package" >/dev/null 2>&1; then
            echo "✓ $package: 설치 성공"
            success_count=$((success_count + 1))
        else
            echo "✗ $package: 설치 실패"
            failed_packages+=("$package")
        fi
    done
    
    echo
    echo "설치 성공: $success_count/${#PACKAGES[@]}"
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        echo "설치 실패: ${failed_packages[*]}"
        log_warning "일부 패키지 설치에 실패했습니다"
    else
        log_success "모든 필수 패키지가 성공적으로 설치되었습니다"
    fi
    
    # 설치 완료 마커 파일 생성
    echo "$(date): 수동 복구로 k8s 운영 패키지 설치 완료" > /var/lib/k8s-ops-packages-installed
    log_success "설치 완료 마커 파일 생성됨"
    
    echo
}

# 8. 시스템 서비스 상태 확인 및 복구
fix_system_services() {
    log_info "8. 시스템 서비스 상태 확인 및 복구 중..."
    
    echo "=== 시스템 서비스 상태 ==="
    
    # k8s-ops-packages 서비스 상태 확인
    if systemctl list-unit-files | grep -q "k8s-ops-packages.service"; then
        local service_status=$(systemctl is-active k8s-ops-packages.service 2>/dev/null || echo "inactive")
        echo "k8s-ops-packages 서비스: $service_status"
        
        if [[ "$service_status" != "active" ]]; then
            log_info "서비스를 활성화합니다..."
            systemctl enable k8s-ops-packages.service
            systemctl start k8s-ops-packages.service || log_warning "서비스 시작 실패"
        fi
    else
        log_warning "k8s-ops-packages 서비스가 등록되지 않았습니다"
    fi
    
    # 관련 서비스들 상태 확인
    for service in ssh k3s k3s-agent; do
        if systemctl list-unit-files | grep -q "$service.service"; then
            local status=$(systemctl is-active "$service.service" 2>/dev/null || echo "inactive")
            echo "$service 서비스: $status"
        else
            echo "$service 서비스: 등록되지 않음"
        fi
    done
    
    echo
}

# 9. 네트워크 및 시스템 설정 확인
check_system_config() {
    log_info "9. 시스템 설정 확인 중..."
    
    echo "=== 시스템 설정 확인 ==="
    
    # APT 소스 설정 확인
    echo "APT 소스 상태:"
    if grep -q "^deb http" /etc/apt/sources.list; then
        echo "  네트워크 소스 활성화됨 (airgap 환경에 부적절)"
        log_warning "네트워크 APT 소스가 활성화되어 있습니다"
    else
        echo "  네트워크 소스 비활성화됨 (airgap 환경에 적절)"
        log_success "네트워크 APT 소스가 비활성화되어 있습니다"
    fi
    
    # dpkg 상태 확인
    if dpkg --audit 2>/dev/null | grep -q .; then
        echo "dpkg 감사 결과 (문제 발견):"
        dpkg --audit | sed 's/^/  /'
        log_warning "dpkg에 문제가 있습니다"
    else
        echo "dpkg 상태: 정상"
        log_success "dpkg 상태가 정상입니다"
    fi
    
    echo
}

# 10. 최종 점검 및 보고서 생성
final_verification() {
    log_info "10. 최종 점검 및 보고서 생성 중..."
    
    echo "=== 최종 점검 결과 ==="
    
    local total_packages=${#PACKAGES[@]}
    local installed_packages=0
    local missing_packages=()
    
    for package in "${PACKAGES[@]}"; do
        if command -v "$package" >/dev/null 2>&1; then
            installed_packages=$((installed_packages + 1))
        else
            missing_packages+=("$package")
        fi
    done
    
    echo "총 패키지: $total_packages"
    echo "설치된 패키지: $installed_packages"
    echo "설치 실패 패키지: $(($total_packages - $installed_packages))"
    echo "설치 성공률: $(( ($installed_packages * 100) / $total_packages ))%"
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        echo "설치되지 않은 패키지: ${missing_packages[*]}"
        echo "상태: ⚠️  부분적 성공"
    else
        echo "상태: ✅ 완전 성공"
    fi
    
    # 상세 보고서 생성
    local report_file="/tmp/vm-packages-fix-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "VM 내부 K8s 운영 패키지 수동 복구 보고서"
        echo "복구 시간: $(date)"
        echo "호스트명: $(hostname)"
        echo "=========================================="
        echo
        echo "복구 결과:"
        echo "  총 패키지: $total_packages"
        echo "  설치된 패키지: $installed_packages"
        echo "  설치 실패 패키지: $(($total_packages - $installed_packages))"
        echo "  성공률: $(( ($installed_packages * 100) / $total_packages ))%"
        echo
        if [[ ${#missing_packages[@]} -gt 0 ]]; then
            echo "설치되지 않은 패키지:"
            for pkg in "${missing_packages[@]}"; do
                echo "  - $pkg"
            done
            echo
        fi
        echo "설치된 패키지 목록:"
        dpkg -l | grep -E "(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)" | sed 's/^/  /' || echo "  설치된 패키지 없음"
        echo
        echo "시스템 로그:"
        echo "  패키지 설치 로그: /var/log/k8s-ops-packages.log"
        echo "  시스템 로그: journalctl -u k8s-ops-packages.service"
    } > "$report_file"
    
    log_success "복구 보고서가 생성되었습니다: $report_file"
    echo
}

# 메인 실행 함수
main() {
    pre_check
    create_backup
    check_current_status
    verify_installation_files
    cleanup_existing_installation
    install_packages
    verify_installation
    fix_system_services
    check_system_config
    final_verification
    
    log_info "=== VM 내부 K8s 운영 패키지 수동 복구 완료 ==="
    
    # 종료 코드 결정
    local missing_count=0
    for package in "${PACKAGES[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            missing_count=$((missing_count + 1))
        fi
    done
    
    if [[ $missing_count -gt 0 ]]; then
        log_warning "일부 패키지 설치에 실패했습니다 ($missing_count개)"
        exit 1
    else
        log_success "모든 패키지가 성공적으로 설치되었습니다"
        exit 0
    fi
}

# 스크립트 실행
main "$@"
