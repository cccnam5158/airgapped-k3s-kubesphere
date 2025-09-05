#!/bin/bash
set -euo pipefail

# VM 내부 K8s 운영 패키지 설치 상태 점검 스크립트
# 사용법: ./check-vm-packages.sh [OPTIONS]
# 
# 이 스크립트는 airgapped 환경에서 생성된 VM 내부에서 실행하여
# K8s 운영에 필요한 패키지들이 제대로 설치되었는지 확인합니다.

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
VERBOSE=false
AUTO_FIX=false
GENERATE_REPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --auto-fix|-f)
            AUTO_FIX=true
            shift
            ;;
        --report|-r)
            GENERATE_REPORT=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --verbose, -v    상세한 출력"
            echo "  --auto-fix, -f   자동으로 문제 수정 시도"
            echo "  --report, -r     상세 보고서 생성"
            echo "  --help, -h       이 도움말 표시"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# 결과 저장용 변수들
TOTAL_PACKAGES=0
INSTALLED_PACKAGES=0
MISSING_PACKAGES=()
FAILED_CHECKS=()
WARNINGS=()

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

# 점검 시작
log_info "=== VM 내부 K8s 운영 패키지 설치 상태 점검 시작 ==="
log_info "점검 시간: $(date)"
log_info "호스트명: $(hostname)"
log_info "OS 정보: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"

# 1. 시스템 기본 정보 점검
check_system_info() {
    log_info "1. 시스템 기본 정보 점검 중..."
    
    echo "=== 시스템 정보 ==="
    echo "호스트명: $(hostname)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    echo "커널: $(uname -r)"
    echo "아키텍처: $(uname -m)"
    echo "메모리: $(free -h | grep Mem | awk '{print $2}')"
    echo "디스크: $(df -h / | tail -1 | awk '{print $4}') 사용 가능"
    echo "현재 시간: $(date)"
    echo "타임존: $(timedatectl show --property=Timezone --value 2>/dev/null || echo 'Unknown')"
    echo
}

# 2. cloud-init 실행 상태 점검
check_cloud_init_status() {
    log_info "2. cloud-init 실행 상태 점검 중..."
    
    local cloud_init_log="/var/log/cloud-init.log"
    local cloud_init_output="/var/log/cloud-init-output.log"
    
    echo "=== cloud-init 상태 ==="
    
    # cloud-init 서비스 상태
    if systemctl is-active cloud-init >/dev/null 2>&1; then
        echo "cloud-init 서비스: $(systemctl is-active cloud-init)"
        log_success "cloud-init 서비스가 활성 상태입니다"
    else
        echo "cloud-init 서비스: 비활성"
        log_warning "cloud-init 서비스가 비활성 상태입니다"
        WARNINGS+=("cloud-init 서비스 비활성")
    fi
    
    # cloud-init 로그 파일 확인
    if [[ -f "$cloud_init_log" ]]; then
        echo "cloud-init 로그: 존재함 ($(stat -c%s "$cloud_init_log") bytes)"
        if $VERBOSE; then
            echo "최근 cloud-init 로그 (마지막 10줄):"
            tail -10 "$cloud_init_log" | sed 's/^/  /'
        fi
    else
        echo "cloud-init 로그: 없음"
        log_warning "cloud-init 로그 파일이 없습니다"
        WARNINGS+=("cloud-init 로그 파일 없음")
    fi
    
    # cloud-init 출력 로그 확인
    if [[ -f "$cloud_init_output" ]]; then
        echo "cloud-init 출력 로그: 존재함 ($(stat -c%s "$cloud_init_output") bytes)"
        if $VERBOSE; then
            echo "최근 cloud-init 출력 (마지막 10줄):"
            tail -10 "$cloud_init_output" | sed 's/^/  /'
        fi
    else
        echo "cloud-init 출력 로그: 없음"
        log_warning "cloud-init 출력 로그 파일이 없습니다"
        WARNINGS+=("cloud-init 출력 로그 없음")
    fi
    
    # cloud-init 완료 마커 파일 확인
    if [[ -f "/var/lib/cloud-init-complete" ]]; then
        echo "cloud-init 완료 마커: 존재함"
        log_success "cloud-init가 완료되었습니다"
    else
        echo "cloud-init 완료 마커: 없음"
        log_warning "cloud-init 완료 마커 파일이 없습니다"
        WARNINGS+=("cloud-init 완료 마커 없음")
    fi
    
    echo
}

