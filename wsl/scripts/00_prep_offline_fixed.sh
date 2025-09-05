#!/bin/bash

# KubeSphere Airgap Lab - Fixed Offline Preparation Script
# 이 스크립트는 이미지 pull 실패 문제를 해결한 버전입니다.

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

# 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/out"

# 환경변수 자동 설정 함수
setup_environment() {
    log_info "환경변수 자동 설정 중..."
    
    # 기본값 설정 (사용자가 이미 설정한 값이 있으면 유지)
    export REGISTRY_HOST_IP="${REGISTRY_HOST_IP:-192.168.6.1}"
    export REGISTRY_PORT="${REGISTRY_PORT:-5000}"
    export USE_EXTERNAL_REGISTRY="${USE_EXTERNAL_REGISTRY:-true}"
    export EXTERNAL_REGISTRY_PUSH_HOST="${EXTERNAL_REGISTRY_PUSH_HOST:-localhost}"
    export EXTERNAL_REGISTRY_PUSH_PORT="${EXTERNAL_REGISTRY_PUSH_PORT:-5000}"
    export REGISTRY_USERNAME="${REGISTRY_USERNAME:-admin}"
    export REGISTRY_TLS_INSECURE="${REGISTRY_TLS_INSECURE:-true}"
    
    # 비밀번호가 설정되지 않은 경우 사용자에게 입력 요청
    if [[ -z "$REGISTRY_PASSWORD" ]]; then
        log_warning "REGISTRY_PASSWORD가 설정되지 않았습니다."
        echo -n "Nexus3 비밀번호를 입력하세요 (기본값: nam0941!@#): "
        read -r input_password
        export REGISTRY_PASSWORD="${input_password:-nam0941!@#}"
    fi
    
    # 환경변수 정보 출력
    log_info "설정된 환경변수:"
    log_info "  REGISTRY_HOST_IP: $REGISTRY_HOST_IP"
    log_info "  REGISTRY_PORT: $REGISTRY_PORT"
    log_info "  USE_EXTERNAL_REGISTRY: $USE_EXTERNAL_REGISTRY"
    log_info "  EXTERNAL_REGISTRY_PUSH_HOST: $EXTERNAL_REGISTRY_PUSH_HOST"
    log_info "  EXTERNAL_REGISTRY_PUSH_PORT: $EXTERNAL_REGISTRY_PUSH_PORT"
    log_info "  REGISTRY_USERNAME: $REGISTRY_USERNAME"
    log_info "  REGISTRY_PASSWORD: [설정됨]"
    log_info "  REGISTRY_TLS_INSECURE: $REGISTRY_TLS_INSECURE"
}

# Registry network configuration (used for TLS SANs and client access from VMs)
# Default host IP is the Windows host-only IP that VMs reach; override via env if needed
REGISTRY_HOST_IP="${REGISTRY_HOST_IP:-192.168.6.1}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"

# External/private registry (e.g., Nexus3 running in WSL via docker run)
# - When enabled, we DO NOT start local registry:2 nor generate local TLS certs
# - Push endpoint is typically WSL localhost:5000
# - VM pull endpoint remains ${REGISTRY_HOST_IP}:${REGISTRY_PORT} via Windows portproxy
USE_EXTERNAL_REGISTRY="${USE_EXTERNAL_REGISTRY:-true}"
EXTERNAL_REGISTRY_PUSH_HOST="${EXTERNAL_REGISTRY_PUSH_HOST:-localhost}"
EXTERNAL_REGISTRY_PUSH_PORT="${EXTERNAL_REGISTRY_PUSH_PORT:-5000}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-admin}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"

# TLS verification for VMs pulling from registry
# If your Nexus3 uses a self-signed certificate, keep this true (skip verification)
# Otherwise set to false and distribute CA, then set ca_file in templates when needed
REGISTRY_TLS_INSECURE="${REGISTRY_TLS_INSECURE:-true}"

# Effective endpoints
# - PUSH from WSL to registry
REGISTRY_PUSH_HOST="$EXTERNAL_REGISTRY_PUSH_HOST"
REGISTRY_PUSH_PORT="$EXTERNAL_REGISTRY_PUSH_PORT"
# - PULL from VMs to Windows host (forwarded to WSL)
REGISTRY_PULL_HOST="$REGISTRY_HOST_IP"
REGISTRY_PULL_PORT="$REGISTRY_PORT"

# 이미지 목록 파일 선택
IMAGES_FILE="$PROJECT_ROOT/examples/images-fixed.txt"

