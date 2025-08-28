#!/bin/bash
# 현재 환경에 맞는 환경 변수 설정
# 사용법: source env-config.sh

echo "🔧 현재 환경에 맞는 설정을 적용합니다..."

# VMware 네트워크 설정 (VMnet1 사용)
# WSL 환경에서도 VM 네트워크 IP 사용 (포트 포워딩을 통해 접근)
if [[ -f /proc/version ]] && grep -q Microsoft /proc/version; then
    # WSL 환경
    export REGISTRY_HOST_IP=192.168.6.1
    echo "   환경: WSL2 (192.168.6.1 사용 - 포트 포워딩 필요)"
elif [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSLENV" ]]; then
    # WSL 환경 (다른 방법으로 감지)
    export REGISTRY_HOST_IP=192.168.6.1
    echo "   환경: WSL2 (192.168.6.1 사용 - 포트 포워딩 필요)"
else
    # 일반 Linux 환경 (VM 등)
    export REGISTRY_HOST_IP=192.168.6.1
    echo "   환경: 일반 Linux (192.168.6.1 사용)"
fi
export REGISTRY_PORT=5000
export REGISTRY_FQDN=registry.local

# Kubernetes 네트워크 설정
export POD_CIDR=10.42.0.0/16
export SVC_CIDR=10.43.0.0/16

# VM IP 주소 설정 (VMnet1 대역 사용)
export MASTER_IP=192.168.6.10
export WORKER1_IP=192.168.6.11
export WORKER2_IP=192.168.6.12

# 네트워크 설정
export GATEWAY_IP=192.168.6.1
export DNS_IP=192.168.6.1

# k3s 버전
export K3S_VERSION=v1.33.4-rc1+k3s1

echo "✅ 환경 변수가 설정되었습니다:"
echo "   레지스트리: ${REGISTRY_HOST_IP}:${REGISTRY_PORT}"
echo "   마스터 IP: ${MASTER_IP}"
echo "   워커1 IP: ${WORKER1_IP}"
echo "   워커2 IP: ${WORKER2_IP}"
echo "   게이트웨이: ${GATEWAY_IP}"
echo "   Pod CIDR: ${POD_CIDR}"
echo "   Service CIDR: ${SVC_CIDR}"
echo ""
echo "📝 사용법:"
echo "   source scripts/env-config.sh"
echo "   cd wsl/scripts"
echo "   ./00_prep_offline.sh"
echo "   ./01_build_seed_isos.sh"