# 3. K8s 운영 패키지 설치 서비스 상태 점검
check_k8s_ops_service() {
    log_info "3. K8s 운영 패키지 설치 서비스 상태 점검 중..."
    
    echo "=== K8s 운영 패키지 서비스 상태 ==="
    
    # k8s-ops-packages 서비스 상태
    if systemctl list-unit-files | grep -q "k8s-ops-packages.service"; then
        local service_status=$(systemctl is-active k8s-ops-packages.service 2>/dev/null || echo "inactive")
        echo "k8s-ops-packages 서비스: $service_status"
        
        if [[ "$service_status" == "active" ]]; then
            log_success "k8s-ops-packages 서비스가 활성 상태입니다"
        else
            log_warning "k8s-ops-packages 서비스가 비활성 상태입니다"
            WARNINGS+=("k8s-ops-packages 서비스 비활성")
            
            if $VERBOSE; then
                echo "서비스 상태 상세:"
                systemctl status k8s-ops-packages.service --no-pager -l || true
            fi
        fi
    else
        echo "k8s-ops-packages 서비스: 등록되지 않음"
        log_error "k8s-ops-packages 서비스가 등록되지 않았습니다"
        FAILED_CHECKS+=("k8s-ops-packages 서비스 미등록")
    fi
    
    # 설치 완료 마커 파일 확인
    if [[ -f "/var/lib/k8s-ops-packages-installed" ]]; then
        echo "패키지 설치 완료 마커: 존재함"
        echo "설치 완료 시간: $(cat /var/lib/k8s-ops-packages-installed)"
        log_success "K8s 운영 패키지 설치가 완료되었습니다"
    else
        echo "패키지 설치 완료 마커: 없음"
        log_warning "K8s 운영 패키지 설치 완료 마커가 없습니다"
        WARNINGS+=("패키지 설치 완료 마커 없음")
    fi
    
    # 설치 로그 확인
    if [[ -f "/var/log/k8s-ops-packages.log" ]]; then
        echo "패키지 설치 로그: 존재함 ($(stat -c%s "/var/log/k8s-ops-packages.log") bytes)"
        if $VERBOSE; then
            echo "패키지 설치 로그 내용:"
            cat "/var/log/k8s-ops-packages.log" | sed 's/^/  /'
        fi
    else
        echo "패키지 설치 로그: 없음"
        log_warning "패키지 설치 로그 파일이 없습니다"
        WARNINGS+=("패키지 설치 로그 없음")
    fi
    
    echo
}