# 기본 이미지 목록이 없으면 미러 버전 사용
if [ ! -f "$IMAGES_FILE" ]; then
    IMAGES_FILE="$PROJECT_ROOT/examples/images-mirror.txt"
    log_warning "기본 이미지 목록을 찾을 수 없어 미러 버전을 사용합니다: $IMAGES_FILE"
fi

# 미러 버전도 없으면 원본 사용
if [ ! -f "$IMAGES_FILE" ]; then
    IMAGES_FILE="$PROJECT_ROOT/examples/images-full.txt"
    log_warning "미러 이미지 목록도 찾을 수 없어 원본을 사용합니다: $IMAGES_FILE"
fi

log_info "사용할 이미지 목록: $IMAGES_FILE"

# 필수 디렉토리 생성
mkdir -p "$OUTPUT_DIR"/{registry,ssh,certs}

# 사전 요구사항 확인
check_prerequisites() {
    log_info "사전 요구사항 확인 중..."
    
    # WSL2 환경 확인
    if [[ ! -f /proc/version ]] || ! grep -q Microsoft /proc/version; then
        log_warning "이 스크립트는 WSL2 환경에서 실행하도록 설계되었습니다"
    fi
    
    # Docker 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되지 않았습니다"
        exit 1
    fi
    
    # Docker 서비스 실행 확인
    if ! docker info &> /dev/null; then
        log_error "Docker 서비스가 실행되지 않았습니다"
        exit 1
    fi
    
    log_success "사전 요구사항 확인 완료"
}

# 필요한 패키지 설치
install_packages() {
    log_info "필요한 패키지 설치 중..."
    
    sudo apt-get update
    sudo apt-get install -y \
        genisoimage \
        lsb-release \
        ca-certificates \
        curl \
        gnupg \
        jq \
        openssl \
        qemu-utils \
        xxd \
        docker.io
    
    log_success "패키지 설치 완료"
}

# External registry login and health check (when USE_EXTERNAL_REGISTRY=true)
login_and_check_registry() {
    if [[ "$USE_EXTERNAL_REGISTRY" == "true" ]]; then
        if [[ -z "$REGISTRY_PASSWORD" ]]; then
            log_error "외부 레지스트리 비밀번호가 비어있습니다. REGISTRY_PASSWORD 를 설정하세요."
            exit 1
        fi

        local login_endpoint="${REGISTRY_PUSH_HOST}:${REGISTRY_PUSH_PORT}"
        log_info "외부 레지스트리 로그인 중: ${login_endpoint} (username=${REGISTRY_USERNAME})"
        echo "$REGISTRY_PASSWORD" | docker login "$login_endpoint" --username "$REGISTRY_USERNAME" --password-stdin

        log_info "외부 레지스트리 상태 확인 중 (/v2/) ..."
        # -k 사용: 셀프사인 인증서 환경 지원
        if curl -fsSk "https://${login_endpoint}/v2/" > /dev/null 2>&1; then
            log_success "외부 레지스트리 접근 가능"
        else
            log_error "외부 레지스트리에 접근할 수 없습니다: https://${login_endpoint}/v2/"
            exit 1
        fi
    else
        # Local legacy path
        generate_certificates
        start_registry
    fi
}

# TLS 인증서 생성
generate_certificates() {
    log_info "레지스트리용 TLS 인증서 생성 중... (SAN: IP:${REGISTRY_HOST_IP}, IP:127.0.0.1, DNS:localhost)"
    
    local cert_dir="$OUTPUT_DIR/certs"
    mkdir -p "$cert_dir"
    
    # 자체 서명 인증서 생성 (OpenSSL 1.1.1+)
    # - CN 은 VM에서 접근하는 호스트 IP로 설정
    # - SAN 에 VM/IP 및 localhost 를 포함해 WSL 내부/외부 모두 유효하도록 설정
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$cert_dir/registry.key" \
        -out "$cert_dir/registry.crt" \
        -days 365 -nodes \
        -subj "/C=KR/ST=Seoul/L=Seoul/O=Private Registry/OU=Airgap Lab/CN=${REGISTRY_HOST_IP}" \
        -addext "subjectAltName=IP:${REGISTRY_HOST_IP},IP:127.0.0.1,DNS:localhost"
    
    # ca.crt 파일도 생성 (seed ISO 에 포함되어 VM 신뢰 저장소에 설치됨)
    cp "$cert_dir/registry.crt" "$cert_dir/ca.crt"
    
    log_success "TLS 인증서 생성 완료"
}

