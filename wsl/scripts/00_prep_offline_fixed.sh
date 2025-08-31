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

# TLS 인증서 생성
generate_certificates() {
    log_info "레지스트리용 TLS 인증서 생성 중..."
    
    local cert_dir="$OUTPUT_DIR/certs"
    mkdir -p "$cert_dir"
    
    # 자체 서명 인증서 생성
    openssl req -x509 -newkey rsa:4096 -keyout "$cert_dir/registry.key" \
        -out "$cert_dir/registry.crt" -days 365 -nodes \
        -subj "/C=KR/ST=Seoul/L=Seoul/O=Private Registry/OU=Airgap Lab/CN=localhost"
    
    # ca.crt 파일도 생성 (01_build_seed_isos.sh에서 필요)
    cp "$cert_dir/registry.crt" "$cert_dir/ca.crt"
    
    log_success "TLS 인증서 생성 완료"
}

# 로컬 레지스트리 시작
start_registry() {
    log_info "localhost:5000에서 로컬 레지스트리 확인 중..."
    
    # 기존 레지스트리 컨테이너가 실행 중인지 확인
    if docker ps --format "table {{.Names}}" | grep -q "^airgap-registry$"; then
        log_info "기존 레지스트리가 실행 중입니다. 재사용합니다."
        
        # 레지스트리 상태 확인
        if curl -k -s https://localhost:5000/v2/ > /dev/null 2>&1; then
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
        -p 0.0.0.0:5000:5000 \
        -v "$OUTPUT_DIR/registry:/var/lib/registry" \
        -v "$OUTPUT_DIR/certs:/certs" \
        -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
        -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
        registry:2
    
    # 레지스트리 시작 대기 및 상태 확인
    log_info "레지스트리 시작 대기 중..."
    local retry_count=0
    while [ $retry_count -lt 10 ]; do
        if curl -k -s https://localhost:5000/v2/ > /dev/null 2>&1; then
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
    log_info "이미지 미러링 시작: $IMAGES_FILE -> localhost:5000"
    
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
        log_info "[$current/$total_images] 미러링: $source_image -> localhost:5000/$target_image"
        
        # 이미지 pull 및 push (3회 재시도)
        local retry_count=0
        local success=false
        
        while [ $retry_count -lt 3 ] && [ "$success" = false ]; do
            if docker pull "$source_image" && \
               docker tag "$source_image" "localhost:5000/$target_image" && \
               docker push "localhost:5000/$target_image"; then
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
    log_info "registries.yaml 설정 생성 중..."
    
    cat > "$OUTPUT_DIR/registries.yaml" << EOF
mirrors:
  "192.168.6.1:5000":
    endpoint:
      - "https://192.168.6.1:5000"
  "registry.k8s.io":
    endpoint:
      - "https://192.168.6.1:5000"
  "docker.io":
    endpoint:
      - "https://192.168.6.1:5000"
  "quay.io":
    endpoint:
      - "https://192.168.6.1:5000"
  "gcr.io":
    endpoint:
      - "https://192.168.6.1:5000"
  "kubesphere":
    endpoint:
      - "https://192.168.6.1:5000"
  "prom":
    endpoint:
      - "https://192.168.6.1:5000"
  "grafana":
    endpoint:
      - "https://192.168.6.1:5000"
  "bitnami":
    endpoint:
      - "https://192.168.6.1:5000"
  "rancher":
    endpoint:
      - "https://192.168.6.1:5000"

configs:
  "192.168.6.1:5000":
    tls:
      ca_file: /usr/local/share/ca-certificates/airgap-registry-ca.crt
      insecure_skip_verify: false
EOF
    
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
    
    check_prerequisites
    install_packages
    generate_certificates
    start_registry
    mirror_images
    download_k3s
    download_airgap_images
    generate_registries_config
    generate_ssh_keys
    
    log_success "오프라인 준비 완료"
    log_info "출력 디렉토리: $OUTPUT_DIR"
    log_info "레지스트리 URL: https://localhost:5000"
    log_info "SSH 개인키: $OUTPUT_DIR/ssh/id_rsa"
}

# 스크립트 실행
main "$@"