# 4. Seed 파일 및 패키지 디렉토리 점검
check_seed_files() {
    log_info "4. Seed 파일 및 패키지 디렉토리 점검 중..."
    
    echo "=== Seed 파일 상태 ==="
    
    # /usr/local/seed 디렉토리 확인
    if [[ -d "/usr/local/seed" ]]; then
        echo "Seed 디렉토리: 존재함"
        echo "Seed 디렉토리 내용:"
        ls -la /usr/local/seed/ | sed 's/^/  /'
        
        # packages 디렉토리 확인
        if [[ -d "/usr/local/seed/packages" ]]; then
            echo "Packages 디렉토리: 존재함"
            echo "Packages 디렉토리 내용:"
            ls -la /usr/local/seed/packages/ | sed 's/^/  /'
            
            # tar.gz 파일 확인
            if [[ -f "/usr/local/seed/packages/k8s-ops-packages.tar.gz" ]]; then
                local archive_size=$(stat -c%s "/usr/local/seed/packages/k8s-ops-packages.tar.gz")
                echo "압축 패키지 파일: 존재함 ($(numfmt --to=iec $archive_size))"
                log_success "압축 패키지 파일이 존재합니다"
            else
                echo "압축 패키지 파일: 없음"
                log_error "압축 패키지 파일이 없습니다"
                FAILED_CHECKS+=("압축 패키지 파일 없음")
            fi
            
            # 설치 스크립트 확인
            if [[ -f "/usr/local/seed/packages/install-packages.sh" ]]; then
                echo "설치 스크립트: 존재함"
                if [[ -x "/usr/local/seed/packages/install-packages.sh" ]]; then
                    log_success "설치 스크립트가 실행 가능합니다"
                else
                    log_warning "설치 스크립트가 실행 불가능합니다"
                    WARNINGS+=("설치 스크립트 실행 권한 없음")
                fi
            else
                echo "설치 스크립트: 없음"
                log_error "설치 스크립트가 없습니다"
                FAILED_CHECKS+=("설치 스크립트 없음")
            fi
        else
            echo "Packages 디렉토리: 없음"
            log_error "Packages 디렉토리가 없습니다"
            FAILED_CHECKS+=("Packages 디렉토리 없음")
        fi
    else
        echo "Seed 디렉토리: 없음"
        log_error "Seed 디렉토리가 없습니다"
        FAILED_CHECKS+=("Seed 디렉토리 없음")
    fi
    
    # CD-ROM 마운트 확인
    echo "CD-ROM 마운트 상태:"
    if mount | grep -q "/dev/sr"; then
        mount | grep "/dev/sr" | sed 's/^/  /'
        log_info "CD-ROM이 마운트되어 있습니다"
    else
        echo "  CD-ROM이 마운트되어 있지 않습니다"
        log_info "CD-ROM이 마운트되어 있지 않습니다 (정상적인 상황)"
    fi
    
    echo
}

# 5. 개별 패키지 설치 상태 점검
check_individual_packages() {
    log_info "5. 개별 패키지 설치 상태 점검 중..."
    
    echo "=== 필수 패키지 설치 상태 ==="
    
    for package in "${PACKAGES[@]}"; do
        TOTAL_PACKAGES=$((TOTAL_PACKAGES + 1))
        
        if command -v "$package" >/dev/null 2>&1; then
            local version
            case "$package" in
                "jq")
                    version=$(jq --version 2>/dev/null || echo "unknown")
                    ;;
                "htop")
                    version=$(htop --version 2>/dev/null | head -1 || echo "unknown")
                    ;;
                "ethtool")
                    version=$(ethtool --version 2>/dev/null || echo "unknown")
                    ;;
                "iproute2")
                    version=$(ip --version 2>/dev/null || echo "unknown")
                    ;;
                "dnsutils")
                    version=$(dig -v 2>/dev/null | head -1 || echo "unknown")
                    ;;
                "telnet")
                    version=$(telnet --help 2>/dev/null | head -1 || echo "unknown")
                    ;;
                "psmisc")
                    version=$(fuser --version 2>/dev/null || echo "unknown")
                    ;;
                "sysstat")
                    version=$(iostat -V 2>/dev/null | head -1 || echo "unknown")
                    ;;
                *)
                    version="unknown"
                    ;;
            esac
            echo "✓ $package: 설치됨 ($version)"
            INSTALLED_PACKAGES=$((INSTALLED_PACKAGES + 1))
        else
            echo "✗ $package: 설치되지 않음"
            MISSING_PACKAGES+=("$package")
        fi
    done
    
    echo
    echo "=== 선택적 패키지 설치 상태 ==="
    
    for package in "${OPTIONAL_PACKAGES[@]}"; do
        if command -v "$package" >/dev/null 2>&1; then
            echo "✓ $package: 설치됨"
        else
            echo "- $package: 설치되지 않음 (선택적)"
        fi
    done
    
    echo
}

# 6. dpkg 상태 점검
check_dpkg_status() {
    log_info "6. dpkg 상태 점검 중..."
    
    echo "=== dpkg 상태 ==="
    
    # dpkg 상태 확인
    if dpkg --audit 2>/dev/null | grep -q .; then
        echo "dpkg 감사 결과 (문제 발견):"
        dpkg --audit | sed 's/^/  /'
        log_warning "dpkg에 문제가 있습니다"
        WARNINGS+=("dpkg 문제 발견")
    else
        echo "dpkg 상태: 정상"
        log_success "dpkg 상태가 정상입니다"
    fi
    
    # 설치된 패키지 목록에서 K8s 운영 패키지 검색
    echo "설치된 K8s 운영 패키지 목록:"
    dpkg -l | grep -E "(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)" | sed 's/^/  /' || echo "  설치된 패키지 없음"
    
    echo
}