# 로컬 레지스트리 시작
start_registry() {
    log_info "localhost:${REGISTRY_PORT}에서 로컬 레지스트리 확인 중..."
    
    # 기존 레지스트리 컨테이너가 실행 중인지 확인
    if docker ps --format "table {{.Names}}" | grep -q "^airgap-registry$"; then
        log_info "기존 레지스트리가 실행 중입니다. 재사용합니다."
        
        # 레지스트리 상태 확인
        if curl -k -s https://localhost:${REGISTRY_PORT}/v2/ > /dev/null 2>&1; then
            log_success "기존 레지스트리가 정상 동작 중입니다"
            return 0
        else
            log_warning "기존 레지스트리가 응답하지 않습니다. 재시작합니다."
            docker stop airgap-registry 2>/dev/null || true
            docker rm airgap-registry 2>/dev/null || true
        fi
    else
        log_info "새로운 레지스트리를 시작합니다."
    fi
    
    # 새 레지스트리 컨테이너 시작 (모든 인터페이스에 바인딩)
    docker run -d --name airgap-registry \
        -p 0.0.0.0:${REGISTRY_PORT}:5000 \
        -v "$OUTPUT_DIR/registry:/var/lib/registry" \
        -v "$OUTPUT_DIR/certs:/certs" \
        -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
        -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
        registry:2
    
    # 레지스트리 시작 대기 및 상태 확인
    log_info "레지스트리 시작 대기 중..."
    local retry_count=0
    while [ $retry_count -lt 10 ]; do
        if curl -k -s https://localhost:${REGISTRY_PORT}/v2/ > /dev/null 2>&1; then
            log_success "레지스트리 시작 완료"
            return 0
        fi
        retry_count=$((retry_count + 1))
        sleep 2
    done
    
    log_error "레지스트리 시작 실패"
    return 1
}

