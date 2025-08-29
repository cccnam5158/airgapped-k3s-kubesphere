#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 22.04.5 LTS Server ISO 기반 Seed ISO 생성 스크립트
# 사용법: ./01_build_seed_isos.sh [OPTIONS]

# Parse command line arguments
CLEANUP_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
    --cleanup-only)
    CLEANUP_ONLY=true
    shift
    ;;
    --help|-h)
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --cleanup-only    Only clean up existing resources without building ISOs"
    echo "  --help, -h    Show this help message"
    exit 0
    ;;
    *)
    echo "Unknown option: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
    esac
done

# 기본 경로 설정 (WSL 감지 전)
OUT_DIR="$(cd "$(dirname "$0")"/.. && pwd)/out"
TPL_DIR="$(cd "$(dirname "$0")"/../templates && pwd)"
WORK_DIR="$OUT_DIR/ubuntu-seed-work"

# Environment variables with defaults
REGISTRY_HOST_IP="${REGISTRY_HOST_IP:-192.168.6.1}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
POD_CIDR="${POD_CIDR:-10.42.0.0/16}"
SVC_CIDR="${SVC_CIDR:-10.43.0.0/16}"
MASTER_IP="${MASTER_IP:-192.168.6.10}"
WORKER1_IP="${WORKER1_IP:-192.168.6.11}"
WORKER2_IP="${WORKER2_IP:-192.168.6.12}"
GATEWAY_IP="${GATEWAY_IP:-192.168.6.1}"
DNS_IP="${DNS_IP:-192.168.6.1}"

# Ubuntu ISO 정보
UBUNTU_ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
UBUNTU_ISO_NAME="ubuntu-22.04.5-live-server-amd64.iso"
UBUNTU_ISO_SHA256="9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
UBUNTU_ISO_SIZE="2,129,362,680"  # bytes (약 2.1GB)

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

