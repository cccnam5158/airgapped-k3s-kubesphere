#!/bin/bash

# Seed ISO 진단 스크립트
# 사용법: ./diagnose_iso.sh

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$REPORT_FILE"
}

# 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/out"
REPORT_FILE="$OUTPUT_DIR/iso_diagnostic_report.txt"

# 진단 결과 파일 초기화
echo "=== Seed ISO 진단 보고서 ===" > "$REPORT_FILE"
echo "생성 시간: $(date)" >> "$REPORT_FILE"
echo "=======================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 1. 기본 파일 존재 확인
check_basic_files() {
    log_info "1. 기본 파일 존재 확인"
    echo "" >> "$REPORT_FILE"
    
    cd "$OUTPUT_DIR"
    
    # ISO 파일들 확인
    for iso in seed-master1.iso seed-worker1.iso seed-worker2.iso ubuntu-22.04.5-live-server-amd64.iso; do
        if [[ -f "$iso" ]]; then
            local size=$(ls -lh "$iso" | awk '{print $5}')
            log_success "$iso 존재 (크기: $size)"
            ls -la "$iso" >> "$REPORT_FILE"
        else
            log_error "$iso 파일이 없습니다"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
}

# 2. ISO 내부 구조 확인
check_iso_structure() {
    log_info "2. Seed ISO 내부 구조 확인"
    echo "" >> "$REPORT_FILE"
    
    cd "$OUTPUT_DIR"
    
    for iso in seed-master1.iso seed-worker1.iso seed-worker2.iso; do
        if [[ -f "$iso" ]]; then
            log_info "$iso 내부 구조 분석 중..."
            echo "=== $iso 내부 구조 ===" >> "$REPORT_FILE"
            
            # 전체 파일 목록
            echo "--- 전체 파일 목록 ---" >> "$REPORT_FILE"
            isoinfo -R -l -i "$iso" >> "$REPORT_FILE" 2>&1 || echo "isoinfo 실행 실패" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            # cloud-init 관련 파일 검색
            echo "--- Cloud-init 관련 파일 ---" >> "$REPORT_FILE"
            isoinfo -R -l -i "$iso" | grep -E "(user-data|meta-data|USER-DATA|META-DATA|cidata)" >> "$REPORT_FILE" 2>&1 || echo "cloud-init 파일을 찾을 수 없습니다" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
        fi
    done
}

# 3. Cloud-init 파일 내용 확인
check_cloudinit_content() {
    log_info "3. Cloud-init 파일 내용 확인"
    echo "" >> "$REPORT_FILE"
    
    cd "$OUTPUT_DIR"
    
    for iso in seed-master1.iso seed-worker1.iso seed-worker2.iso; do
        if [[ -f "$iso" ]]; then
            log_info "$iso의 cloud-init 파일 내용 추출 중..."
            echo "=== $iso Cloud-init 내용 ===" >> "$REPORT_FILE"
            
            # user-data 추출 시도 (여러 경로)
            echo "--- user-data 내용 ---" >> "$REPORT_FILE"
            local found_userdata=false
            
            for path in "/user-data" "/USER-DATA" "/cidata/user-data" "/cloud-init/user-data"; do
                if isoinfo -R -x "$path" -i "$iso" > temp_userdata.txt 2>/dev/null; then
                    echo "user-data 파일 위치: $path" >> "$REPORT_FILE"
                    echo "내용 (첫 50줄):" >> "$REPORT_FILE"
                    head -50 temp_userdata.txt >> "$REPORT_FILE"
                    found_userdata=true
                    rm -f temp_userdata.txt
                    break
                fi
            done
            
            if [[ "$found_userdata" == "false" ]]; then
                echo "user-data 파일을 찾을 수 없습니다" >> "$REPORT_FILE"
            fi
            
            # meta-data 추출 시도
            echo "--- meta-data 내용 ---" >> "$REPORT_FILE"
            local found_metadata=false
            
            for path in "/meta-data" "/META-DATA" "/cidata/meta-data" "/cloud-init/meta-data"; do
                if isoinfo -R -x "$path" -i "$iso" > temp_metadata.txt 2>/dev/null; then
                    echo "meta-data 파일 위치: $path" >> "$REPORT_FILE"
                    echo "내용:" >> "$REPORT_FILE"
                    cat temp_metadata.txt >> "$REPORT_FILE"
                    found_metadata=true
                    rm -f temp_metadata.txt
                    break
                fi
            done
            
            if [[ "$found_metadata" == "false" ]]; then
                echo "meta-data 파일을 찾을 수 없습니다" >> "$REPORT_FILE"
            fi
            
            echo "" >> "$REPORT_FILE"
        fi
    done
}