# 7. 네트워크 및 시스템 설정 점검
check_system_config() {
    log_info "7. 시스템 설정 점검 중..."
    
    echo "=== 시스템 설정 ==="
    
    # 네트워크 설정 확인
    echo "네트워크 인터페이스:"
    ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
    
    # DNS 설정 확인
    echo "DNS 설정:"
    cat /etc/resolv.conf | sed 's/^/  /'
    
    # APT 소스 설정 확인
    echo "APT 소스 상태:"
    if grep -q "^deb http" /etc/apt/sources.list; then
        echo "  네트워크 소스 활성화됨 (airgap 환경에 부적절)"
        log_warning "네트워크 APT 소스가 활성화되어 있습니다"
        WARNINGS+=("네트워크 APT 소스 활성화")
    else
        echo "  네트워크 소스 비활성화됨 (airgap 환경에 적절)"
        log_success "네트워크 APT 소스가 비활성화되어 있습니다"
    fi
    
    # 시스템 서비스 상태 확인
    echo "관련 시스템 서비스 상태:"
    for service in ssh k3s k3s-agent; do
        if systemctl list-unit-files | grep -q "$service.service"; then
            local status=$(systemctl is-active "$service.service" 2>/dev/null || echo "inactive")
            echo "  $service: $status"
        else
            echo "  $service: 등록되지 않음"
        fi
    done
    
    echo
}

# 8. 문제 진단 및 해결 방안 제시
diagnose_issues() {
    log_info "8. 문제 진단 및 해결 방안 분석 중..."
    
    echo "=== 문제 진단 ==="
    
    if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
        echo "설치되지 않은 패키지들: ${MISSING_PACKAGES[*]}"
        
        # 가능한 원인 분석
        echo "가능한 원인:"
        
        if [[ ! -f "/var/lib/k8s-ops-packages-installed" ]]; then
            echo "  1. K8s 운영 패키지 설치 서비스가 실행되지 않았습니다"
            echo "     해결방안: sudo systemctl start k8s-ops-packages.service"
        fi
        
        if [[ ! -f "/usr/local/seed/packages/k8s-ops-packages.tar.gz" ]]; then
            echo "  2. 압축 패키지 파일이 없습니다"
            echo "     해결방안: ISO 재생성 또는 수동 패키지 설치"
        fi
        
        if [[ ! -x "/usr/local/seed/packages/install-packages.sh" ]]; then
            echo "  3. 설치 스크립트가 실행 불가능합니다"
            echo "     해결방안: chmod +x /usr/local/seed/packages/install-packages.sh"
        fi
        
        if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
            echo "  4. 시스템 구성 문제:"
            for check in "${FAILED_CHECKS[@]}"; do
                echo "     - $check"
            done
        fi
    else
        echo "모든 필수 패키지가 설치되어 있습니다"
    fi
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo "경고사항:"
        for warning in "${WARNINGS[@]}"; do
            echo "  - $warning"
        done
    fi
    
    echo
}

