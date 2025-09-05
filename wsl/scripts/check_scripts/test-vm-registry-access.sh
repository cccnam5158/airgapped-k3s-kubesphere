#!/bin/bash

# VM에서 Registry 접근 테스트 스크립트
# 사용법: ./test-vm-registry-access.sh [VM_IP]

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

# 기본값 설정
REGISTRY_IP="${REGISTRY_HOST_IP:-192.168.6.1}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
SSH_KEY="${SSH_KEY:-./wsl/out/ssh/id_rsa}"

# VM IP 설정
if [ $# -eq 1 ]; then
    VM_IP="$1"
else
    # 기본값: 마스터 노드
    VM_IP="${MASTER_IP:-192.168.6.10}"
fi

log_info "VM Registry 접근 테스트 시작"
log_info "VM IP: $VM_IP"
log_info "Registry: $REGISTRY_IP:$REGISTRY_PORT"
log_info "SSH Key: $SSH_KEY"

# SSH 키 존재 확인
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH 키를 찾을 수 없습니다: $SSH_KEY"
    exit 1
fi

# SSH 키 권한 설정
chmod 600 "$SSH_KEY" 2>/dev/null || true

# 1. VM 연결 테스트
log_info "1. VM SSH 연결 테스트..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "echo 'SSH 연결 성공'" 2>/dev/null; then
    log_success "VM SSH 연결 성공"
else
    log_error "VM SSH 연결 실패"
    exit 1
fi

# 2. Registry 접근 테스트
log_info "2. Registry 접근 테스트..."
log_info "   curl -k https://$REGISTRY_IP:$REGISTRY_PORT/v2/_catalog"

REGISTRY_RESPONSE=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "curl -k -s https://$REGISTRY_IP:$REGISTRY_PORT/v2/_catalog" 2>/dev/null)

if [ -n "$REGISTRY_RESPONSE" ]; then
    log_success "Registry 접근 성공"
    
    # JSON 파싱 시도
    if echo "$REGISTRY_RESPONSE" | grep -q '"repositories"'; then
        IMAGE_COUNT=$(echo "$REGISTRY_RESPONSE" | grep -o '"repositories"' | wc -l)
        log_info "   이미지 개수: $IMAGE_COUNT"
        
        # 이미지 목록 출력
        echo "$REGISTRY_RESPONSE" | grep -o '"[^"]*"' | grep -v '"repositories"' | sed 's/"//g' | while read -r img; do
            if [ -n "$img" ]; then
                log_info "   - $img"
            fi
        done
    else
        log_warning "Registry 응답을 파싱할 수 없습니다"
        echo "응답: $REGISTRY_RESPONSE"
    fi
else
    log_error "Registry 접근 실패"
fi

# 3. 특정 이미지 태그 테스트
log_info "3. 특정 이미지 태그 테스트..."
TEST_IMAGES=("k8s/metrics-server" "kubesphere/ks-apiserver" "grafana/grafana")

for img in "${TEST_IMAGES[@]}"; do
    log_info "   테스트 이미지: $img"
    TAG_RESPONSE=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "curl -k -s https://$REGISTRY_IP:$REGISTRY_PORT/v2/$img/tags/list" 2>/dev/null)
    
    if [ -n "$TAG_RESPONSE" ] && ! echo "$TAG_RESPONSE" | grep -q '"errors"'; then
        log_success "   $img: 태그 조회 성공"
        # 태그 목록 출력 (최대 5개)
        echo "$TAG_RESPONSE" | grep -o '"[^"]*"' | grep -v '"name"' | grep -v '"tags"' | sed 's/"//g' | head -5 | while read -r tag; do
            if [ -n "$tag" ]; then
                log_info "     - $tag"
            fi
        done
    else
        log_warning "   $img: 태그 조회 실패 또는 이미지 없음"
    fi
done

# 4. k3s registry 설정 확인
log_info "4. k3s registry 설정 확인..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "sudo test -f /etc/rancher/k3s/registries.yaml" 2>/dev/null; then
    log_success "registries.yaml 파일 존재"
    
    # 설정 내용 확인
    log_info "   registries.yaml 내용:"
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "sudo cat /etc/rancher/k3s/registries.yaml" 2>/dev/null | while read -r line; do
        log_info "     $line"
    done
else
    log_error "registries.yaml 파일이 없습니다"
fi

# 5. CA 인증서 확인
log_info "5. CA 인증서 확인..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "sudo test -f /usr/local/share/ca-certificates/airgap-registry-ca.crt" 2>/dev/null; then
    log_success "CA 인증서 파일 존재"
else
    log_error "CA 인증서 파일이 없습니다"
fi

# 6. k3s 서비스 상태 확인
log_info "6. k3s 서비스 상태 확인..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$VM_IP" "sudo systemctl is-active k3s" 2>/dev/null | grep -q "active"; then
    log_success "k3s 서비스 실행 중"
else
    log_warning "k3s 서비스가 실행되지 않음"
fi

log_info "테스트 완료"
log_info "VM에서 registry 접근이 성공하면 k3s가 이미지를 정상적으로 pull할 수 있습니다."