# 4. ISO 부팅 정보 확인
check_boot_info() {
    log_info "4. ISO 부팅 정보 확인"
    echo "" >> "$REPORT_FILE"
    
    cd "$OUTPUT_DIR"
    
    for iso in seed-master1.iso ubuntu-22.04.5-live-server-amd64.iso; do
        if [[ -f "$iso" ]]; then
            log_info "$iso 부팅 정보 분석 중..."
            echo "=== $iso 부팅 정보 ===" >> "$REPORT_FILE"
            
            # ISO 정보
            echo "--- ISO 기본 정보 ---" >> "$REPORT_FILE"
            isoinfo -d -i "$iso" >> "$REPORT_FILE" 2>&1 || echo "ISO 정보 읽기 실패" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            # 부팅 관련 파일
            echo "--- 부팅 관련 파일 ---" >> "$REPORT_FILE"
            isoinfo -R -l -i "$iso" | grep -E "(boot|Boot|BOOT|grub|isolinux)" >> "$REPORT_FILE" 2>&1 || echo "부팅 파일을 찾을 수 없습니다" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    done
}

# 5. GRUB 설정 확인
check_grub_config() {
    log_info "5. GRUB 설정 확인"
    echo "" >> "$REPORT_FILE"
    
    cd "$OUTPUT_DIR"
    
    for iso in seed-master1.iso ubuntu-22.04.5-live-server-amd64.iso; do
        if [[ -f "$iso" ]]; then
            log_info "$iso의 GRUB 설정 확인 중..."
            echo "=== $iso GRUB 설정 ===" >> "$REPORT_FILE"
            
            # grub.cfg 파일 찾기 및 추출
            echo "--- GRUB 설정 파일 ---" >> "$REPORT_FILE"
            local grub_paths=("/boot/grub/grub.cfg" "/isolinux/grub.cfg" "/grub/grub.cfg")
            
            for path in "${grub_paths[@]}"; do
                if isoinfo -R -x "$path" -i "$iso" > temp_grub.cfg 2>/dev/null; then
                    echo "GRUB 설정 파일 위치: $path" >> "$REPORT_FILE"
                    echo "내용 (첫 100줄):" >> "$REPORT_FILE"
                    head -100 temp_grub.cfg >> "$REPORT_FILE"
                    rm -f temp_grub.cfg
                    break
                fi
            done
            
            echo "" >> "$REPORT_FILE"
        fi
    done
}

# 6. 환경 및 도구 확인
check_environment() {
    log_info "6. 환경 및 도구 확인"
    echo "" >> "$REPORT_FILE"
    
    echo "=== 환경 정보 ===" >> "$REPORT_FILE"
    
    # 시스템 정보
    echo "--- 시스템 정보 ---" >> "$REPORT_FILE"
    uname -a >> "$REPORT_FILE"
    echo "WSL 버전: $(grep Microsoft /proc/version 2>/dev/null || echo "Not WSL")" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 필요한 도구들 확인
    echo "--- 설치된 도구 확인 ---" >> "$REPORT_FILE"
    local tools=("isoinfo" "genisoimage" "xorriso" "mount" "umount")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo "$tool: $(which "$tool") ($(${tool} --version 2>&1 | head -1 || echo "버전 정보 없음"))" >> "$REPORT_FILE"
        else
            echo "$tool: 설치되지 않음" >> "$REPORT_FILE"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
}