# 이미지 미러링
mirror_images() {
    local push_endpoint="${REGISTRY_PUSH_HOST}:${REGISTRY_PUSH_PORT}"
    log_info "이미지 미러링 시작: $IMAGES_FILE -> ${push_endpoint}"
    
    local total_images=$(wc -l < "$IMAGES_FILE")
    local current=0
    local failed_images=()
    
    while IFS=' ' read -r source_image target_image; do
        # 주석 라인 건너뛰기
        [[ $source_image =~ ^#.*$ ]] && continue
        [[ -z $source_image ]] && continue
        
        # Windows 줄바꿈 문자 제거
        source_image=$(echo "$source_image" | tr -d '\r')
        target_image=$(echo "$target_image" | tr -d '\r')
        
        current=$((current + 1))
        log_info "[$current/$total_images] 미러링: $source_image -> ${push_endpoint}/$target_image"
        
        # 이미지 pull 및 push (3회 재시도)
        local retry_count=0
        local success=false
        
        while [ $retry_count -lt 3 ] && [ "$success" = false ]; do
            if docker pull "$source_image" && \
               docker tag "$source_image" "${push_endpoint}/$target_image" && \
               docker push "${push_endpoint}/$target_image"; then
                success=true
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt 3 ]; then
                    log_warning "$source_image pull 실패 (시도 $retry_count/3)"
                    sleep 2
                fi
            fi
        done
        
        if [ "$success" = false ]; then
            log_error "$source_image pull 실패 (3회 시도 후) - 건너뛰기"
            failed_images+=("$source_image")
        fi
    done < "$IMAGES_FILE"
    
    # 실패한 이미지들 보고
    if [ ${#failed_images[@]} -gt 0 ]; then
        log_warning "일부 이미지 미러링 실패. 계속 진행합니다..."
        log_error "실패한 이미지들 (${#failed_images[@]}개):"
        for img in "${failed_images[@]}"; do
            echo "  - PULL_FAILED: $img"
        done
    fi
    
    log_info "이미지 미러링 완료"
}

# k3s 바이너리 다운로드
download_k3s() {
    log_info "k3s v1.33.4-rc1+k3s1 다운로드 중..."
    
    # k3s 바이너리를 out 디렉토리에 직접 다운로드
    curl -L -o "$OUTPUT_DIR/k3s" \
        "https://github.com/k3s-io/k3s/releases/download/v1.33.4-rc1%2Bk3s1/k3s"
    
    chmod +x "$OUTPUT_DIR/k3s"
    
    log_success "k3s 바이너리 다운로드 완료"
}

# 에어갭 이미지 다운로드 (선택사항)
download_airgap_images() {
    log_info "에어갭 이미지 다운로드 중 (선택사항)..."
    
    local airgap_dir="$OUTPUT_DIR/airgap"
    mkdir -p "$airgap_dir"
    
    # 에어갭 이미지 tar.gz 파일 다운로드
    curl -L -o "$airgap_dir/k3s-airgap-images-amd64.tar.gz" \
        "https://github.com/k3s-io/k3s/releases/download/v1.33.4-rc1%2Bk3s1/k3s-airgap-images-amd64.tar.gz"
    
    # SHA256 체크섬 다운로드
    curl -L -o "$airgap_dir/k3s-airgap-images-amd64.sha256sum" \
        "https://github.com/k3s-io/k3s/releases/download/v1.33.4-rc1%2Bk3s1/k3s-airgap-images-amd64.sha256sum"
    
    # 체크섬 검증 (tar.gz 파일만 검증)
    cd "$airgap_dir"
    if echo "8cd72a5d8e7a232bb1c52b2d4df2f4f28a60e9d8311c130122bd9650ef9d1621  k3s-airgap-images-amd64.tar.gz" | sha256sum -c; then
        log_success "에어갭 이미지 다운로드 및 검증 완료"
        log_info "에어갭 이미지 위치: $airgap_dir/k3s-airgap-images-amd64.tar.gz"
        log_info "사용법: gunzip -c k3s-airgap-images-amd64.tar.gz | docker load"
    else
        log_error "에어갭 이미지 체크섬 검증 실패"
    fi
}

# registries.yaml 생성
generate_registries_config() {
    log_info "registries.yaml 설정 생성 중... (VM → https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT})"
    
    # 인증 정보가 있는 경우와 없는 경우를 구분하여 생성
    if [[ "$USE_EXTERNAL_REGISTRY" == "true" && -n "$REGISTRY_USERNAME" && -n "$REGISTRY_PASSWORD" ]]; then
        log_info "인증 정보를 포함한 registries.yaml 생성 (username=${REGISTRY_USERNAME})"
        cat > "$OUTPUT_DIR/registries.yaml" << EOF
mirrors:
  "${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "registry.k8s.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "docker.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "quay.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "gcr.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "kubesphere":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "prom":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "grafana":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "bitnami":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "rancher":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"

configs:
  "${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}":
    tls:
      insecure_skip_verify: ${REGISTRY_TLS_INSECURE}
    auth:
      username: ${REGISTRY_USERNAME}
      password: ${REGISTRY_PASSWORD}
EOF
    else
        log_info "인증 정보 없이 registries.yaml 생성 (공개 레지스트리 또는 인증 불필요)"
        cat > "$OUTPUT_DIR/registries.yaml" << EOF
mirrors:
  "${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "registry.k8s.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "docker.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "quay.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "gcr.io":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "kubesphere":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "prom":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "grafana":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "bitnami":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
  "rancher":
    endpoint:
      - "https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"

configs:
  "${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}":
    tls:
      insecure_skip_verify: ${REGISTRY_TLS_INSECURE}
EOF
    fi
    
    log_success "registries.yaml 설정 생성 완료"
}

# SSH 키 생성
generate_ssh_keys() {
    log_info "VM 접근용 SSH 키 쌍 생성 중..."
    
    local ssh_dir="$OUTPUT_DIR/ssh"
    mkdir -p "$ssh_dir"
    
    if [ ! -f "$ssh_dir/id_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f "$ssh_dir/id_rsa" -N "" -C "airgap-lab@$(hostname)"
    fi
    
    log_success "SSH 키 쌍 생성 완료"
}

# 메인 실행
main() {
    log_info "KubeSphere Airgap Lab 오프라인 준비 시작"
    
    # 환경변수 자동 설정
    setup_environment
    
    check_prerequisites
    install_packages
    login_and_check_registry
    mirror_images
    download_k3s
    download_airgap_images
    generate_registries_config
    generate_ssh_keys
    
    log_success "오프라인 준비 완료"
    log_info "출력 디렉토리: $OUTPUT_DIR"
    log_info "푸시 엔드포인트 (WSL 내부): https://${REGISTRY_PUSH_HOST}:${REGISTRY_PUSH_PORT}"
    log_info "풀 엔드포인트 (VM에서 접근): https://${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}"
    log_info "SSH 개인키: $OUTPUT_DIR/ssh/id_rsa"
}

# 스크립트 실행
main "$@"