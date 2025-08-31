# VM Registry URL 불일치 문제 해결

## 📋 작업 개요
VM에서 private registry의 이미지를 정상적으로 가져올 수 있도록 URL 불일치 문제를 해결했습니다.

## 🔍 문제 분석

### 발견된 문제점
1. **Registry URL 불일치**:
   - `registries.yaml`에서 `localhost:5000` 사용
   - VM에서는 `192.168.6.1:5000`으로 접근해야 함

2. **TLS 인증서 경로 불일치**:
   - 설정: `/etc/ssl/certs/airgap-registry-ca.crt`
   - 실제: `/usr/local/share/ca-certificates/airgap-registry-ca.crt`

## ✅ 해결 내용

### 1. registries.yaml 생성 스크립트 수정
**파일**: `wsl/scripts/00_prep_offline_fixed.sh`

**변경 사항**:
- `localhost:5000` → `192.168.6.1:5000`으로 변경
- TLS 인증서 경로를 실제 설치 경로로 수정

```yaml
# 수정 전
mirrors:
  "localhost:5000":
    endpoint:
      - "https://localhost:5000"
configs:
  "localhost:5000":
    tls:
      ca_file: /etc/ssl/certs/airgap-registry-ca.crt

# 수정 후
mirrors:
  "192.168.6.1:5000":
    endpoint:
      - "https://192.168.6.1:5000"
configs:
  "192.168.6.1:5000":
    tls:
      ca_file: /usr/local/share/ca-certificates/airgap-registry-ca.crt
```

### 2. 기존 registries.yaml 파일 업데이트
**파일**: `wsl/out/registries.yaml`

**변경 사항**:
- 모든 registry endpoint를 `192.168.6.1:5000`으로 통일
- TLS 인증서 경로 수정

### 3. VM Registry 접근 테스트 스크립트 생성
**파일**: `wsl/scripts/test-vm-registry-access.sh`

**기능**:
- VM SSH 연결 테스트
- Registry 접근 테스트 (`curl -k https://192.168.6.1:5000/v2/_catalog`)
- 특정 이미지 태그 조회 테스트
- k3s registry 설정 확인
- CA 인증서 존재 확인
- k3s 서비스 상태 확인

**사용법**:
```bash
# 마스터 노드 테스트 (기본값)
./wsl/scripts/test-vm-registry-access.sh

# 특정 VM 테스트
./wsl/scripts/test-vm-registry-access.sh 192.168.6.11
```

## 🔧 적용 방법

### 1. 새로운 VM 생성 시
```bash
# WSL에서 실행
cd wsl/scripts
./00_prep_offline_fixed.sh  # 수정된 registries.yaml 생성
./01_build_seed_isos.sh     # 새로운 ISO 생성
```

### 2. 기존 VM 업데이트 시
```bash
# VM에 접속하여 registries.yaml 수정
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.10

# registries.yaml 백업
sudo cp /etc/rancher/k3s/registries.yaml /etc/rancher/k3s/registries.yaml.backup

# 새로운 설정 적용
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null << 'EOF'
mirrors:
  "192.168.6.1:5000":
    endpoint:
      - "https://192.168.6.1:5000"
  "registry.k8s.io":
    endpoint:
      - "https://192.168.6.1:5000"
  # ... (전체 설정)
configs:
  "192.168.6.1:5000":
    tls:
      ca_file: /usr/local/share/ca-certificates/airgap-registry-ca.crt
      insecure_skip_verify: false
EOF

# k3s 재시작
sudo systemctl restart k3s
```

## 🧪 검증 방법

### 1. Registry 접근 테스트
```bash
# VM에서 직접 테스트
curl -k https://192.168.6.1:5000/v2/_catalog

# WSL에서 스크립트로 테스트
./wsl/scripts/test-vm-registry-access.sh
```

### 2. k3s 이미지 pull 테스트
```bash
# VM에서 k3s가 이미지를 pull할 수 있는지 확인
sudo k3s ctr images ls | grep -E "(k8s|kubesphere)"
```

### 3. Pod 생성 테스트
```bash
# 간단한 테스트 Pod 생성
kubectl run test-pod --image=192.168.6.1:5000/k8s/pause:3.10
kubectl get pods
```

## 📝 참고사항

- **Registry URL**: `https://192.168.6.1:5000` (VM에서 접근)
- **WSL 내부 URL**: `https://localhost:5000` (WSL 내부에서만 사용)
- **포트 포워딩**: Windows에서 WSL2로 포트 포워딩이 설정되어 있어야 함
- **TLS 인증서**: 자체 서명된 인증서 사용 (`-k` 옵션으로 무시 가능)

## 🚀 다음 단계

1. **새로운 VM 생성**: 수정된 설정으로 VM을 새로 생성
2. **기존 VM 업데이트**: 실행 중인 VM의 registry 설정 업데이트
3. **테스트 실행**: `test-vm-registry-access.sh` 스크립트로 검증
4. **k3s 클러스터 확인**: 이미지 pull 및 Pod 생성 테스트

---
**작성일**: 2024-12-29  
**상태**: 완료 ✅