# 7. 템플릿 파일 확인
check_templates() {
    log_info "7. 템플릿 파일 확인"
    echo "" >> "$REPORT_FILE"
    
    echo "=== 템플릿 파일 ===" >> "$REPORT_FILE"
    
    local template_dir="$PROJECT_ROOT/templates"
    
    for tpl in user-data-master.tpl user-data-worker.tpl; do
        local tpl_path="$template_dir/$tpl"
        if [[ -f "$tpl_path" ]]; then
            echo "--- $tpl 내용 (첫 30줄) ---" >> "$REPORT_FILE"
            head -30 "$tpl_path" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        else
            echo "$tpl 파일이 없습니다: $tpl_path" >> "$REPORT_FILE"
        fi
    done
}

# 8. 스크립트 환경변수 확인
check_script_variables() {
    log_info "8. 스크립트 환경변수 확인"
    echo "" >> "$REPORT_FILE"
    
    echo "=== 환경변수 ===" >> "$REPORT_FILE"
    
    # 01_build_seed_isos.sh에서 사용하는 주요 변수들
    local vars=("REGISTRY_HOST_IP" "REGISTRY_PORT" "POD_CIDR" "SVC_CIDR" "MASTER_IP" "WORKER1_IP" "WORKER2_IP")
    
    for var in "${vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            echo "$var=${!var}" >> "$REPORT_FILE"
        else
            echo "$var=설정되지 않음" >> "$REPORT_FILE"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
    
    # SSH 키 확인
    echo "--- SSH 키 ---" >> "$REPORT_FILE"
    if [[ -f "$OUTPUT_DIR/ssh/id_rsa.pub" ]]; then
        echo "SSH 공개키 존재: $OUTPUT_DIR/ssh/id_rsa.pub" >> "$REPORT_FILE"
        echo "내용: $(cat "$OUTPUT_DIR/ssh/id_rsa.pub")" >> "$REPORT_FILE"
    else
        echo "SSH 공개키가 없습니다" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
}

# 메인 실행
main() {
    log_info "=== Seed ISO 진단 시작 ==="
    
    # 출력 디렉토리로 이동
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_error "출력 디렉토리가 없습니다: $OUTPUT_DIR"
        exit 1
    fi
    
    # 진단 실행
    check_basic_files
    check_iso_structure
    check_cloudinit_content
    check_boot_info
    check_grub_config
    check_environment
    check_templates
    check_script_variables
    
    # 보고서 완료
    echo "=======================================" >> "$REPORT_FILE"
    echo "진단 완료 시간: $(date)" >> "$REPORT_FILE"
    
    log_success "=== 진단 완료 ==="
    log_success "보고서 위치: $REPORT_FILE"
    log_info "보고서 보기: cat $REPORT_FILE"
    log_info "보고서 크기: $(du -h "$REPORT_FILE" | cut -f1)"
    
    # 요약 정보 출력
    echo ""
    log_info "=== 요약 정보 ==="
    
    # ISO 파일 존재 여부
    cd "$OUTPUT_DIR"
    local iso_count=$(ls seed-*.iso 2>/dev/null | wc -l)
    log_info "Seed ISO 파일 개수: $iso_count/3"
    
    # Cloud-init 파일 발견 여부
    local cloudinit_found=false
    for iso in seed-master1.iso; do
        if [[ -f "$iso" ]] && isoinfo -R -l -i "$iso" | grep -q "user-data"; then
            cloudinit_found=true
            break
        fi
    done
    
    if [[ "$cloudinit_found" == "true" ]]; then
        log_success "Cloud-init 파일이 ISO에서 발견됨"
    else
        log_error "Cloud-init 파일이 ISO에서 발견되지 않음"
    fi
}

# 스크립트 실행
main "$@"