# 9. 자동 수정 시도 (--auto-fix 옵션)
attempt_auto_fix() {
    if [[ "$AUTO_FIX" == "true" ]]; then
        log_info "9. 자동 수정 시도 중..."
        
        echo "=== 자동 수정 시도 ==="
        
        # 1. 설치 스크립트 실행 권한 수정
        if [[ -f "/usr/local/seed/packages/install-packages.sh" ]] && [[ ! -x "/usr/local/seed/packages/install-packages.sh" ]]; then
            echo "설치 스크립트 실행 권한 수정 중..."
            chmod +x "/usr/local/seed/packages/install-packages.sh"
            log_success "설치 스크립트 실행 권한 수정 완료"
        fi
        
        # 2. K8s 운영 패키지 서비스 재시작
        if systemctl list-unit-files | grep -q "k8s-ops-packages.service"; then
            echo "K8s 운영 패키지 서비스 재시작 중..."
            systemctl restart k8s-ops-packages.service || true
            log_info "K8s 운영 패키지 서비스 재시작 완료"
        fi
        
        # 3. 수동으로 패키지 설치 시도
        if [[ -f "/usr/local/seed/packages/install-packages.sh" ]] && [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
            echo "수동 패키지 설치 시도 중..."
            cd /usr/local/seed/packages
            ./install-packages.sh || log_warning "수동 설치 실패"
        fi
        
        echo "자동 수정 완료. 다시 점검을 실행하세요."
        echo
    fi
}

# 10. 결과 요약 및 보고서 생성
generate_summary() {
    log_info "10. 결과 요약 생성 중..."
    
    echo "=== 점검 결과 요약 ==="
    echo "총 점검 패키지: $TOTAL_PACKAGES"
    echo "설치된 패키지: $INSTALLED_PACKAGES"
    echo "설치 실패 패키지: $(($TOTAL_PACKAGES - $INSTALLED_PACKAGES))"
    echo "설치 성공률: $(( ($INSTALLED_PACKAGES * 100) / $TOTAL_PACKAGES ))%"
    
    if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
        echo "설치되지 않은 패키지: ${MISSING_PACKAGES[*]}"
        echo "상태: ❌ 문제 발견"
    else
        echo "상태: ✅ 모든 패키지 설치됨"
    fi
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo "경고사항 수: ${#WARNINGS[@]}"
    fi
    
    if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
        echo "실패한 점검 수: ${#FAILED_CHECKS[@]}"
    fi
    
    echo
    
    # 상세 보고서 생성 (--report 옵션)
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        local report_file="/tmp/vm-packages-report-$(date +%Y%m%d-%H%M%S).txt"
        
        {
            echo "VM 내부 K8s 운영 패키지 설치 상태 점검 보고서"
            echo "생성 시간: $(date)"
            echo "호스트명: $(hostname)"
            echo "=========================================="
            echo
            echo "시스템 정보:"
            echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
            echo "  커널: $(uname -r)"
            echo "  아키텍처: $(uname -m)"
            echo
            echo "패키지 설치 상태:"
            echo "  총 패키지: $TOTAL_PACKAGES"
            echo "  설치됨: $INSTALLED_PACKAGES"
            echo "  설치 실패: $(($TOTAL_PACKAGES - $INSTALLED_PACKAGES))"
            echo "  성공률: $(( ($INSTALLED_PACKAGES * 100) / $TOTAL_PACKAGES ))%"
            echo
            if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
                echo "설치되지 않은 패키지:"
                for pkg in "${MISSING_PACKAGES[@]}"; do
                    echo "  - $pkg"
                done
                echo
            fi
            if [[ ${#WARNINGS[@]} -gt 0 ]]; then
                echo "경고사항:"
                for warning in "${WARNINGS[@]}"; do
                    echo "  - $warning"
                done
                echo
            fi
            if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
                echo "실패한 점검:"
                for check in "${FAILED_CHECKS[@]}"; do
                    echo "  - $check"
                done
                echo
            fi
            echo "상세 로그:"
            echo "  cloud-init 로그: /var/log/cloud-init.log"
            echo "  패키지 설치 로그: /var/log/k8s-ops-packages.log"
            echo "  시스템 로그: journalctl -u k8s-ops-packages.service"
        } > "$report_file"
        
        log_success "상세 보고서가 생성되었습니다: $report_file"
        echo "보고서 내용 미리보기:"
        head -20 "$report_file" | sed 's/^/  /'
        echo "  ... (전체 내용은 $report_file 파일을 확인하세요)"
        echo
    fi
}

# 메인 실행 함수
main() {
    check_system_info
    check_cloud_init_status
    check_k8s_ops_service
    check_seed_files
    check_individual_packages
    check_dpkg_status
    check_system_config
    diagnose_issues
    attempt_auto_fix
    generate_summary
    
    log_info "=== VM 내부 K8s 운영 패키지 설치 상태 점검 완료 ==="
    
    # 종료 코드 결정
    if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]] || [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
        log_error "점검에서 문제가 발견되었습니다"
        exit 1
    else
        log_success "모든 점검이 통과되었습니다"
        exit 0
    fi
}

# 스크립트 실행
main "$@"