# WSL 환경 감지 및 작업 디렉토리 변경 (로그 함수 정의 후)
setup_wsl_environment() {
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ "$(pwd)" == /mnt/* ]]; then
    log_info "WSL 환경이 감지되었습니다. 작업 디렉토리를 WSL 내부로 이동합니다..."
    
    # 원본 Windows 경로들 저장
    ORIGINAL_OUT_DIR="$OUT_DIR"
    ORIGINAL_TPL_DIR="$TPL_DIR"
    
    # WSL 내부 경로로 변경
    WSL_WORK_BASE="$HOME/airgapped-k3s-build"
    mkdir -p "$WSL_WORK_BASE"
    
    OUT_DIR="$WSL_WORK_BASE/out"
    WORK_DIR="$WSL_WORK_BASE/ubuntu-seed-work"
    TPL_DIR="$WSL_WORK_BASE/templates"
    
    # 필요한 파일들을 WSL로 복사
    mkdir -p "$OUT_DIR" "$TPL_DIR"
    
    if [[ -d "$ORIGINAL_OUT_DIR" ]]; then
    cp -r "$ORIGINAL_OUT_DIR"/* "$OUT_DIR/" 2>/dev/null || true
    log_success "기존 출력 파일들을 WSL로 복사했습니다"
    fi
    
    if [[ -d "$ORIGINAL_TPL_DIR" ]]; then
    cp -r "$ORIGINAL_TPL_DIR"/* "$TPL_DIR/" 2>/dev/null || true
    log_success "템플릿 파일들을 WSL로 복사했습니다"
    fi
    
    # 결과를 Windows로 복사하는 함수 정의
    copy_back_to_windows() {
    if [[ -n "${ORIGINAL_OUT_DIR:-}" ]]; then
    log_info "생성된 ISO 파일들을 Windows로 복사합니다..."
    mkdir -p "$ORIGINAL_OUT_DIR"
    
    for iso_file in "$OUT_DIR"/*.iso; do
    if [[ -f "$iso_file" ]]; then
    cp "$iso_file" "$ORIGINAL_OUT_DIR/"
    log_success "$(basename "$iso_file")을 Windows로 복사했습니다"
    fi
    done
    fi
    }
    
    # 스크립트 종료 시 자동으로 복사하도록 trap 설정
    trap copy_back_to_windows EXIT
    
    log_info "WSL 작업 디렉토리: $OUT_DIR"
    export WSL_MODE=true
    else
    export WSL_MODE=false
    fi
}

# Cleanup function to remove existing resources
cleanup_existing_resources() {
    log_info "Cleaning up existing resources..."
    
    # Remove existing ISO files
    local iso_files=(
    "$OUT_DIR/seed-master1.iso"
    "$OUT_DIR/seed-worker1.iso"
    "$OUT_DIR/seed-worker2.iso"
    )
    
    for iso_file in "${iso_files[@]}"; do
    if [[ -f "$iso_file" ]]; then
    rm -f "$iso_file"
    log_info "Removed existing ISO: $(basename "$iso_file")"
    fi
    done
    
    # Remove existing user-data files
    local user_data_files=(
    "$OUT_DIR/user-data-master1"
    "$OUT_DIR/user-data-worker1"
    "$OUT_DIR/user-data-worker2"
    )
    
    for user_data_file in "${user_data_files[@]}"; do
    if [[ -f "$user_data_file" ]]; then
    rm -f "$user_data_file"
    log_info "Removed existing user-data: $(basename "$user_data_file")"
    fi
    done
    
    # Remove existing meta-data files
    local meta_data_files=(
    "$OUT_DIR/meta-data-master1"
    "$OUT_DIR/meta-data-worker1"
    "$OUT_DIR/meta-data-worker2"
    )
    
    for meta_data_file in "${meta_data_files[@]}"; do
    if [[ -f "$meta_data_file" ]]; then
    rm -f "$meta_data_file"
    log_info "Removed existing meta-data: $(basename "$meta_data_file")"
    fi
    done
    
    # Remove common directory if it exists
    if [[ -d "$OUT_DIR/common" ]]; then
    rm -rf "$OUT_DIR/common"
    log_info "Removed existing common directory"
    fi
    
    # Remove Ubuntu work directory if it exists
    if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    log_info "Removed existing Ubuntu work directory"
    fi
    
    log_success "Cleanup completed"
}

# 필수 도구 확인
check_prerequisites() {
    log_info "필수 도구들을 확인합니다..."
    
    local required_tools=("xorriso" "rsync" "wget" "sha256sum" "genisoimage")
    
    for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
    log_error "$tool 명령어가 없습니다. 설치해주세요"
    log_info "Ubuntu/Debian: sudo apt-get install xorriso isolinux rsync wget genisoimage"
    exit 1
    fi
    done
    
    # isolinux 패키지 확인 (명령어가 아닌 패키지)
    if ! dpkg -l isolinux 2>/dev/null | grep -q "^ii"; then
    log_error "isolinux 패키지가 설치되지 않았습니다. 설치해주세요"
    log_info "Ubuntu/Debian: sudo apt-get install isolinux"
    exit 1
    fi
    
    # Check if required files exist
    local required_files=(
    "$OUT_DIR/k3s"
    "$OUT_DIR/registries.yaml"
    "$TPL_DIR/user-data-master.tpl"
    "$TPL_DIR/user-data-worker.tpl"
    )
    
    for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
    log_error "Required file not found: $file"
    log_error "Please run 00_prep_offline_fixed.sh first"
    exit 1
    fi
    done
    
    # Check if SSH key exists
    if [[ ! -f "$OUT_DIR/ssh/id_rsa.pub" ]]; then
    log_error "SSH public key not found. Please run 00_prep_offline_fixed.sh first"
    exit 1
    fi
    
    log_success "필수 도구 확인 완료"
}

# Ubuntu ISO 다운로드
download_ubuntu_iso() {
    log_info "Ubuntu 22.04.5 LTS Server ISO 다운로드 상태를 확인합니다..."
    
    local iso_path="$OUT_DIR/$UBUNTU_ISO_NAME"
    
    if [[ -f "$iso_path" ]]; then
    log_info "기존 ISO 파일이 발견되었습니다: $(basename "$iso_path")"
    
    # 파일 크기 확인
    local file_size=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)
    local file_size_mb=$((file_size / 1024 / 1024))
    
    log_info "파일 크기: ${file_size_mb}MB (예상: 약 2.1GB)"
    
    # 크기가 너무 작으면 손상된 것으로 간주
    if [[ $file_size -lt 20000 ]]; then  # 2GB 미만
    log_warning "파일 크기가 너무 작습니다. 손상된 것으로 간주하고 재다운로드합니다..."
    rm -f "$iso_path"
    else
    log_info "파일 크기가 정상입니다. SHA256 무결성을 확인합니다..."
    
    # SHA256 검증
    local current_sha256=$(sha256sum "$iso_path" | cut -d' ' -f1)
    if [[ "$current_sha256" == "$UBUNTU_ISO_SHA256" ]]; then
    log_success "기존 ISO 파일이 유효합니다. 재다운로드를 건너뜁니다."
    return 0
    else
    log_warning "SHA256 체크섬이 일치하지 않습니다. 파일이 손상되었습니다."
    log_info "예상 SHA256: $UBUNTU_ISO_SHA256"
    log_info "실제 SHA256: $current_sha256"
    log_warning "재다운로드를 시작합니다..."
    rm -f "$iso_path"
    fi
    fi
    else
    log_info "기존 ISO 파일이 없습니다. 새로 다운로드합니다."
    fi
    
    log_info "Ubuntu 22.04.5 LTS Server ISO 다운로드를 시작합니다..."
    log_info "다운로드 URL: $UBUNTU_ISO_URL"
    log_info "예상 파일 크기: 약 2.1GB"
    log_info "다운로드 중... (진행률이 표시됩니다)"
    
    # wget으로 다운로드 (진행률 표시 포함)
    if wget --progress=bar:force:noscroll -O "$iso_path" "$UBUNTU_ISO_URL"; then
    log_success "Ubuntu ISO 다운로드 완료"
    else
    log_error "Ubuntu ISO 다운로드 실패"
    if [[ -f "$iso_path" ]]; then
    rm -f "$iso_path"
    fi
    exit 1
    fi
    
    # 다운로드된 파일 크기 확인
    local downloaded_size=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)
    local downloaded_size_mb=$((downloaded_size / 1024 / 1024))
    log_info "다운로드된 파일 크기: ${downloaded_size_mb}MB"
    
    # SHA256 검증
    log_info "ISO 파일 무결성을 확인합니다..."
    local downloaded_sha256=$(sha256sum "$iso_path" | cut -d' ' -f1)
    if [[ "$downloaded_sha256" == "$UBUNTU_ISO_SHA256" ]]; then
    log_success "ISO 파일 무결성 확인 완료"
    log_success "SHA256 체크섬: $downloaded_sha256"
    else
    log_error "ISO 파일이 손상되었습니다. 다운로드를 다시 시도해주세요"
    log_error "예상 SHA256: $UBUNTU_ISO_SHA256"
    log_error "실제 SHA256: $downloaded_sha256"
    rm -f "$iso_path"
    exit 1
    fi
}

# 작업 디렉토리 정리
cleanup_work_dir() {
    log_info "작업 디렉토리를 정리합니다..."
    
    if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    log_info "기존 작업 디렉토리 삭제됨"
    fi
    
    mkdir -p "$WORK_DIR"
    log_success "작업 디렉토리 생성됨"
}

# Ubuntu ISO 마운트 및 복사 (개선된 버전)
extract_ubuntu_iso() {
    log_info "Ubuntu ISO를 추출합니다..."
    
    local iso_path="$OUT_DIR/$UBUNTU_ISO_NAME"
    local mount_point="$WORK_DIR/mount"
    
    mkdir -p "$mount_point"
    
    # ISO 마운트
    log_info "ISO를 마운트합니다..."
    if sudo mount -o loop "$iso_path" "$mount_point"; then
    log_success "ISO 마운트 완료"
    else
    log_error "ISO 마운트 실패"
    exit 1
    fi
    
    # 부팅 파일 확인 - Ubuntu 22.04.5의 실제 구조에 맞게 수정
    log_info "부팅 파일 구조를 확인합니다..."
    
    # BIOS 부팅 이미지 확인
    log_info "BIOS 부팅 관련 파일들을 검색합니다..."
    if [[ -f "$mount_point/boot/grub/i386-pc/eltorito.img" ]]; then
    export HAS_BIOS_BOOT=true
    export BIOS_BOOT_IMG="boot/grub/i386-pc/eltorito.img"
    log_success "BIOS 부팅 이미지 발견됨: $BIOS_BOOT_IMG"
    else
    export HAS_BIOS_BOOT=false
    log_warning "BIOS 부팅 이미지를 찾을 수 없습니다"
    fi
    
    # EFI 부팅 파일 확인 (여러 경로 체크)
    log_info "UEFI 부팅 파일들을 검색합니다..."
    
    # Ubuntu 22.04.5에서는 EFI 부팅 파일들이 EFI/boot/ 디렉토리에 있음
    export HAS_UEFI=false
    export EFI_IMG_PATH=""
    
    # 실제 EFI 부팅 파일들 확인
    if [[ -f "$mount_point/EFI/boot/bootx64.efi" ]]; then
    export HAS_UEFI=true
    export EFI_BOOT_PATH="EFI/boot/bootx64.efi"
    log_success "UEFI 부팅 파일 발견됨: $EFI_BOOT_PATH"
    fi
    
    # GRUB EFI 이미지 확인 (있다면)
    if [[ -f "$mount_point/boot/grub/efi.img" ]]; then
    export EFI_IMG_PATH="boot/grub/efi.img"
    log_success "GRUB EFI 이미지 발견됨: $EFI_IMG_PATH"
    elif [[ -f "$mount_point/boot/grub/x86_64-efi/core.efi" ]]; then
    export EFI_IMG_PATH="boot/grub/x86_64-efi/core.efi"
    log_success "GRUB EFI 코어 발견됨: $EFI_IMG_PATH"
    fi
    
    if [[ "$HAS_UEFI" == "false" ]]; then
    log_warning "UEFI 부팅 파일을 찾을 수 없습니다"
    fi
    
    # boot.catalog 파일 확인
    if [[ -f "$mount_point/boot.catalog" ]]; then
    log_success "boot.catalog 파일 발견됨"
    export HAS_BOOT_CATALOG=true
    else
    log_warning "boot.catalog 파일이 없습니다"
    export HAS_BOOT_CATALOG=false
    fi
    
    # 부팅 관련 파일들 상세 확인
    log_info "부팅 관련 파일들 상세 확인:"
    find "$mount_point" -name "*.img" -type f 2>/dev/null | head -10
    find "$mount_point" -name "eltorito.img" -type f 2>/dev/null
    find "$mount_point" -name "*.efi" -type f 2>/dev/null | head -5
    
    # 부팅 디렉토리 구조 출력
    log_info "부팅 관련 디렉토리 구조:"
    if [[ -d "$mount_point/boot" ]]; then
    find "$mount_point/boot" -maxdepth 3 -type f -name "*.img" -o -name "*.efi" 2>/dev/null
    fi
    if [[ -d "$mount_point/EFI" ]]; then
    find "$mount_point/EFI" -type f 2>/dev/null
    fi
    
    # 전체 부팅 호환성 상태 요약
    log_info "부팅 호환성 요약:"
    if [[ "$HAS_BIOS_BOOT" == "true" ]]; then
    log_success "✓ BIOS/Legacy 부팅 지원됨"
    else
    log_warning "✗ BIOS/Legacy 부팅 지원되지 않음"
    fi
    
    if [[ "$HAS_UEFI" == "true" ]]; then
    log_success "✓ UEFI 부팅 지원됨"
    else
    log_warning "✗ UEFI 부팅 지원되지 않음"
    fi
    
    if [[ "$HAS_BIOS_BOOT" == "false" && "$HAS_UEFI" == "false" ]]; then
    log_error "부팅 가능한 구성을 찾을 수 없습니다!"
    sudo umount "$mount_point"
    exit 1
    fi
    
    # ISO 내용 복사
    log_info "ISO 내용을 복사합니다..."
    if rsync -av "$mount_point/" "$WORK_DIR/extracted/"; then
    log_success "ISO 내용 복사 완료"
    
    # 복사된 파일들의 권한을 수정 (읽기 전용 해제)
    log_info "복사된 파일들의 권한을 수정합니다..."
    find "$WORK_DIR/extracted" -type d -exec chmod 755 {} \;
    find "$WORK_DIR/extracted" -type f -exec chmod 644 {} \;
    log_success "파일 권한 수정 완료"
    else
    log_error "ISO 내용 복사 실패"
    sudo umount "$mount_point"
    exit 1
    fi
    
    # 마운트 해제
    sudo umount "$mount_point"
    rmdir "$mount_point"
    log_success "ISO 마운트 해제 완료"
}

# Load SSH public key and CA certificate
load_credentials() {
    log_info "Loading SSH public key and CA certificate..."
    
    if [[ -f "$OUT_DIR/ssh/id_rsa.pub" ]]; then
    export SSH_PUBLIC_KEY=$(cat "$OUT_DIR/ssh/id_rsa.pub")
    log_success "SSH public key loaded"
    else
    log_error "SSH public key not found at $OUT_DIR/ssh/id_rsa.pub"
    exit 1
    fi
    
    # Check for CA certificate (try multiple possible names)
    local ca_cert_file=""
    for cert_file in "$OUT_DIR/certs/ca.crt" "$OUT_DIR/certs/registry.crt"; do
    if [[ -f "$cert_file" ]]; then
    ca_cert_file="$cert_file"
    break
    fi
    done
    
    if [[ -n "$ca_cert_file" ]]; then
    export CA_PEM_INLINE=$(cat "$ca_cert_file" | sed 's/^/    /')
    log_success "CA certificate loaded from $ca_cert_file"
    else
    log_error "CA certificate not found. Please run 00_prep_offline_fixed.sh first"
    exit 1
    fi
}

# 토큰 생성
generate_token() {
    log_info "K3s 토큰을 생성합니다..."
    
    if [[ ! -f "$OUT_DIR/token" ]]; then
    export TOKEN=$(openssl rand -hex 32)
    echo "$TOKEN" > "$OUT_DIR/token"
    log_success "새 토큰 생성됨"
    else
    export TOKEN=$(cat "$OUT_DIR/token")
    log_info "기존 토큰 사용됨"
    fi
}

# 비밀번호 해시 생성 (identity.password 용 SHA-512 crypt)
generate_password_hash() {
    log_info "설치 사용자 비밀번호 해시를 생성합니다..."
    # 기본 평문 비밀번호 (SSH는 키 기반만 허용하므로 설치용으로만 사용)
    local plain_password="${INSTALL_USER_PASSWORD:-ubuntu}"
    # openssl -6 (SHA-512) 사용
    if command -v openssl &> /dev/null; then
    local salt
    salt=$(openssl rand -hex 8)
    export PASSWORD_HASH=$(openssl passwd -6 -salt "$salt" "$plain_password")
    if [[ -n "$PASSWORD_HASH" ]]; then
    log_success "비밀번호 해시 생성 완료"
    else
    log_error "비밀번호 해시 생성 실패"
    exit 1
    fi
    else
    log_error "openssl 명령을 찾을 수 없습니다"
    exit 1
    fi
}

# Set environment variables for template substitution
set_template_vars() {
    log_info "Setting template environment variables..."
    
    export REGISTRY_HOST_IP
    export REGISTRY_PORT
    export POD_CIDR
    export SVC_CIDR
    export MASTER_IP
    export WORKER1_IP
    export WORKER2_IP
    export GATEWAY_IP
    export DNS_IP
    export TOKEN
    export PASSWORD_HASH
    # Helper for templates to prevent envsubst from expanding runtime shell variables
    export DOLLAR='$'
    
    log_success "Template environment variables set"
}

# cloud-init 파일 생성 (수정된 버전)
generate_cloud_init_files() {
    log_info "cloud-init 파일들을 생성합니다..."
    
    # autoinstall 디렉토리를 extracted 디렉토리 안에 생성
    local autoinstall_dir="$WORK_DIR/extracted/autoinstall"
    mkdir -p "$autoinstall_dir"
    
    # Master cloud-init 파일 생성
    log_info "Master cloud-init 파일 생성 중..."
    envsubst < "$TPL_DIR/user-data-master.tpl" > "$autoinstall_dir/user-data-master1"
    
    # Master meta-data 파일 생성
    cat > "$autoinstall_dir/meta-data-master1" << EOF
instance-id: master1
local-hostname: k3s-master1
EOF
    
    # Worker1 cloud-init 파일 생성
    log_info "Worker1 cloud-init 파일 생성 중..."
    # hostname을 worker1으로 변경
    sed 's/hostname: k3s-master1/hostname: k3s-worker1/' "$TPL_DIR/user-data-worker.tpl" | \
    sed 's/${WORKER_IP}/${WORKER1_IP}/' | \
    envsubst > "$autoinstall_dir/user-data-worker1"
    
    # Worker1 meta-data 파일 생성
    cat > "$autoinstall_dir/meta-data-worker1" << EOF
instance-id: worker1
local-hostname: k3s-worker1
EOF
    
    # Worker2 cloud-init 파일 생성
    log_info "Worker2 cloud-init 파일 생성 중..."
    # hostname을 worker2로 변경
    sed 's/hostname: k3s-worker1/hostname: k3s-worker2/' "$TPL_DIR/user-data-worker.tpl" | \
    sed 's/${WORKER_IP}/${WORKER2_IP}/' | \
    envsubst > "$autoinstall_dir/user-data-worker2"
    
    # Worker2 meta-data 파일 생성
    cat > "$autoinstall_dir/meta-data-worker2" << EOF
instance-id: worker2
local-hostname: k3s-worker2
EOF
    
    log_success "모든 cloud-init 파일들이 /autoinstall 디렉토리에 생성됨"

    # Normalize line endings to LF to avoid CRLF issues on target VMs
    if command -v sed >/dev/null 2>&1; then
    sed -i 's/\r$//' "$autoinstall_dir/user-data-master1" || true
    sed -i 's/\r$//' "$autoinstall_dir/user-data-worker1" || true
    sed -i 's/\r$//' "$autoinstall_dir/user-data-worker2" || true
    sed -i 's/\r$//' "$autoinstall_dir/meta-data-master1" || true
    sed -i 's/\r$//' "$autoinstall_dir/meta-data-worker1" || true
    sed -i 's/\r$//' "$autoinstall_dir/meta-data-worker2" || true
    log_success "cloud-init 파일 줄바꿈(LF) 정규화 완료"
    fi
}

# GRUB 설정 수정 함수 - WSL 호환 버전
modify_grub_config() {
    log_info "GRUB 설정을 autoinstall용으로 수정합니다..."
    
    local -a grub_files=(
    "$WORK_DIR/extracted/boot/grub/grub.cfg"
    "$WORK_DIR/extracted/boot/grub/loopback.cfg"
    )

    local injected=false
    for grub_cfg in "${grub_files[@]}"; do
    if [[ -f "$grub_cfg" ]]; then
    local grub_cfg_backup="$grub_cfg.backup"
    cp "$grub_cfg" "$grub_cfg_backup"
    log_info "GRUB 설정 백업 생성됨: $(basename "$grub_cfg")"

    # 모든 linux/linuxefi 엔트리에 autoinstall 파라미터 주입
    local new_content
    new_content=$(awk '
    BEGIN { OFS="" }
    /^[[:space:]]*linux(efi)?[[:space:]]+\/casper\/vmlinuz/ {
    line=$0
    # 기존 autoinstall 잔재 제거
    gsub(/[[:space:]]+autoinstall[^-]* /, " ", line)
    gsub(/[[:space:]]+autoinstall[^-]*$/, "", line)
    # GRUB에서 ; 는 명령 구분자이므로 반드시 이스케이프 필요
    # locale/keyboard 커널 파라미터를 함께 주입하여 초기 언어 선택 프롬프트를 차단
    param=" autoinstall ds=nocloud\\;s=/cdrom/autoinstall/ locale=en_US.UTF-8 keyboard-configuration/layoutcode=us console-setup/ask_detect=false console=ttyS0,115200 console=tty0"
    pos=index(line, " ---")
    if (pos > 0) {
    before=substr(line, 1, pos-1)
    after=substr(line, pos)
    print before, param, after; next
    }
    print line, param; next
    }
    { print $0 }
    ' "$grub_cfg")

    if echo "$new_content" > "$grub_cfg"; then
    log_success "GRUB 설정 수정 완료: $(basename "$grub_cfg")"
    injected=true
    log_info "수정된 부팅 라인들 ($(basename "$grub_cfg")):"
    grep -n "linux .*autoinstall" "$grub_cfg" | head -3 || true
    else
    log_error "GRUB 설정 수정 실패: $(basename "$grub_cfg")"
    cp "$grub_cfg_backup" "$grub_cfg"
    fi
    fi
    done

    if [[ "$injected" == "true" ]]; then
    return 0
    else
    log_error "수정할 GRUB 설정 파일을 찾지 못했습니다"
    return 1
    fi
}

# isolinux 설정 수정 함수 - WSL 호환 버전 (grub과 동일한 방식)
modify_isolinux_config() {
    log_info "isolinux 설정을 확인하고 수정합니다..."
    
    local isolinux_dir="$WORK_DIR/extracted/isolinux"
    local isolinux_cfg="$isolinux_dir/isolinux.cfg"
    
    if [[ -f "$isolinux_cfg" ]]; then
    log_info "isolinux 설정 파일 발견됨"
    
    # 백업 생성
    cp "$isolinux_cfg" "$isolinux_cfg.backup"
    
    # isolinux.cfg 내 append 라인에 커널 파라미터 추가
    local new_content
    new_content=$(sed 's|^\( *append .*$\)|\1 autoinstall ds=nocloud;s=/cdrom/autoinstall/ console=ttyS0,115200 console=tty0|' "$isolinux_cfg")
    echo "$new_content" > "$isolinux_cfg" || { cp "$isolinux_cfg.backup" "$isolinux_cfg"; log_warning "isolinux 설정 수정 실패"; }
    
    if grep -q "autoinstall" "$isolinux_cfg"; then
    log_success "isolinux 설정에 autoinstall 파라미터 추가됨"
    else
    log_warning "isolinux 설정 수정이 제대로 되지 않았습니다"
    fi
    else
    log_info "isolinux 설정 파일이 없습니다 (EFI 전용일 수 있음)"
    fi

    # BIOS 부팅용 txt.cfg도 있으면 수정
    local txt_cfg="$WORK_DIR/extracted/isolinux/txt.cfg"
    if [[ -f "$txt_cfg" ]]; then
    log_info "isolinux txt.cfg 발견됨"
    cp "$txt_cfg" "$txt_cfg.backup"
    local new_txt
    new_txt=$(sed 's|^\( *append .*$\)|\1 autoinstall ds=nocloud;s=/cdrom/autoinstall/ console=ttyS0,115200 console=tty0|' "$txt_cfg")
    echo "$new_txt" > "$txt_cfg" || { cp "$txt_cfg.backup" "$txt_cfg"; log_warning "txt.cfg 수정 실패"; }
    grep -n "autoinstall" "$txt_cfg" || log_warning "txt.cfg에 autoinstall 미반영"
    fi
}

# 추가 파일 복사
copy_additional_files() {
    log_info "추가 파일들을 복사합니다..."
    
    local files_dir="$WORK_DIR/extracted/files"
    mkdir -p "$files_dir"
    
    # K3s 바이너리 복사
    cp "$OUT_DIR/k3s" "$files_dir/"
    chmod +x "$files_dir/k3s"
    
    # Registry 설정 복사
    cp "$OUT_DIR/registries.yaml" "$files_dir/"
    chmod 644 "$files_dir/registries.yaml"
    
    # CA 인증서 복사
    if [[ -f "$OUT_DIR/certs/ca.crt" ]]; then
    cp "$OUT_DIR/certs/ca.crt" "$files_dir/airgap-registry-ca.crt"
    elif [[ -f "$OUT_DIR/certs/registry.crt" ]]; then
    cp "$OUT_DIR/certs/registry.crt" "$files_dir/airgap-registry-ca.crt"
    fi
    chmod 644 "$files_dir/airgap-registry-ca.crt"
    
    # Airgapped 환경용 패키지 다운로드 및 복사
    log_info "Airgapped 환경용 패키지들을 다운로드합니다..."
    
    # 패키지 다운로드 디렉토리 설정 (scripts/ops-packages)
    local download_dir="$(dirname "$0")/ops-packages"
    mkdir -p "$download_dir"
    
    # VM용 패키지 디렉토리
    local packages_dir="$files_dir/packages"
    mkdir -p "$packages_dir"
    
    # 필요한 패키지 목록 (Ubuntu 22.04 호환성 고려)
    local packages=(
        "jq"
        "htop"
        "ethtool"
        "iproute2"
        "dnsutils"  # dig 명령어 포함
        "telnet"
        "psmisc"
        "sysstat"
    )
    
    # 의존성 패키지 목록 (자동으로 포함)
    local dependency_packages=(
        "libjq1"      # jq 의존성
        "libsensors5" # sysstat 의존성
        "libsensors-config" # libsensors5 의존성
        "libonig5"    # jq 의존성 (일부 버전)
    )
    
    # 선택적 패키지 (있으면 다운로드, 없으면 건너뜀)
    local optional_packages=(
        "iftop"
        "iotop"
        "dstat"
        "yq"
    )
    
    # 패키지 다운로드 (개선된 방식)
    cd "$download_dir"
    
    # 의존성 패키지 먼저 다운로드 (설치 순서 최적화)
    log_info "의존성 패키지 다운로드 중..."
    for package in "${dependency_packages[@]}"; do
        log_info "의존성 패키지 다운로드 중: $package"
        if apt-get download "$package" 2>/dev/null; then
            log_success "의존성 패키지 다운로드 완료: $package"
        else
            log_warning "의존성 패키지 다운로드 실패: $package (건너뜀)"
        fi
    done
    
    # 필수 패키지 다운로드
    log_info "필수 패키지 다운로드 중..."
    for package in "${packages[@]}"; do
        log_info "패키지 다운로드 중: $package"
        if apt-get download "$package" 2>/dev/null; then
            log_success "패키지 다운로드 완료: $package"
        else
            log_warning "패키지 다운로드 실패: $package (건너뜀)"
        fi
    done
    
    # 선택적 패키지 다운로드 (있으면 다운로드)
    log_info "선택적 패키지 다운로드 중..."
    for package in "${optional_packages[@]}"; do
        log_info "선택적 패키지 다운로드 중: $package"
        if apt-get download "$package" 2>/dev/null; then
            log_success "선택적 패키지 다운로드 완료: $package"
        else
            log_info "선택적 패키지 다운로드 실패: $package (정상적인 상황)"
        fi
    done
    
    # 다운로드된 .deb 파일들 확인
    local deb_count=$(ls -1 *.deb 2>/dev/null | wc -l)
    if [[ $deb_count -gt 0 ]]; then
        log_success "총 $deb_count개의 .deb 파일이 다운로드되었습니다"
        ls -la *.deb
    else
        log_warning "다운로드된 .deb 파일이 없습니다"
    fi
    
    # deb 파일들을 tar.gz로 압축
    log_info "deb 파일들을 tar.gz로 압축합니다..."
    local deb_files=$(ls -1 *.deb 2>/dev/null | wc -l)
    if [[ $deb_files -gt 0 ]]; then
        tar -czf "k8s-ops-packages.tar.gz" *.deb
        log_success "deb 파일들을 k8s-ops-packages.tar.gz로 압축 완료"
        
        # 압축 파일 크기 확인
        local archive_size=$(du -h "k8s-ops-packages.tar.gz" | cut -f1)
        log_info "압축 파일 크기: $archive_size"
        
            # 원본 deb 파일들 삭제 (압축 파일만 유지)
    rm -f *.deb
    log_info "원본 deb 파일들 삭제됨 (압축 파일만 유지)"
    
    # 압축 파일을 VM용 디렉토리로 복사
    cp "k8s-ops-packages.tar.gz" "$packages_dir/"
    log_info "압축 파일을 VM용 디렉토리로 복사: $packages_dir/"
    else
        log_warning "압축할 deb 파일이 없습니다"
        # 빈 tar.gz 파일 생성 (VM에서 오류 방지)
        tar -czf "k8s-ops-packages.tar.gz" --files-from /dev/null
        log_info "빈 k8s-ops-packages.tar.gz 파일 생성됨 (VM 호환성용)"
        
        # 빈 압축 파일을 VM용 디렉토리로 복사
        cp "k8s-ops-packages.tar.gz" "$packages_dir/"
        log_info "빈 압축 파일을 VM용 디렉토리로 복사: $packages_dir/"
    fi
    
    # 패키지 설치 스크립트 생성 (tar.gz 압축 해제 포함)
    cat > "$packages_dir/install-packages.sh" << 'EOF'
#!/bin/bash
# Airgapped 환경에서 패키지 설치 스크립트
set -euo pipefail

log() { echo "[install-packages] $1"; }

log "Airgapped 환경에서 추가 패키지들을 설치합니다..."

# tar.gz 파일이 있으면 압축 해제
if [[ -f "k8s-ops-packages.tar.gz" ]]; then
    log "k8s-ops-packages.tar.gz 압축 해제 중..."
    tar -xzf "k8s-ops-packages.tar.gz"
    log "압축 해제 완료"
fi

# 설치 순서 최적화: 의존성 패키지 먼저 설치
log "의존성 패키지 먼저 설치 중..."
for deb_file in lib*.deb; do
    if [[ -f "$deb_file" ]]; then
        log "의존성 패키지 설치 중: $deb_file"
        dpkg -i "$deb_file" || log "의존성 패키지 설치 실패: $deb_file"
    fi
done

# 의존성 문제 해결 (1차)
log "1차 의존성 문제 해결 중..."
apt-get install -f -y || log "1차 의존성 해결 실패"

# 주요 패키지들 설치
log "주요 패키지들 설치 중..."
for deb_file in *.deb; do
    if [[ -f "$deb_file" && ! "$deb_file" =~ ^lib ]]; then
        log "패키지 설치 중: $deb_file"
        dpkg -i "$deb_file" || log "패키지 설치 실패: $deb_file"
    fi
done

# 의존성 문제 해결 (2차)
log "2차 의존성 문제 해결 중..."
apt-get install -f -y || log "2차 의존성 해결 실패"

# 설치 완료 확인 및 마커 파일 생성
log "설치된 패키지 확인 중..."
dpkg -l | grep -E "(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)" || log "설치된 패키지 없음"

# 설치 성공률 계산
total_packages=8
installed_count=0
for cmd in jq htop ethtool ip dnsutils telnet fuser iostat; do
    if command -v "$cmd" >/dev/null 2>&1; then
        installed_count=$((installed_count + 1))
    fi
done
success_rate=$(( (installed_count * 100) / total_packages ))

log "설치 성공률: $installed_count/$total_packages ($success_rate%)"

# 설치 완료 마커 파일 생성
echo "$(date): k8s 운영 패키지 설치 완료 (성공률: $success_rate%)" > /var/lib/k8s-ops-packages-installed
log "패키지 설치 완료!"
EOF
    chmod +x "$packages_dir/install-packages.sh"
    
    # 작업 디렉토리를 원래 위치로 복원
    cd "$(dirname "$0")"
    
    log_success "Airgapped 환경용 패키지 준비 완료 (tar.gz 압축 포함)"
    log_info "패키지 다운로드 위치: $download_dir"
    log_info "VM용 패키지 위치: $packages_dir"
    
    # WSL 기준 빌드 시각 기록 (부팅 시 초기 오프라인 시간 동기화에 사용)
    if command -v date &> /dev/null; then
    # UTC 기준으로만 epoch 생성 (타임존 무관한 절대시간)
    EPOCH_SECONDS=$(TZ=UTC date +%s)
    RFC3339_UTC=$(TZ=UTC date +%Y-%m-%dT%H:%M:%SZ)
    
    # WSL의 현재 타임존 정보 캡처
    WSL_TIMEZONE=$(cat /etc/timezone 2>/dev/null || date +%Z)
    WSL_OFFSET=$(date +%z)
    
    # 빌드 호스트 정보
    BUILD_HOST_TYPE="WSL"
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    BUILD_HOST_TYPE="WSL-${WSL_DISTRO_NAME}"
    fi
    
    {
    echo "# Seed ISO build time captured on ${BUILD_HOST_TYPE}"
    echo "# All times normalized to UTC for consistent VM setup"
    echo "EPOCH_SECONDS=$EPOCH_SECONDS"
    echo "RFC3339_UTC=$RFC3339_UTC"
    echo "BUILD_HOST_TIMEZONE=$WSL_TIMEZONE"
    echo "BUILD_HOST_OFFSET=$WSL_OFFSET"
    echo "# Target VM timezone will be set to Asia/Seoul (UTC+9)"
    echo "TARGET_TIMEZONE=Asia/Seoul"
    } > "$files_dir/build-timestamp" 2>/dev/null || true
    chmod 644 "$files_dir/build-timestamp" 2>/dev/null || true
    
    log_success "빌드 타임스탬프 생성 완료 (UTC 기준 epoch: $EPOCH_SECONDS)"
    fi

    # Airgap 이미지 복사 (있는 경우)
    if [[ -f "$OUT_DIR/airgap/k3s-airgap-images-amd64.tar.gz" ]]; then
    cp "$OUT_DIR/airgap/k3s-airgap-images-amd64.tar.gz" "$files_dir/"
    chmod 644 "$files_dir/k3s-airgap-images-amd64.tar.gz"
    log_success "Airgap 이미지 포함됨"
    else
    log_warning "Airgap 이미지가 없습니다"
    fi
    
    log_success "추가 파일들 복사 완료"

    # Ensure LF endings for bootstrap scripts and unit files in extracted tree after templates render
    # These files are generated when cloud-init runs on target, but we also normalize any files we ship
    if command -v sed >/dev/null 2>&1; then
    # If any CRLF sneaks into templates copied into ISO, remove CRs defensively
    find "$WORK_DIR/extracted" -type f \( -name 'user-data*' -o -name 'meta-data*' -o -name '*.service' -o -name '*.sh' -o -name 'registries.yaml' -o -name 'build-timestamp' \) -print0 2>/dev/null | \
    xargs -0 -I{} sh -c "sed -i 's/\\r$//' '{}' 2>/dev/null || true"
    log_success "ISO 내 텍스트 파일 줄바꿈(LF) 정규화 완료"
    fi
}

# Ubuntu 22.04.5 전용 Seed ISO 생성 함수 (수정된 버전)
generate_seed_isos() {
    log_info "Seed ISO 파일들을 생성합니다..."
    
    local extracted_dir="$WORK_DIR/extracted"
    
    # ISO 9660 규칙에 맞는 볼륨 라벨 사용
    local volume_label="Ubuntu-Server-22045-amd64"
    
    # 로그에서 확인된 부팅 파일들을 기반으로 설정
    local has_bios_boot=true
    local has_efi_boot=true
    local bios_boot_img="boot/grub/i386-pc/eltorito.img"
    local efi_boot_file="EFI/boot/bootx64.efi"
    
    # 실제 파일 존재 여부 재확인
    if [[ ! -f "$extracted_dir/$bios_boot_img" ]]; then
    log_warning "BIOS 부팅 파일이 복사되지 않았습니다: $bios_boot_img"
    has_bios_boot=false
    fi
    
    if [[ ! -f "$extracted_dir/$efi_boot_file" ]]; then
    log_warning "EFI 부팅 파일이 복사되지 않았습니다: $efi_boot_file"
    has_efi_boot=false
    fi
    
    # boot.catalog 확인
    local has_boot_catalog=false
    if [[ -f "$extracted_dir/boot.catalog" ]]; then
    has_boot_catalog=true
    log_success "boot.catalog 파일 확인됨"
    fi
    
    # Ubuntu 22.04.5 Live Server에 특화된 xorriso 명령어 구성
    local base_cmd="xorriso -as mkisofs"
    base_cmd="$base_cmd -r -V \"$volume_label\""
    base_cmd="$base_cmd -J -joliet-long"
    base_cmd="$base_cmd -rational-rock"
    
    # BIOS 부팅 지원 (El Torito)
    if [[ "$has_bios_boot" == "true" ]]; then
    base_cmd="$base_cmd -b $bios_boot_img"
    base_cmd="$base_cmd -no-emul-boot -boot-load-size 4 -boot-info-table"
    
    # Boot catalog 설정
    if [[ "$has_boot_catalog" == "true" ]]; then
    base_cmd="$base_cmd -c boot.catalog"
    fi
    
    log_info "BIOS 부팅 지원 추가: $bios_boot_img"
    fi
    
    # EFI 부팅 지원
    if [[ "$has_efi_boot" == "true" ]]; then
    if [[ "$has_bios_boot" == "true" ]]; then
    base_cmd="$base_cmd -eltorito-alt-boot"
    fi
    
    # Ubuntu 22.04.5는 EFI 파티션 이미지가 없으므로 EFI 디렉토리를 직접 사용
    # 대신 EFI 시스템 파티션을 생성
    if [[ -f "$extracted_dir/boot/grub/efi.img" ]]; then
    base_cmd="$base_cmd -e boot/grub/efi.img -no-emul-boot"
    else
    # EFI 파티션 이미지가 없는 경우 EFI 파일들을 직접 사용
    base_cmd="$base_cmd -e $efi_boot_file -no-emul-boot"
    fi
    
    log_info "EFI 부팅 지원 추가"
    fi
    
    # 하이브리드 부팅 지원 (USB에서도 부팅 가능)
    if [[ -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]]; then
    base_cmd="$base_cmd -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin"
    log_info "하이브리드 MBR 부팅 지원 추가"
    elif [[ -f "/usr/lib/syslinux/isohdpfx.bin" ]]; then
    base_cmd="$base_cmd -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin"
    log_info "하이브리드 MBR 부팅 지원 추가 (syslinux)"
    else
    log_warning "하이브리드 MBR 파일을 찾을 수 없습니다"
    fi
    
    # GPT 파티션 테이블 지원 (최신 UEFI 시스템)
    if [[ "$has_efi_boot" == "true" ]]; then
    base_cmd="$base_cmd -isohybrid-gpt-basdat"
    
    # EFI 시스템 파티션을 GPT에 추가
    if [[ -f "$extracted_dir/boot/grub/efi.img" ]]; then
    base_cmd="$base_cmd -append_partition 2 0xef boot/grub/efi.img"
    fi
    fi
    
    # 각 ISO 생성 함수 (수정된 버전)
    create_iso() {
    local node_name="$1"
    local user_data_suffix="$2"
    local output_iso="$3"
    
    log_info "$node_name ISO 생성 중..."
    
    # 해당 노드용 user-data와 meta-data를 기본 파일명으로 복사
    cp "$extracted_dir/autoinstall/user-data-$user_data_suffix" "$extracted_dir/autoinstall/user-data"
    cp "$extracted_dir/autoinstall/meta-data-$user_data_suffix" "$extracted_dir/autoinstall/meta-data"
    
    local cmd="$base_cmd -o \"$output_iso\" \"$extracted_dir\""
    
    log_info "실행 명령어: $cmd"
    
    # ISO 생성 실행
    if eval "$cmd" 2>&1; then
    local size=$(du -h "$output_iso" | cut -f1)
    log_success "$node_name ISO 생성 완료 (크기: $size)"
    
    # ISO 파일 기본 검증
    if command -v file &> /dev/null; then
    local file_info=$(file "$output_iso")
    if echo "$file_info" | grep -q "ISO 9660"; then
    log_success "$node_name ISO가 올바른 ISO 9660 형식입니다"
    
    # 부팅 가능 여부 확인
    if echo "$file_info" | grep -q -i "boot"; then
    log_success "$node_name ISO가 부팅 가능한 것으로 보입니다"
    fi
    else
    log_warning "$node_name ISO 형식 확인 필요: $file_info"
    fi
    fi
    
    return 0
    else
    log_error "$node_name ISO 생성 실패"
    return 1
    fi
    }
    
    # 실제 ISO 파일들 생성
    log_info "ISO 생성을 시작합니다..."
    
    create_iso "Master" "master1" "$OUT_DIR/seed-master1.iso" || {
    log_error "Master ISO 생성 실패"
    exit 1
    }
    
    create_iso "Worker1" "worker1" "$OUT_DIR/seed-worker1.iso" || {
    log_error "Worker1 ISO 생성 실패"
    exit 1
    }
    
    create_iso "Worker2" "worker2" "$OUT_DIR/seed-worker2.iso" || {
    log_error "Worker2 ISO 생성 실패"
    exit 1
    }
    
    # 부팅 검증
    log_info "생성된 ISO들의 부팅 정보를 검증합니다..."
    for iso_file in "$OUT_DIR/seed-master1.iso" "$OUT_DIR/seed-worker1.iso" "$OUT_DIR/seed-worker2.iso"; do
    if command -v isoinfo &> /dev/null; then
    log_info "$(basename "$iso_file") 부팅 정보:"
    isoinfo -d -i "$iso_file" | grep -E "(Boot|System|Volume|El Torito)" || true
    fi
    done
    
    log_success "모든 Seed ISO 파일이 성공적으로 생성되었습니다!"
}

# 결과 확인
verify_results() {
    log_info "생성된 ISO 파일들을 확인합니다..."
    
    local iso_files=(
    "$OUT_DIR/seed-master1.iso"
    "$OUT_DIR/seed-worker1.iso"
    "$OUT_DIR/seed-worker2.iso"
    )
    
    for iso_file in "${iso_files[@]}"; do
    if [[ -f "$iso_file" ]]; then
    local size=$(du -h "$iso_file" | cut -f1)
    log_success "$(basename "$iso_file") 생성됨 (크기: $size)"
    else
    log_error "$(basename "$iso_file") 생성 실패"
    exit 1
    fi
    done
    
    log_success "모든 seed ISO 파일이 성공적으로 생성되었습니다!"
    echo
    log_info "VM 부팅 순서를 'disk, cdrom'으로 설정하세요. (설치 후 CD-ROM 제거 시 재부팅이 원활합니다)"
}

# 정리
cleanup() {
    log_info "작업 디렉토리를 정리합니다..."
    
    if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    log_success "작업 디렉토리 정리 완료"
    fi
}

# 메인 실행
main() {
    log_info "=== Ubuntu 22.04.5 LTS 기반 Seed ISO 생성 시작 ==="
    
    # cleanup-only 모드인 경우 WSL 설정 건너뛰고 바로 정리
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
    # 디렉토리 생성
    mkdir -p "$OUT_DIR"
    
    # 기존 리소스 정리 (Windows 디렉토리)
    cleanup_existing_resources
    
    # WSL 작업 디렉토리도 정리 (있다면)
    if [[ -d "$HOME/airgapped-k3s-build" ]]; then
    log_info "WSL 작업 디렉토리도 정리합니다..."
    
    # 마운트된 ISO가 있다면 해제
    local mount_point="$HOME/airgapped-k3s-build/ubuntu-seed-work/mount"
    if mountpoint -q "$mount_point" 2>/dev/null; then
    log_info "마운트된 ISO를 해제합니다..."
    sudo umount "$mount_point" || true
    fi
    
    # 권한 변경 후 삭제
    sudo chmod -R 755 "$HOME/airgapped-k3s-build/" 2>/dev/null || true
    sudo rm -rf "$HOME/airgapped-k3s-build"
    log_success "WSL 작업 디렉토리 정리 완료"
    fi
    
    # WSL 환경인 경우 ORIGINAL_OUT_DIR의 ISO 파일들도 정리
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ "$(pwd)" == /mnt/* ]]; then
    local windows_out_dir="$(cd "$(dirname "$0")"/.. && pwd)/out"
    if [[ -d "$windows_out_dir" ]]; then
    log_info "Windows 디렉토리의 생성된 ISO 파일들도 정리합니다..."
    
    local iso_files=(
    "$windows_out_dir/seed-master1.iso"
    "$windows_out_dir/seed-worker1.iso"
    "$windows_out_dir/seed-worker2.iso"
    )
    
    for iso_file in "${iso_files[@]}"; do
    if [[ -f "$iso_file" ]]; then
    rm -f "$iso_file"
    log_info "삭제됨: $(basename "$iso_file")"
    fi
    done
    
    log_success "Windows 디렉토리 ISO 파일 정리 완료"
    fi
    fi
    
    log_success "Cleanup completed. Exiting."
    exit 0
    fi
    
    # WSL 환경 설정 (정상 실행 모드에서만)
    setup_wsl_environment
    
    log_info "Ubuntu ISO 다운로드 정책:"
    log_info "- 기존 파일이 있으면 무결성 검증 후 재사용"
    log_info "- 파일이 손상되었으면 자동으로 재다운로드"
    log_info "- 예상 파일 크기: 약 2.1GB"
    echo
    
    # 디렉토리 생성
    mkdir -p "$OUT_DIR"
    
    # 기존 리소스 정리
    cleanup_existing_resources
    
    # 1. 필수 도구 확인
    check_prerequisites
    
    # 2. Ubuntu ISO 다운로드
    download_ubuntu_iso
    
    # 3. 자격증명 로드
    load_credentials
    
    # 4. 토큰 생성
    generate_token
    
    # 4.1 비밀번호 해시 생성
    generate_password_hash
    
    # 5. 템플릿 환경변수 설정
    set_template_vars
    
    # 6. 작업 디렉토리 정리
    cleanup_work_dir
    
    # 7. Ubuntu ISO 추출
    extract_ubuntu_iso
    
    # 8. cloud-init 파일 생성
    generate_cloud_init_files
    
    # 9. 추가 파일 복사
    copy_additional_files
    
    # 10. GRUB 설정 수정
    modify_grub_config
    
    # 11. isolinux 설정 수정
    modify_isolinux_config
    
    # 12. Seed ISO 생성
    generate_seed_isos
    
    # 13. 결과 확인
    verify_results
    
    # 14. 정리
    cleanup
    
    log_info "=== Ubuntu 22.04.5 LTS 기반 Seed ISO 생성 완료 ==="
    log_info "다음 단계:"
    log_info "1. Windows에서 VM 생성: .\\windows\\Setup-VMs.ps1"
    log_info "2. VM 부팅 후 클러스터 확인: ./02_wait_and_config.sh"
}

# 스크립트 실행
main "$@"