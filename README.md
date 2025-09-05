# 🚀 Airgapped Lab - VMware Workstation + k3s + KubeSphere

Windows 10/11 환경에서 VMware Workstation Pro를 사용하여 완전히 오프라인으로 k3s 클러스터와 KubeSphere를 구축하는 프로젝트입니다.

## 🎯 프로젝트 개요

이 프로젝트는 다음을 제공합니다:
- **완전 오프라인 환경**: 인터넷 연결 없이 모든 구성 요소 실행
- **자동화된 설정**: 스크립트 기반 자동 설치 및 구성
- **현재 환경 최적화**: Windows 10/11 + WSL2 + VMware Workstation 환경에 맞춤
- **최신 버전**: k3s v1.33.4-rc1, KubeSphere v4.1.3 사용
- **호환성 보장**: 안전한 버전 조합으로 안정성 확보
- **로컬 Docker 레지스트리**: 이미지 미러링을 통한 오프라인 지원

## 📚 목차

### 🚀 시작하기
- [프로젝트 개요](#-프로젝트-개요)
- [아키텍처](#-아키텍처)
- [실행 순서 요약](#-실행-순서-요약)
- [빠른 시작](#-빠른-시작)
- [사전 요구사항](#-사전-요구사항)

### 📖 사용 가이드
- [프로젝트 구조](#-프로젝트-구조)
- [접속 정보](#-접속-정보)
- [시간 동기화(중요)](#-시간-동기화중요)
- [구성 요소 버전](#-구성-요소-버전)
- [미러링된 이미지 목록](#-미러링된-이미지-목록)

### 🔧 운영 및 관리
- [WSL에서 kubectl로 VM 클러스터 접속하기](#wsl에서-kubectl로-vm-클러스터-접속하기)
- [VM 내부 패키지 설치 상태 점검](#-vm-내부-패키지-설치-상태-점검)
- [에어갭 환경 구성](#-에어갭-환경-구성)

### ⚠️ 문제 해결
- [문제 해결(트러블슈팅) 안내](#-문제-해결트러블슈팅-안내)
- [주의사항](#️-주의사항)
- [보안 및 안정성](#-보안-및-안정성)

### 📝 참고 정보
- [최근 변경사항](#-최근-변경사항)
- [관련 자료](#-관련-자료)
- [라이선스](#-라이선스)

## 🏗 아키텍처

- Windows Host에서 VMware Workstation에 1 Master + N Worker VM을 자동 설치(cloud-init autoinstall)하여 k3s + KubeSphere 클러스터를 구성합니다.
- WSL2는 Seed ISO 생성, 레지스트리, 인증서 생성 등 오프라인 자산을 제공합니다.
- SSH는 키 기반 인증만 허용합니다(`wsl/out/ssh/id_rsa`).
- 상세 플로우는 다음 문서를 참고하세요: `windows/setup-vm-process-diagram.md`

## 🧭 실행 순서 요약

1. 관리자 PowerShell에서 환경 검증 (`./scripts/check-env.ps1`)
2. WSL2 Ubuntu에서 오프라인 준비 (`wsl/scripts/00_prep_offline_fixed.sh`)
3. 관리자 PowerShell에서 포트 포워딩 설정 (`./scripts/setup-port-forwarding.ps1`)
4. WSL2 Ubuntu에서 Seed ISO 생성 (`wsl/scripts/01_build_seed_isos.sh`)
5. 관리자 PowerShell에서 VM 생성 (`./scripts/setup-vms.ps1`)
6. WSL2 Ubuntu에서 클러스터 확인 (`wsl/scripts/02_wait_and_config.sh`)

## 📁 프로젝트 구조

```
airgapped-k3s-kubesphere/
├── README.md                    # 메인 문서 (이 파일)
├── scripts/                     # Windows 실행 스크립트
│   ├── check-env.ps1           # 환경 검증 스크립트
│   ├── cleanup-vms.ps1         # VM 정리 스크립트
│   ├── setup-port-forwarding.ps1 # 포트 포워딩 설정
│   └── test-registry-access.ps1 # 레지스트리 접근 테스트
├── wsl/                        # WSL2 관련 파일
│   ├── scripts/                # WSL2 실행 스크립트
│   │   ├── 00_prep_offline_fixed.sh # 오프라인 준비 (이미지 미러링, 인증서 생성)
│   │   ├── 01_build_seed_isos.sh # Ubuntu 22.04.5 기반 Seed ISO 생성
│   │   ├── 02_wait_and_config.sh # 클러스터 확인 및 설정
│   │   ├── check-vm-packages.sh # VM 내부 패키지 설치 상태 점검
│   │   ├── fix-vm-packages.sh   # VM 내부 패키지 설치 문제 수동 복구
│   │   └── ops-packages/        # K8s 운영 패키지 다운로드 디렉토리 (자동 생성)
│   ├── templates/              # cloud-init 템플릿
│   │   ├── user-data-master.tpl # 마스터 노드 템플릿
│   │   └── user-data-worker.tpl # 워커 노드 템플릿
│   └── examples/               # 예제 파일
│       ├── images.txt          # 기본 이미지 목록
│       └── images-with-digests.txt # 다이제스트 포함 이미지 목록
└── windows/                    # Windows 관련 파일
    └── Setup-VMs.ps1          # VM 생성 PowerShell 스크립트
```

## 🔧 사전 요구사항

### Windows 환경
- **OS**: Windows 10 Pro/11 Pro (64비트)
- **VMware Workstation**: Pro 16+ 설치
- **WSL2**: Ubuntu 22.04 LTS 설치
- **관리자 권한**: PowerShell 실행 필요

### Ubuntu 22.04 LTS 정보
- **VM OS**: Ubuntu 22.04.5 LTS (Jammy Jellyfish)
- **아키텍처**: AMD64 (x86_64)
- **다운로드**: https://releases.ubuntu.com/22.04/
- **파일명**: `ubuntu-22.04.5-live-server-amd64.iso`
- **설치 방식**: Cloud-init 자동 설치 (수동 설치 불필요)

### 시스템 요구사항
- **메모리**: 최소 16GB (권장 32GB)
- **디스크**: 최소 20GB 여유 공간
- **CPU**: 가상화 지원 (Intel VT-x/AMD-V)

### 네트워크 설정
- **VMware 네트워크**: VMnet1 (192.168.6.0/24)
- **레지스트리**: 192.168.6.1:5000
- **마스터**: 192.168.6.10
- **워커들**: 192.168.6.11, 192.168.6.12

## 🚀 빠른 시작

### 1단계: 환경 검증

**관리자 권한으로 PowerShell 실행 후:**

```powershell
# 환경 검증
.\scripts\check-env.ps1

# 문제가 있다면 수동으로 해결
# WSL2, VMware Workstation, 관리자 권한 확인
```

> **참고**: 환경 문제는 수동으로 해결해야 합니다.

### 2단계: WSL2에서 오프라인 준비

```bash
# WSL2 Ubuntu 실행
wsl -d Ubuntu-22.04

# 오프라인 준비 스크립트 실행 (환경변수 자동 설정)
cd wsl/scripts
chmod +x 00_prep_offline_fixed.sh
./00_prep_offline_fixed.sh
```

> **🆕 개선사항**: 이제 환경변수가 자동으로 설정되므로 별도 설정 없이 바로 실행 가능합니다. 스크립트가 Nexus3 비밀번호를 입력 요청합니다.

### (선택) 외부(WSL) Nexus3 프라이빗 레지스트리 사용

WSL에서 docker로 실행 중인 Nexus3를 프라이빗 레지스트리로 사용할 수 있습니다. **환경변수는 자동으로 설정되므로** 별도 설정 없이 바로 실행 가능합니다.

#### 🚀 간단한 실행 방법 (권장)

```bash
# WSL 터미널에서 바로 실행
cd wsl/scripts
chmod +x 00_prep_offline_fixed.sh
./00_prep_offline_fixed.sh
```

스크립트가 자동으로 다음을 수행합니다:
- 환경변수 자동 설정 (기본값 사용)
- Nexus3 비밀번호 입력 요청 (기본값: `nam0941!@#`)
- 모든 설정 정보 출력

#### 🔧 수동 환경변수 설정 (고급 사용자)

기본값을 변경하고 싶은 경우에만 환경변수를 수동으로 설정하세요:

```bash
# WSL 터미널에서
export USE_EXTERNAL_REGISTRY=true
export EXTERNAL_REGISTRY_PUSH_HOST=localhost
export EXTERNAL_REGISTRY_PUSH_PORT=5000
export REGISTRY_USERNAME=admin
export REGISTRY_PASSWORD='<password>'
# VM이 접근할 Windows Host IP:Port (기본 192.168.6.1:5000)
export REGISTRY_HOST_IP=192.168.6.1
export REGISTRY_PORT=5000
# 셀프사인 인증서 환경이면 true (권장), CA 배포 시 false
export REGISTRY_TLS_INSECURE=true

bash wsl/scripts/00_prep_offline_fixed.sh
```

```powershell
# Windows(관리자)에서 포트 프록시 설정
.\u0063ipts\setup-port-forwarding.ps1 -RegistryIP 192.168.6.1 -Port 5000
```

#### ✅ 검증 방법

- WSL: `docker login localhost:5000` 성공, `curl -k https://localhost:5000/v2/` 200
- VM: `curl -k https://192.168.6.1:5000/v2/` 200
- k3s: 이미지 풀 오류 없이 파드가 Running

### 2.5단계: Windows 포트 포워딩 설정

**관리자 권한으로 PowerShell 실행 후:**

```powershell
# 포트 포워딩 설정 (WSL2와 VM 네트워크 간 연결)
.\scripts\setup-port-forwarding.ps1
```

### 3단계: Seed ISO 생성 (개선된 k8s 운영 도구 포함)

```bash
# WSL2 Ubuntu에서 Seed ISO 생성
cd wsl/scripts
chmod +x 01_build_seed_isos.sh
./01_build_seed_isos.sh
```

> **🆕 개선사항**: 이제 k8s 운영에 필요한 도구들(jq, htop, ethtool, iproute2, dnsutils, telnet, psmisc, sysstat, iftop, iotop, dstat, yq)이 자동으로 포함됩니다.

### 3단계: 시간 동기화 확인 (새로 추가)

VM과 WSL 간의 시간 차이를 해결하기 위해 시간 동기화를 확인합니다:

```bash
# WSL2에서 시간 동기화 진단 스크립트 실행
cd wsl/scripts
chmod +x time-sync-diagnose.sh
./time-sync-diagnose.sh
```

> **중요**: VM 생성 후 시간 차이가 발생하면 이 스크립트를 실행하여 동기화하세요.

> **중요**: 이 단계는 VM들이 WSL2의 레지스트리에 접근할 수 있도록 하는 필수 단계입니다.

**오프라인 준비 스크립트가 수행하는 작업:**
- 필요한 패키지 설치 (xorriso, isolinux, rsync, wget, genisoimage)
- 로컬 Docker 레지스트리 시작 (localhost:5000)
- 이미지 미러링 (26개 이미지)
- k3s 바이너리 다운로드 (v1.33.4-rc1+k3s1)
- 에어갭 이미지 다운로드 (636MB, 선택사항)
- SSH 키 생성
- TLS 인증서 생성
- registries.yaml 설정 파일 생성

### 3단계: VM 생성 (Ubuntu 22.04.5 LTS 자동 설치)

```bash
# WSL2에서 Ubuntu 22.04.5 기반 Seed ISO 생성
cd wsl/scripts
chmod +x 01_build_seed_isos.sh
./01_build_seed_isos.sh
```

**관리자 PowerShell에서:**

```powershell
# VM 생성 및 부팅
.\scripts\setup-vms.ps1
```

### 3.5단계: VM 상태 점검 (선택사항)

VM이 정상적으로 생성되었는지 확인하려면 점검 스크립트를 사용하세요:

```powershell
# 모든 VM 점검
.\scripts\check-vm-health.ps1

# 특정 VM만 점검
.\scripts\check-vm-health.ps1 -VmName k3s-master1

# SSH 키 경로 지정
.\scripts\check-vm-health.ps1 -SshKeyPath "..\wsl\out\ssh\id_rsa"
```

**점검 항목:**
- 시스템 정보 (OS, 커널, 리소스)
- 네트워크 연결 (인터페이스, IP, 게이트웨이, DNS)
- 필수 서비스 상태 (SSH, systemd)
- 필수 디렉토리 및 파일 존재
- Cloud-init 초기화 상태
- SSH 키 설정
- Docker/K3s 관련 확인
- 시스템 건강 상태

> **참고**: jq 등 외부 명령어 없이 기본 Linux 명령어만으로 점검합니다.

### 4단계: 클러스터 확인 및 WSL kubectl 설정

```bash
# WSL2에서 실행
cd wsl/scripts
chmod +x 02_wait_and_config.sh
./02_wait_and_config.sh
```

**이 스크립트가 수행하는 작업:**
- VM들의 SSH 연결 확인
- k3s 서비스 상태 점검
- 클러스터 노드 및 파드 상태 확인
- **WSL에서 kubectl 접속 자동 설정** (새로 추가)
  - kubeconfig 파일 다운로드
  - 서버 주소 자동 수정
  - TLS 인증서 문제 자동 해결
  - WSL에서의 kubectl 접속 테스트

> **참고**: Ubuntu 22.04.5 LTS는 Cloud-init를 통해 자동으로 설치되므로 수동 설치가 필요하지 않습니다.

## 🕒 시간 동기화(중요)

오프라인/에어갭 환경에서 NTP를 사용할 수 없고, VM 설치 직후 WSL과 시간 차이가 크면 k3s/kubectl, 레지스트리 TLS에서 x509 오류가 발생할 수 있습니다. 이를 방지하기 위해 다음이 추가되었습니다.

- VM 부팅 시 `sync-time.service`가 실행되어 아래 순서로 시간을 맞춥니다.
  1) `https://192.168.6.1:5000/v2/`의 HTTP Date 헤더(WSL 레지스트리)로 시간 설정
  2) 위가 불가능하면 ISO에 포함된 `files/build-timestamp`(WSL에서 ISO 생성 시각)로 시간 설정
  - 설정 후 `hwclock --systohc`로 하드웨어 클록 저장
- `k3s-bootstrap.service`/`k3s-agent-bootstrap.service`는 `sync-time.service` 이후 실행되도록 의존성이 추가되었습니다.

수동으로 재동기화가 필요하면 (WSL에서):

```bash
wsl -d Ubuntu-22.04
cd wsl/scripts
./sync-time-k3s.sh
```

> 중요: 포트 포워딩이 설정되지 않은 상태라도 `build-timestamp` 폴백으로 인증서 유효기간 문제를 회피합니다. 가능하면 2.5단계(포트 포워딩)를 먼저 수행하세요.

## 📊 미러링된 이미지 목록

### Kubernetes Core (4개)
- `registry.k8s.io/metrics-server/metrics-server:v0.7.2`
- `registry.k8s.io/coredns/coredns:v1.11.1`
- `registry.k8s.io/pause:3.10`
- `registry.k8s.io/kube-proxy:v1.33.4`

### KubeSphere Core (2개)
- `kubesphere/ks-apiserver:v4.1.3`
- `kubesphere/ks-controller-manager:v4.1.3`

### Monitoring (3개)
- `kubesphere/notification-manager-operator:v2.5.0`
- `kubesphere/notification-manager:v2.5.0`
- `kubesphere/fluent-bit:v3.0.4`

### Prometheus Stack (2개)
- `prom/prometheus:v2.53.5`
- `prom/alertmanager:v0.27.0`

### Grafana (1개)
- `grafana/grafana:10.4.1`

### Rancher Mirrored (4개)
- `rancher/mirrored-pause:3.10`
- `rancher/mirrored-coredns-coredns:1.11.1`
- `rancher/mirrored-metrics-server:v0.7.2`
- `rancher/mirrored-cluster-proportional-autoscaler:v1.9.0`

### Additional (2개)
- `bitnami/kubectl:1.30.3`
- `quay.io/brancz/kube-rbac-proxy:v0.15.0`

**총 26개 이미지 미러링 완료**

## 🌐 접속 정보

### SSH 접속 (키 기반 인증만 지원)
```bash
# 마스터 노드
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.10

# 워커 노드들
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.11
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.12

# ⚠️ 주의: 패스워드 인증은 비활성화되어 있습니다. SSH 키만 사용 가능합니다.
```

### KubeSphere 콘솔
- **URL**: http://192.168.6.10:30880
- **계정**: admin
- **비밀번호**: P@88w0rd

### kubectl 사용
```bash
# 마스터 노드에서
kubectl get nodes -o wide
kubectl get pods -A
```

### WSL에서 kubectl로 VM 클러스터 접속하기

WSL 터미널에서 직접 `kubectl`로 VM의 k3s API에 접속하려면 아래 절차를 따르세요.

#### 1단계: kubeconfig 다운로드 및 설정

```bash
# 키 경로 설정
SSH_KEY=./wsl/out/ssh/id_rsa
KCFG_DIR=./wsl/out/kubeconfigs
mkdir -p "$KCFG_DIR"

# SSH 호스트 키 문제 해결 (VM 재생성 시 필요)
ssh-keygen -f "/home/ubuntu/.ssh/known_hosts" -R "192.168.6.10" 2>/dev/null || true

# 마스터에서 kubeconfig 복사
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@192.168.6.10:/etc/rancher/k3s/k3s.yaml "$KCFG_DIR/k3s.yaml"

# 권한 설정
chmod 600 "$KCFG_DIR/k3s.yaml"

# 서버 주소를 VM IP로 변경 (기본값이 127.0.0.1이므로)
sed -i 's/127.0.0.1/192.168.6.10/g' "$KCFG_DIR/k3s.yaml"
```

#### 2단계: API 서버 접속 방법 선택

**방법 A: 직접 접속 (권장)**

```bash
# 환경변수 설정
export KUBECONFIG="$KCFG_DIR/k3s.yaml"

# 연결 테스트
kubectl get nodes -o wide
```

**방법 B: SSH 포트포워딩 (방화벽 문제 시)**

```bash
# 새 터미널에서 SSH 포워딩 실행
ssh -i "$SSH_KEY" -L 6443:127.0.0.1:6443 ubuntu@192.168.6.10

# 다른 터미널에서 localhost로 접속
sed 's#server: https://.*:6443#server: https://127.0.0.1:6443#' "$KCFG_DIR/k3s.yaml" > "$KCFG_DIR/k3s.local.yaml"
export KUBECONFIG="$KCFG_DIR/k3s.local.yaml"
kubectl get nodes -o wide
```

**방법 C: Windows 포트 프록시 (지속적)**

```powershell
# 관리자 PowerShell에서 실행
netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=6443
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=6443 connectaddress=192.168.6.10 connectport=6443
netsh advfirewall firewall add rule name="Allow k3s 6443 TCP" dir=in action=allow protocol=TCP localport=6443
```

```bash
# WSL에서 localhost로 접속
sed 's#server: https://.*:6443#server: https://127.0.0.1:6443#' "$KCFG_DIR/k3s.yaml" > "$KCFG_DIR/k3s.local.yaml"
export KUBECONFIG="$KCFG_DIR/k3s.local.yaml"
kubectl get nodes -o wide
```

#### 3단계: 문제 해결

**TLS 인증서 오류 발생 시:**

```bash
# 방법 1: 인증서 검증 우회 (임시)
kubectl --insecure-skip-tls-verify get nodes

# 방법 2: CA 인증서 설정 (권장)
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@192.168.6.10:/usr/local/share/ca-certificates/airgap-registry-ca.crt ~/
sudo cp ~/airgap-registry-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# 방법 3: 시간 동기화 (시간 차이로 인한 인증서 오류)
cd wsl/scripts
./time-sync-diagnose.sh
```

**SSH 연결 오류 시:**

```bash
# SSH 키 권한 확인
chmod 600 "$SSH_KEY"

# SSH 연결 테스트
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@192.168.6.10 "echo 'SSH OK'"
```

#### 4단계: 영구 설정 (선택사항)

```bash
# ~/.bashrc에 환경변수 추가
echo 'export KUBECONFIG=./wsl/out/kubeconfigs/k3s.yaml' >> ~/.bashrc
echo 'alias kubectl="kubectl --insecure-skip-tls-verify"' >> ~/.bashrc

# 설정 적용
source ~/.bashrc
```

#### 5단계: 실제 문제 해결 사례 (2024-12-19)

사용자가 실제로 겪은 TLS 인증서 오류와 SSH 호스트 키 문제 해결 과정:

```bash
# 1. TLS 인증서 오류 발생
export KUBECONFIG=~/.kube/config-k3s && kubectl get nodes
# 결과: Unable to connect to the server: tls: failed to verify certificate: x509: certificate signed by unknown authority

# 2. SSH 호스트 키 문제 해결 (VM 재생성 시 필요)
ssh-keygen -f "/home/ubuntu/.ssh/known_hosts" -R "192.168.6.10"
sed -i '/192.168.6.10/d' ~/.ssh/known_hosts

# 3. 새로운 kubeconfig 파일 다운로드
scp -o StrictHostKeyChecking=no -i ~/.ssh/airgap_k3s ubuntu@192.168.6.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config-k3s

# 4. 서버 주소 수정 (127.0.0.1 → 192.168.6.10)
sed -i 's/127.0.0.1/192.168.6.10/g' ~/.kube/config-k3s

# 5. 연결 테스트 성공
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
# 결과: 정상적으로 노드 목록 출력
```

**주요 해결 포인트:**
- **SSH 호스트 키 초기화**: VM 재생성 시 기존 호스트 키 제거
- **StrictHostKeyChecking=no**: 첫 연결 시 호스트 키 검증 건너뛰기
- **서버 주소 수정**: k3s.yaml의 기본값 127.0.0.1을 실제 VM IP로 변경
- **TLS 인증서**: k3s의 자체 서명 인증서는 포함된 CA로 검증됨

### 참고사항
- k3s의 `k3s.yaml`에는 CA/클라이언트 인증서가 포함되어 있으므로 별도 인증서 설치가 필요 없습니다.
- 시간 차이로 x509 오류가 나면 VM 부팅 시 자동 동기화되지만, 수동으로는 WSL에서 `wsl/scripts/sync-time-k3s.sh`를 실행하세요.
- `02_wait_and_config.sh` 스크립트가 자동으로 WSL에서의 kubectl 접속도 검증합니다.
- **VM 재생성 시 주의**: SSH 호스트 키가 변경되므로 known_hosts에서 해당 IP를 제거해야 합니다.

### TLS SAN 자동 설정 (인증서 오류 방지)

VM 마스터 노드의 k3s API 서버 인증서가 IP로 접근할 때 신뢰될 수 있도록 `tls-san`이 자동으로 설정됩니다.

- 적용 대상: `wsl/templates/user-data-master.tpl`
- 내용: 설치 시 `/etc/rancher/k3s/config.yaml`에 아래가 생성되고, k3s 서버 실행 옵션에도 동일 SAN이 반영됩니다.

```yaml
tls-san:
  - 192.168.6.10
  - 127.0.0.1
  - localhost
```

또한 서버 실행 시 다음 옵션이 자동 포함됩니다:

```bash
k3s server --tls-san 192.168.6.10 --tls-san 127.0.0.1 --tls-san localhost ...
```

이로 인해 WSL에서 `scp`로 가져온 `k3s.yaml`의 `server: https://192.168.6.10:6443`를 그대로 사용해도 `x509: certificate signed by unknown authority` 오류가 발생하지 않습니다.

## 🔧 구성 요소 버전

| 구성 요소 | 버전 | 설명 |
|----------|------|------|
| k3s | v1.33.4-rc1+k3s1 | 경량 Kubernetes (RC) |
| KubeSphere | v4.1.3 | 컨테이너 플랫폼 |
| Ubuntu | 22.04.5 LTS | VM OS (Jammy Jellyfish) |
| Docker Registry | 2.8.1 | 프라이빗 레지스트리 |

### 주요 업데이트 (v2.2)
- **Ubuntu**: 22.04.3 LTS → 22.04.5 LTS (최신 패치)
- **k3s**: v1.30.5 → v1.33.4-rc1 (최신 RC 버전)
- **KubeSphere**: v3.4.2 → v4.1.3 (1.33 계열 호환)
- **ISO 생성 방식**: genisoimage → xorriso (Ubuntu ISO 기반)
- **IP 주소**: 192.168.100.x → 192.168.6.x (네트워크 통일)
- **metrics-server**: v0.7.1 → v0.7.2 (최신 패치)
- **coredns**: v1.11.1 → v1.12.3 (최신 안정 버전)
- **pause**: 3.9 → 3.10 (최신 샌드박스)
- **kube-proxy/kubectl**: 클러스터와 동일 버전 (v1.33.4-rc1)

### 변경 사항 요약 (cloud-init/k3s 자동 구성 안정화)
- **Autoinstall 신뢰성 향상**: GRUB 커널 파라미터 `autoinstall ds=nocloud\;s=/cdrom/autoinstall/`를 `grub.cfg`와 `loopback.cfg` 모두에 주입하여 UEFI/BIOS 모두에서 자동 설치가 보장됩니다.
- **BIOS+UEFI 하이브리드 부팅**: xorriso 옵션 정비(`-eltorito-alt-boot`, `-isohybrid-mbr`, `-isohybrid-gpt-basdat`).
- **시드 파일 영구 보관**: 설치 중 `late-commands`에서 `/cdrom/files` → `/target/usr/local/seed`로 복사. 부팅 후 스크립트는 `/usr/local/seed`를 우선 사용, 없을 때만 CD 마운트로 폴백.
- **부트스트랩 서비스 도입**: `k3s-bootstrap.service`(마스터), `k3s-agent-bootstrap.service`(워커). runcmd에서 즉시 실행하며 로그를 남기고, 서비스는 실패/재부팅 시 재시도하도록 enable.
  - 로그 경로: 마스터 `/var/log/k3s-bootstrap.log`, 워커 `/var/log/k3s-agent-bootstrap.log`
  - 멱등 플래그: `/var/lib/k3s-bootstrap.done`, `/var/lib/k3s-agent-bootstrap.done`
- **APT 지연 제거**: early-commands에서 APT 소스 주석 처리(네트워크 미사용), 타임아웃/재시도 값 축소. 파일 미존재 시에도 성공하도록 null-safe 처리.
- **네트워크 매칭 완화**: Netplan `match.name: "e*"` + `optional: true`로 다양한 NIC 이름(예: `enp0s16`, `ens160`) 대응.
- **k3s 설치 스크립트 보강**:
  - `k3s` 바이너리 이름이 변형(`k3s*`)되어도 자동 탐지/설치
  - 컨테이너 이미지 import는 k3s/agent 기동 후로 이동(중단 방지)
  - cloud-init 템플릿의 brace 확장 보존을 위해 `${DOLLAR}{1..30}` 사용
- **클러스터 확인 스크립트 개선(02_wait_and_config.sh)**:
  - `SSH_KEY`가 `/mnt/*`에 있으면 자동으로 `~/.ssh/airgap_k3s`로 복사(퍼미션 600)
  - k3s 상태 점검을 서비스/프로세스/6443 포트/부트스트랩 실패까지 포괄
  - `kubectl` 탐색을 최대 5분간 재시도
- **콘솔 자동 로그인**: `tty1`/`ttyS0`에서 `ubuntu` 자동 로그인(SSH는 여전히 키 기반만 허용)

### K8s 운영 패키지 설치 개선 (v2.3)
- **의존성 패키지 자동 다운로드**: jq(libjq1), sysstat(libsensors5) 등 의존성 패키지들을 ISO 생성 시 자동으로 포함
- **설치 순서 최적화**: 의존성 패키지를 먼저 설치한 후 주요 패키지 설치
- **2단계 의존성 해결**: 1차(의존성 설치 후), 2차(주요 패키지 설치 후) 의존성 문제 해결
- **설치 성공률 모니터링**: 설치 완료 후 성공률을 계산하여 마커 파일에 기록
- **APT 설정 강화**: 인증되지 않은 패키지 설치 허용 및 다운그레이드 허용 설정 추가
- **상세 로깅**: 설치 과정의 각 단계별 상세 로그 생성 및 journald 연동

> 부팅 후 빠른 점검
```bash
# 마스터
sudo tail -n 200 /var/log/k3s-bootstrap.log
ss -lntp | grep 6443 || true
sudo /usr/local/bin/k3s kubectl get nodes -o wide || true

# 워커
sudo tail -n 200 /var/log/k3s-agent-bootstrap.log
pgrep -a k3s || true
```

## 🔍 VM 내부 패키지 설치 상태 점검

VM 내부에서 K8s 운영 패키지(jq, htop, ethtool 등)가 제대로 설치되었는지 확인하고 문제를 진단할 수 있는 스크립트가 제공됩니다.

### 점검 스크립트 사용법

VM 내부에서 실행:

```bash
# 기본 점검
sudo ./check-vm-packages.sh

# 상세 출력과 함께 점검
sudo ./check-vm-packages.sh --verbose

# 자동 수정 시도
sudo ./check-vm-packages.sh --auto-fix

# 상세 보고서 생성
sudo ./check-vm-packages.sh --report

# 모든 옵션 사용
sudo ./check-vm-packages.sh --verbose --auto-fix --report
```

### 수동 복구 스크립트 사용법

패키지 설치에 문제가 있을 경우:

```bash
# 기본 복구 (확인 후 실행)
sudo ./fix-vm-packages.sh

# 강제 복구 (확인 없이 실행)
sudo ./fix-vm-packages.sh --force

# 상세 출력과 함께 복구
sudo ./fix-vm-packages.sh --verbose

# 백업 생성을 건너뛰고 복구
sudo ./fix-vm-packages.sh --skip-backup
```

### 점검 항목

1. **시스템 기본 정보**: OS, 커널, 메모리, 디스크 등
2. **cloud-init 실행 상태**: 로그 파일, 완료 마커 확인
3. **K8s 운영 패키지 서비스**: systemd 서비스 상태 점검
4. **Seed 파일 및 패키지 디렉토리**: 설치 파일 존재 여부 확인
5. **개별 패키지 설치 상태**: jq, htop, ethtool 등 8개 필수 패키지
6. **dpkg 상태**: 패키지 관리자 상태 점검
7. **네트워크 및 시스템 설정**: APT 소스, 서비스 상태 등
8. **문제 진단**: 설치 실패 원인 분석 및 해결 방안 제시
9. **자동 수정**: 간단한 문제 자동 해결 시도
10. **결과 요약**: 설치 성공률 및 상세 보고서 생성

### 복구 기능

1. **사전 점검**: 권한, 디스크 공간 등 확인
2. **백업 생성**: 기존 상태 보존
3. **설치 파일 검증**: Seed 디렉토리, 압축 파일, 스크립트 확인
4. **기존 설치 정리**: 이전 설치 상태 정리
5. **패키지 설치 실행**: 수동 설치 스크립트 실행
6. **설치 결과 확인**: 개별 패키지 설치 상태 검증
7. **시스템 서비스 복구**: 관련 서비스 상태 복구
8. **최종 점검**: 설치 성공률 및 보고서 생성

> 검증 스크립트 실행 시 키 지정 예시
```bash
SSH_KEY=~/.ssh/airgap_k3s ./wsl/scripts/02_wait_and_config.sh
```

## ⚠️ 주의사항

### 필수 요구사항
1. **관리자 권한**: PowerShell은 반드시 관리자 권한으로 실행
2. **VMware PATH**: vmrun 명령어 사용을 위해 PATH 설정 필요
3. **WSL2**: Ubuntu WSL2가 정상 실행 중
4. **디스크 공간**: C: 드라이브에 최소 20GB 이상 여유 공간

### 문제 해결

#### 환경 문제 해결
```powershell
# 관리자 권한으로 PowerShell 실행 후
# WSL2, VMware Workstation, 관리자 권한 확인
.\scripts\check-env.ps1
```

#### WSL2 문제
```powershell
# WSL2 재시작
wsl --shutdown
wsl -d Ubuntu-22.04

# WSL2 설치 확인
wsl --list --verbose

# Ubuntu 설치
wsl --install -d Ubuntu
```

#### WSL 환경 패키지 문제
```bash
# WSL에서 실행
cd wsl/scripts
chmod +x 00_prep_offline_fixed.sh
./00_prep_offline_fixed.sh

# 필요한 패키지들이 자동으로 설치됩니다
```

#### 레지스트리 접근 문제
VM들이 WSL2의 레지스트리에 접근할 수 없는 경우:

```powershell
# 관리자 권한으로 PowerShell 실행 후
.\scripts\setup-port-forwarding.ps1
```

**문제 해결 순서:**
1. 레지스트리 접근 테스트: `.\scripts\test-registry-access.ps1`
2. WSL2에서 레지스트리가 실행 중인지 확인: `docker ps | grep registry`
3. Windows 포트 포워딩 설정: `.\scripts\setup-port-forwarding.ps1`
4. VM에서 레지스트리 접근 테스트: `curl -k https://192.168.6.1:5000/v2/_catalog`

#### Ubuntu 자동설치(autoinstall) 시 언어 선택 화면이 나오는 경우 (해결 기록)

다음 증상은 Subiquity(UI)로 언어 선택 화면이 표시되어 자동 설치가 진행되지 않는 문제입니다. 본 저장소에서는 아래와 같이 수정하여 해결했습니다.

**증상**
- 부팅 시 언어 선택 화면 노출
- `/proc/cmdline`에 `autoinstall`이 있으나 동작하지 않음
- `/var/log/installer/subiquity-server-debug.log`에 `skipping Locale/Keyboard ... as interactive` 로그 출력
- `cloud-init status --long`에 `Failed loading yaml blob ... could not find expected ':'` 또는 `Unhandled non-multipart userdata` 경고

**원인**
- GRUB에서 `ds=nocloud;s=...`의 세미콜론(;)이 명령 구분자로 해석되어 커널 파라미터가 잘려 전달됨
- 실제로는 `boot/grub/loopback.cfg`가 사용되지만 `grub.cfg`만 수정해 파라미터가 누락됨
- `user-data` YAML에 멀티라인 인증서(PEM)를 인라인으로 넣어 YAML 파서 오류 발생

**해결 방법**
1. 커널 파라미터를 모든 부팅 엔트리(UEFI/BIOS, grub.cfg/loopback.cfg)에 주입하고 `---` 앞에 위치시킴
   - `autoinstall ds=nocloud\;s=/cdrom/autoinstall/ console=ttyS0,115200 console=tty0 ---`
   - 세미콜론은 반드시 `\;`로 이스케이프
2. `wsl/scripts/01_build_seed_isos.sh`의 GRUB 수정 로직 보강
   - `boot/grub/grub.cfg`, `boot/grub/loopback.cfg` 모두에 적용
   - `isolinux/isolinux.cfg`, `isolinux/txt.cfg`의 `append` 라인에도 동일 파라미터 반영(가능한 경우)
3. cloud-init 템플릿 구조 정리
   - `autoinstall:` 루트 아래에 설치 설정 배치, cloud-init 실행 항목은 `autoinstall.user-data:` 하위로 이동
   - `#cloud-config` 헤더 유지(Autoinstall + user-data 혼합 시 subiquity가 정상 인식)
4. YAML 파싱 오류 제거
   - 인증서(PEM)는 `write_files` 인라인을 제거하고, 설치 스크립트가 CD에서 복사하도록 변경

**검증 체크리스트**
- GRUB 편집 화면에서 커널 라인: `... vmlinuz ... autoinstall ds=nocloud\;s=/cdrom/autoinstall/ ... ---`
- `cat /proc/cmdline`에 위 문자열 그대로 포함
- `/cdrom/autoinstall/user-data`의 첫 줄이 `#cloud-config`
- `cloud-init status --long`에 YAML 경고가 없음

이 변경들은 `wsl/scripts/01_build_seed_isos.sh`, `wsl/templates/user-data-*.tpl`에 반영되어 있습니다.

#### VMware/vmrun 문제
```powershell
# PATH 추가 (임시)
$env:PATH += ";C:\Program Files (x86)\VMware\VMware Workstation\bin"

# PATH 추가 (영구)
[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\Program Files (x86)\VMware\VMware Workstation\bin", "Machine")

# vmrun 확인
vmrun -T ws list
```

##### vmrun 인자 순서 호환성(워크어라운드)
일부 환경에서 `vmrun`이 게스트 명령 실행 시 인증 플래그의 위치를 엄격히 해석하지 못하는 문제가 보고되었습니다. 본 프로젝트 스크립트(`windows/Setup-VMs.ps1`)는 다음 두 가지 양식을 모두 시도하고, 최초 성공한 양식을 캐시하여 이후 호출에 재사용합니다.

1) 표준 양식(권장): 인증 플래그가 명령 앞에 위치

```powershell
vmrun -T ws -gu <guestUser> -gp <guestPassword> runProgramInGuest "C:\path\vm.vmx" "/bin/echo" test
```

2) 대체 양식(워크어라운드): 명령 뒤에 인증 플래그를 배치

```powershell
vmrun -T ws runProgramInGuest "C:\path\vm.vmx" -gu <guestUser> -gp <guestPassword> "/bin/echo" test
```

추가로, 게스트 명령이 모두 실패할 경우에는 VMware Tools 상태, 게스트 IP(`getGuestIPAddress -wait`), SSH(포트 22 응답/키 기반 접속) 등의 신호를 기반으로 준비/완료 상태를 판정합니다.

##### SSH 폴백 완료 판정 파싱 오류(워크어라운드)
일부 환경에서 Windows PowerShell → `ssh.exe` → `bash -lc`로 명령이 전달될 때, if/then/fi 구문이 인용 경계 문제로 파싱 오류를 일으켜 완료 판정이 실패할 수 있습니다.

- 증상: `bash: -c: line 1: syntax error near unexpected token 'then'`
- 원인: 다중 레이어 인용 처리에서 if 블록이 깨짐
- 해결: if 블록 대신 안전한 one-liner를 사용

```bash
# 변경 전 (권장하지 않음)
if [ -f /var/lib/iso-copy-complete ] || [ -f /var/lib/cloud-init-complete ] || [ -f /var/lib/k3s-bootstrap.done ] || [ -f /var/lib/k3s-agent-bootstrap.done ]; then echo STATE_COMPLETE; else echo STATE_INCOMPLETE; fi

# 변경 후 (권장)
test -f /var/lib/iso-copy-complete || test -f /var/lib/cloud-init-complete || test -f /var/lib/k3s-bootstrap.done || test -f /var/lib/k3s-agent-bootstrap.done && echo STATE_COMPLETE || echo STATE_INCOMPLETE
```

본 변경은 `windows/Setup-VMs.ps1`에 반영되어 있으며, vmrun 게스트 명령이 불가능한 환경에서도 SSH 폴백으로 안정적으로 완료 여부를 확인할 수 있습니다.

#### 권한 문제
```powershell
# 관리자 권한으로 PowerShell 실행
# 또는 실행 정책 변경
Set-ExecutionPolicy Bypass -Scope Process -Force
```

#### 환경 검증
```powershell
# 환경 상태 확인
.\scripts\check-env.ps1
```

#### 줄바꿈 문자 문제
Windows에서 생성된 텍스트 파일을 Linux/WSL에서 읽을 때 발생하는 문제입니다.

**증상:**
```
Error parsing reference: "localhost:5000/k8s/metrics-server:v0.7.2\r" is not a valid repository/tag
```

**해결책:**
- `00_prep_offline_fixed.sh` 스크립트에 줄바꿈 문자 제거 로직이 포함되어 있습니다
- `tr -d '\r'` 명령어로 Windows CRLF 문자를 제거합니다

#### 시간 동기화 문제 (VM과 WSL 간 3시간 차이)

VM과 WSL 간에 3시간의 시간 차이가 발생하는 문제입니다. 이는 한국 표준시(KST)와 UTC 간의 차이로 인한 것입니다.

**증상:**
- VM의 시간이 WSL보다 3시간 빠름 또는 늦음
- 로그 타임스탬프가 일치하지 않음
- 인증서 만료 시간 계산 오류

**해결책:**
1. **자동 해결**: VM 생성 시 자동으로 시간 동기화가 수행됩니다
2. **수동 해결**: 시간 차이가 발생하면 다음 스크립트를 실행하세요:

```bash
# WSL2에서 시간 동기화 진단 및 수정
cd wsl/scripts
chmod +x time-sync-diagnose.sh
./time-sync-diagnose.sh
```

**개선사항:**
- WSL 호스트 시간과 동기화하는 로직 추가
- Windows 호스트 시간을 직접 가져오는 기능
- 부팅 시간 기반 시간 계산
- 타임존을 Asia/Seoul로 명시적 설정
- 하드웨어 클록을 UTC로 설정

#### 이미지 Pull 실패
일부 이미지는 접근 권한이나 존재하지 않는 문제로 실패할 수 있습니다.

**실패한 이미지들:**
- `kubesphere/ks-console:v4.1.3`
- `kubesphere/ks-installer:v4.1.3`
- `prom/prometheus-operator:v0.70.0`
- `sig-storage/*` (CSI 관련 이미지들)

**해결책:**
- 현재 미러링된 이미지들로 코어 컴포넌트 설치
- 확장 컴포넌트는 나중에 개별 설치

<!-- 실행 순서 요약은 상단 '🧭 실행 순서 요약' 섹션으로 이동했습니다. -->

## 🧩 문제 해결(트러블슈팅) 안내

### 재부팅 시 설치가 다시 진행되는 문제(해결)

### 증상
- VM을 재부팅하면 Ubuntu 설치가 다시 시작되거나 cloud-init autoinstall 화면으로 진입함
- VM 재시작 시 cloud-init이 반복적으로 실행되어 불필요한 재설치 시도

### 원인
- VM의 부팅 순서가 `cdrom,disk`로 설정되어 있어, 설치가 끝난 뒤에도 Seed ISO가 연결된 상태에서 CD가 먼저 부팅됨
- Seed ISO에는 `autoinstall ds=nocloud\;s=/cdrom/autoinstall/` 커널 파라미터가 포함되어 있어 매 부팅 시 설치가 재시작됨
- cloud-init의 idempotency가 제대로 보장되지 않아 매번 실행 시마다 모든 설정을 다시 적용

### 조치 사항 (프로젝트 반영)
- `windows/Setup-VMs.ps1`에서 부팅 순서를 `disk,cdrom`으로 변경하여, 설치 완료 후에는 디스크가 우선 부팅되도록 수정했습니다.
- BIOS PXE 부팅은 비활성화 상태를 유지합니다.
- **cloud-init idempotency 개선**: 각 설정 단계마다 완료 표시 파일을 생성하여 중복 실행을 방지합니다.

### Cloud-init Idempotency 개선 (2024-12-19)
각 설정 단계가 한 번만 실행되도록 완료 표시 파일을 사용합니다:

```bash
# 완료 표시 파일들 (VM 내부에서 확인)
ls -la /var/lib/cloud-init-complete          # Cloud-init 전체 완료
ls -la /var/lib/timezone-set                 # 타임존 설정 완료
ls -la /var/lib/sync-time-enabled            # 시간 동기화 완료
ls -la /var/lib/ca-certificates-updated      # CA 인증서 업데이트 완료
ls -la /var/lib/swap-disabled                # 스왑 비활성화 완료
ls -la /var/lib/sysctl-applied               # sysctl 설정 완료
ls -la /var/lib/hostname-set                 # 호스트명 설정 완료
ls -la /var/lib/kernel-modules-loaded        # 커널 모듈 로드 완료
ls -la /var/lib/k3s-bootstrap.done           # K3s 마스터 부트스트랩 완료
ls -la /var/lib/k3s-agent-bootstrap.done     # K3s 워커 부트스트랩 완료
ls -la /var/lib/autologin-configured         # 자동 로그인 설정 완료
ls -la /var/lib/kubectl-alias-created        # kubectl 별칭 생성 완료
ls -la /var/lib/ssh-restarted                # SSH 재시작 완료
```

### 이미 생성된 VM에 대한 워크어라운드
1) VMware Workstation에서 각 VM의 설정을 열고, CD/DVD 장치의 `연결됨(Connected)` 체크를 해제하거나 ISO 연결을 제거합니다.
2) VM 설정의 부팅 순서를 디스크 우선으로 변경합니다(가능한 경우). 또는 다음 `.vmx` 항목을 확인/수정합니다:

```text
bios.bootOrder = "disk,cdrom"
```

3) 재부팅 후에도 설치가 재시작되면, VM 콘솔에서 다음 파일 유무로 멱등 플래그를 확인하세요.

```bash
# 마스터
ls -l /var/lib/k3s-bootstrap.done || true

# 워커
ls -l /var/lib/k3s-agent-bootstrap.done || true
```

파일이 존재하면 설치 스크립트는 재실행되지 않습니다. 파일이 없다면 최초 설치가 완료되지 않은 상태일 수 있으므로 `sudo tail -n 200 /var/log/k3s-bootstrap.log`(마스터) 또는 `/var/log/k3s-agent-bootstrap.log`(워커)를 확인하세요.

### 문제 진단 및 해결
VM에서 cloud-init이 반복 실행되는 문제가 발생하면:

```bash
# Cloud-init 상태 확인
sudo cloud-init status --long

# Cloud-init 로그 확인
sudo tail -f /var/log/cloud-init.log

# 완료 표시 파일 확인
ls -la /var/lib/cloud-init-complete

# K3s 부트스트랩 로그 확인
sudo tail -f /var/log/k3s-bootstrap.log          # 마스터
sudo tail -f /var/log/k3s-agent-bootstrap.log    # 워커

# 수동으로 완료 표시 파일 생성 (필요시)
sudo mkdir -p /var/lib
sudo touch /var/lib/cloud-init-complete
```

### 참고
- ISO를 분리하지 않아도 `disk,cdrom` 순서면 디스크가 먼저 부팅되어 재설치 루프를 예방할 수 있습니다.
- Cloud-init idempotency 개선으로 VM 재시작 시 불필요한 재설치가 방지됩니다.

### ⚠️ 중요: VMware ISO 연결 해제

VM 내부에서 eject를 했더라도 VMware Workstation의 설정에서 ISO가 여전히 연결되어 있으면, VM을 재부팅할 때 다시 설치가 진행될 수 있습니다.

#### 자동 해결 (권장)
VM 생성 스크립트가 자동으로 ISO 연결을 해제합니다:
- VM 부팅 후 ISO 파일 복사 완료까지 대기 (최대 15분)
- 파일 복사 완료 신호 확인 후 ISO 장치 자동 해제
- 재설치 루프 완전 방지
- 안전한 파일 복사 보장

#### 수동 해결
VMware Workstation에서 수동으로 ISO 연결을 해제하려면:

1. **VM 선택** → **Edit Settings**
2. **CD/DVD 장치** 선택
3. **"Connected" 체크 해제** 또는 **ISO 파일 연결 제거**
4. **OK** 클릭

#### 확인 방법
```bash
# VM 내부에서 CD-ROM 장치 확인
ls -la /dev/sr* /dev/cd* /dev/scd* 2>/dev/null || echo "CD-ROM 장치 없음"

# VMware 설정에서 ISO 연결 상태 확인
# Edit Settings → CD/DVD → Connected 체크 해제됨
```

## 🔒 보안 및 안정성

### 이미지 다이제스트 고정
오프라인 환경에서의 안정성을 위해 이미지 다이제스트를 고정하는 것을 권장합니다:

```bash
# WSL2에서 다이제스트 조회 (선택사항)
cd wsl/scripts
# get-image-digests.sh 스크립트가 제거되었으므로 수동으로 확인
docker images --digests
```

### 호환성 보장
- **kube-proxy/kubectl**: 클러스터 버전과 동일 (v1.33.4-rc1)
- **KubeSphere 4.1.3**: k3s 1.33 계열과 공식 호환
- **CoreDNS/metrics-server**: K3s 기본값과 동등 또는 보수 최신

### 보안 고려사항
- **SSH 키 기반 인증**: 패스워드 인증 완전 비활성화, SSH 키만 사용
- **루트 로그인 비활성화**: 보안 강화를 위해 root 계정 SSH 로그인 차단
- **TLS 인증서**: 프라이빗 레지스트리용 자체 서명 인증서 (SAN 포함)
- **네트워크 격리**: Host-Only 네트워크 사용
- **최소 권한**: 필요한 최소 권한만 부여

### 레지스트리 TLS SAN 문제와 해결 (중요)
- **증상**: 워커에서 `curl https://192.168.6.1:5000/v2/` 또는 kubelet 이미지 pull 시 `connection reset by peer` 발생.
- **원인**: 레지스트리 인증서가 `CN=localhost`로 생성되고 `SubjectAltName`에 `192.168.6.1`이 없어 TLS 이름검증 실패.
- **해결**:
  1) WSL에서 `wsl/scripts/00_prep_offline_fixed.sh` 실행 시 SAN 포함 인증서가 자동 생성됨(CN=`${REGISTRY_HOST_IP}`, SAN=`IP:${REGISTRY_HOST_IP},IP:127.0.0.1,DNS:localhost`).
  2) 생성된 `out/certs/airgap-registry-ca.crt`가 시드에 포함되어 VM 부팅 시 `/usr/local/share/ca-certificates/`로 복사되고 `update-ca-certificates`가 실행됨.
  3) `registries.yaml`도 VM 접근 주소(`https://${REGISTRY_HOST_IP}:${REGISTRY_PORT}`)로 자동 생성/배포됨.
- **검증**:
  - VM: `openssl s_client -connect 192.168.6.1:5000 -servername 192.168.6.1 -showcerts </dev/null | openssl x509 -noout -subject -ext subjectAltName`
  - VM: `curl -vk https://192.168.6.1:5000/v2/`
  - 클러스터: `kubectl -n kube-system get pods` 에서 `local-path-provisioner`가 Running 전환

## 📞 지원

문제가 발생하면:
1. `scripts\check-env.ps1` 실행하여 환경 검증
2. WSL2 및 VMware 상태 확인
3. 충분한 시스템 리소스 확보
4. 방화벽이나 보안 소프트웨어 확인
5. 이미지 다이제스트 확인 (오프라인 환경)

## 📝 참고사항

- **레지스트리 URL**: `https://192.168.6.1:5000` (VM에서 접근)
- **WSL2 레지스트리**: `https://localhost:5000` (WSL2 내부)
- **k3s 버전**: `v1.33.4-rc1+k3s1`
- **KubeSphere 버전**: `v4.1.3`
- **Ubuntu 버전**: `22.04.5 LTS`
- **총 미러링된 이미지**: 26개
- **에어갭 이미지**: `k3s-airgap-images-amd64.tar` (636MB)
- **네트워크 구성**: WSL2 ↔ Windows 포트 포워딩 ↔ VM 네트워크
- **IP 대역**: 192.168.6.x (통일된 네트워크 설정)

## 🔧 최근 변경사항
### 2025-09-02: Setup-VMs 가속 및 신뢰도 개선 (중요)
- `windows/Setup-VMs.ps1`
  - VM 준비 대기 고정시간 300s → 120s로 축소, IP/SSH 신호 기반 조기 종료
  - `vmrun` 대체 인자 순서(명령 뒤 `-gu/-gp`) 자동 시도 및 캐시
  - 게스트 명령 실패 시 SSH 폴백으로 완료 파일(`/var/lib/iso-copy-complete`) 확인
  - 워커 ISO 분리 병렬 처리, 불필요한 대기 시간 축소
- 예상 효과: 전체 실행 시간 단축(환경에 따라 6~9분 수준), 완료 판정 정확도 향상

#### Wait for VMs ready 단계가 멈출 때 (트러블슈팅)
**증상**: 다음 로그 이후 수 분간 아무 변화가 없는 것처럼 보임

```text
[INFO] Waiting for VMs to be ready for operations...
[INFO] Waiting for VM k3s-master1 to be ready for operations (max 20 minutes)...
```

**원인**: 과거 버전에서 SSH 실패 시 즉시 반복으로 넘어가(vmrun/기타 신호 확인을 스킵) SSH만 재시도하는 문제가 있었습니다.

**해결(적용됨)**:
- SSH 실패 후에도 vmrun 구문 테스트와 게스트 IP/Tools 신호 확인을 수행하도록 수정되었습니다.
- 주기적 진행 로그가 추가되어, SSH가 아직 준비되지 않은 경우에도 경과 시간이 보입니다.

**확인 팁**:
- VMware 콘솔에서 VM이 네트워크를 획득했는지 확인합니다.
- Windows에서 다음 명령으로 SSH 포트가 열리는지 확인합니다:
  ```powershell
  Test-NetConnection 192.168.6.10 -Port 22
  ```
- 문제가 지속되면 `windows/Check-VMs.ps1`로 상태를 점검하세요.

**SSH 옵션/키 관련 팁**:
- 본 스크립트는 Windows `ssh.exe` 사용 시 다음 옵션을 강제해 키 우선 순위를 고정합니다:
  - `-o IdentitiesOnly=yes -o NumberOfPasswordPrompts=0 -o ConnectionAttempts=1`
- 수동 점검 시에도 동일 옵션을 사용해 주세요.
  ```powershell
  ssh -i .\wsl\out\ssh\id_rsa -o IdentitiesOnly=yes -o NumberOfPasswordPrompts=0 -o StrictHostKeyChecking=no ubuntu@192.168.6.10 "echo vm_ready"
  ```

### 2025-09-02: K3s 기본 컴포넌트 활성화 (중요)
- 변경: `wsl/templates/user-data-master.tpl`에서 K3s `config.yaml` 생성 시 `disable` 항목(`traefik`, `servicelb`) 제거하여 기본 컴포넌트가 자동 배포되도록 수정
- 영향: Traefik(Ingress), ServiceLB, local-path-provisioner, CoreDNS, metrics-server, pause 등이 기본값대로 배포됨
- 검증: `kubectl -n kube-system get pods -o wide`, `sudo k3s ctr images ls`

### 2025-09-01: 마스터 템플릿 런타임 변수 이스케이프 수정 (중요)
- **문제**: `user-data-master.tpl`에서 `setup-k3s-master.sh`의 `${SEED_BASE}`가 ISO 빌드 시 `envsubst`로 비워져 k3s 복사 단계가 실패할 수 있음
- **해결**: 2025-09-01에 `setup-k3s-master.sh` 스크립트의 SRC 변수 설정 및 SEED_BASE 검증 로직 개선
- **수정**: `${SEED_BASE}`를 `${DOLLAR}{SEED_BASE}`로 이스케이프하여 런타임에 올바르게 평가되도록 변경 (2곳)
- **영향**: k3s 바이너리 복사 및 클러스터 부트스트랩 안정화

### 2025-09-01: PowerShell 스크립트 변수 참조 구문 수정 (중요)
- **문제**: `Setup-VMs.ps1`에서 `$guestSyntax.Name`, `$guestSyntax.Args` 접근 시 PowerShell 구문 오류 발생
- **원인**: 해시테이블 속성 접근 시 잘못된 구문 사용
- **해결**: `$guestSyntax['Name']`, `$guestSyntax['Args']` 형태로 수정 (4곳)
- **영향**: VM 생성 스크립트 실행 오류 해결
- **파일**: `wsl/templates/user-data-master.tpl`


### 2024-12-19: k8s 운영 도구 설치 개선 및 CDROM 마운트 해제 로직 개선 (8차 수정)
- **문제**: 
  - k8s 운영에 필요한 command들이 deb 파일로 다운로드되었지만 VM에서 설치되지 않음
  - CDROM 마운트 해제 시 cloud-init status가 done으로 완료되지 않아 계속 대기하는 상태
- **해결**: 
  - deb 파일들을 tar.gz로 압축하여 VM에 전달하는 로직 추가
  - VM에서 tar.gz 압축 해제 및 자동 설치 스크립트 추가
  - cloud-init 템플릿에 k8s 운영 패키지 설치 서비스 추가
  - Setup-VMs.ps1의 Wait-ForISOCopy 로직 개선 (타임아웃 증가, 상태 체크 개선)
  - 설치 완료 확인 로직 및 마커 파일 생성 추가
- **포함된 도구**: jq, htop, ethtool, iproute2, dnsutils, telnet, psmisc, sysstat, iftop, iotop, dstat, yq
- **영향**: k8s 운영 도구들이 정상적으로 설치되고, CDROM 마운트 해제가 정확한 시점에 수행됨
- **파일**: `wsl/scripts/01_build_seed_isos.sh`, `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`, `windows/Setup-VMs.ps1`

### 2024-12-19: kubectl TLS 인증서 오류 해결 가이드 추가 (7차 수정)
- **문제**: WSL에서 kubectl 접속 시 TLS 인증서 오류 및 SSH 호스트 키 문제 발생
- **해결**: 
  - 실제 사용자 사례 기반 문제 해결 과정 문서화
  - SSH 호스트 키 초기화 방법 추가 (`ssh-keygen -R`, `sed -i '/IP/d'`)
  - TLS 인증서 오류 해결 방법 상세 가이드
  - VM 재생성 시 주의사항 및 해결책 추가
- **문서**: README.md의 WSL kubectl 접속 가이드에 실제 문제 해결 사례 추가
- **영향**: 사용자가 kubectl 접속 문제를 빠르게 해결할 수 있는 구체적인 가이드 제공
- **파일**: `README.md`

### 2024-12-19: Airgapped 환경용 패키지 자동 포함 (6차 수정)
- **문제**: Airgapped 환경에서 추가 유틸리티 패키지들이 필요하지만 네트워크 접근이 불가능한 상황
- **해결**: 
  - WSL에서 ISO 빌드 시 필요한 패키지들을 미리 다운로드하여 ISO에 포함
  - 포함된 패키지: `jq`, `iftop`, `iotop`, `dstat`, `sysstat`, `psmisc`, `yq`, `iproute2`, `telnet`, `dnsutils`, `htop`, `ethtool`
  - VM 설치 후 자동으로 추가 패키지들이 설치되도록 cloud-init 스크립트 추가
- **영향**: Airgapped 환경에서도 완전한 도구셋 사용 가능, 디버깅 및 모니터링 효율성 향상
- **파일**: `wsl/scripts/01_build_seed_isos.sh`, `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`

### 2024-12-19: WSL kubectl 접속 자동화 및 개선 (5차 수정)
- **개선**: `02_wait_and_config.sh` 스크립트에 WSL kubectl 접속 자동 설정 기능 추가
- **기능**: 
  - kubeconfig 파일 자동 다운로드 및 설정
  - SSH 호스트 키 문제 자동 해결
  - TLS 인증서 오류 자동 처리 (insecure flag 사용)
  - WSL에서의 kubectl 접속 테스트 및 검증
- **문서**: README.md의 WSL kubectl 접속 가이드 개선 및 단계별 문제 해결 방법 추가
- **영향**: 사용자가 수동으로 kubectl 설정할 필요 없이 자동으로 WSL에서 VM 클러스터 접속 가능
- **파일**: `wsl/scripts/02_wait_and_config.sh`, `README.md`

### 2024-12-19: VMware ISO 자동 해제 및 Cloud-init Idempotency 개선 (4차 수정)
- **문제**: VM 재시작 시 cloud-init이 반복적으로 실행되어 불필요한 재설치 시도, VMware ISO 연결로 인한 재설치 루프 위험
- **해결**: 
  - VM 생성 스크립트에 ISO 자동 해제 로직 추가 (VMX 파일 수정 방식)
  - 각 설정 단계마다 완료 표시 파일을 생성하여 idempotency 보장
  - `runcmd` 섹션의 모든 명령을 조건부 실행으로 변경
  - K3s 부트스트랩 서비스의 중복 실행 방지
- **영향**: VM 재시작 시 불필요한 재설치 완전 방지, 안정적인 클러스터 운영
- **파일**: `windows/Setup-VMs.ps1`, `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`

### 2024-12-19: Cloud-init Idempotency 개선 (3차 수정)
- **문제**: VM 재시작 시 cloud-init이 반복적으로 실행되어 불필요한 재설치 시도
- **해결**: 
  - 각 설정 단계마다 완료 표시 파일을 생성하여 idempotency 보장
  - `runcmd` 섹션의 모든 명령을 조건부 실행으로 변경
  - K3s 부트스트랩 서비스의 중복 실행 방지
- **영향**: VM 재시작 시 불필요한 재설치 방지, 안정적인 클러스터 운영
- **파일**: `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`

### 2024-12-19: VM 자동 설치 개선 (2차 수정)
- **문제**: VM 설치 시 언어 선택 화면이 계속 나타나는 문제
- **해결**: 
  - `autoinstall` 섹션에 `shutdown: reboot` 및 `reboot: true` 설정 추가
  - `early-commands`에 언어 설정 강제 적용 명령 추가
  - `packages` 섹션에 필수 패키지 목록 추가
- **영향**: Ubuntu 22.04 자동 설치 시 인터랙티브 프롬프트 완전 제거
- **파일**: `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`

### 250901 - PowerShell 스크립트 vmrun 타임아웃 문제 해결
- **문제**: `Setup-VMs.ps1` 실행 시 `vmrun guest command syntax` 테스트에서 무한 대기 발생
- **원인**: `Test-VMRunGuestSyntax` 함수에서 `vmrun` 명령어 실행 시 타임아웃 처리 부족
- **해결**: 
  - `Test-VMRunGuestSyntax` 함수에 30초 타임아웃 추가
  - `Wait-ForVMReady` 함수에서 vmrun 구문 테스트에 60초 타임아웃 추가
  - Job 기반 비동기 실행으로 무한 대기 방지
- **영향**: VM 생성 후 준비 상태 확인 기능 정상화, 스크립트 진행 중단 문제 해결

### 250901 - vmrun 인증 플래그 순서 및 부트스트랩 실행 방식 변경 (중요)
- **문제**: `vmrun` 인증 플래그가 `runProgramInGuest` 뒤에 배치되어 게스트 명령 실패 → 준비/완료 상태 체크 불가
- **해결**: `windows/Setup-VMs.ps1`에서 인증 플래그를 명령 앞에 위치하도록 수정 (모든 호출 경로)
- **변경**: `wsl/templates/user-data-master.tpl`의 runcmd에서 부트스트랩 스크립트 직접 실행을 제거하고, systemd 서비스(`k3s-bootstrap.service`)만 사용하도록 변경
- **참고 명령 (올바른 예시)**:
  ```
  vmrun -T ws -gu <guestUser> -gp <guestPassword> runProgramInGuest "C:\path\vm.vmx" "/bin/echo" test
  ```
- **영향**: 게스트 명령 실행 안정화, 중복 실행 방지로 k3s 기동 타이밍 개선

### 250901 - Netplan nameservers YAML 시퀀스 정비
- **변경**: `user-data-master.tpl`에서 `nameservers.addresses`를 블록 시퀀스로 변경
- **예시**:
  ```yaml
  nameservers:
    addresses:
      - ${DNS_IP}
  ```

## 🎯 다음 단계

1. VM 생성 및 k3s 설치 (자동화됨)
2. KubeSphere 코어 컴포넌트 설치 (자동화됨)
3. 확장 컴포넌트 개별 설치 (필요시)
4. 클러스터 모니터링 및 관리

## 🔄 에어갭 환경 구성

이 프로젝트는 완전한 에어갭 환경을 지원합니다:

### 자동 에어갭 이미지 로드
VM이 부팅될 때 자동으로 에어갭 이미지가 로드됩니다:
- **k3s-airgap-images-amd64.tar** (636MB): 공식 k3s 에어갭 이미지 패키지
- **자동 로드**: VM 템플릿에 포함되어 부팅 시 자동 실행
- **Docker 런타임**: k3s가 Docker 런타임을 사용하도록 설정

### 수동 에어갭 이미지 로드 (선택사항)
WSL2에서 직접 에어갭 이미지를 로드할 수도 있습니다:

```bash
# 에어갭 이미지 로드
cd wsl/out/airgap
docker load -i k3s-airgap-images-amd64.tar

# 로드된 이미지 확인
docker images | grep k3s
```

### 에어갭 환경의 장점
- **완전 오프라인**: 인터넷 연결 없이 모든 구성 요소 실행
- **공식 검증**: k3s 팀에서 공식적으로 제공하는 이미지 조합
- **버전 호환성**: k3s v1.33.4-rc1과 완벽 호환
- **빠른 배포**: 이미 패키징된 이미지로 빠른 클러스터 구축
- **무결성 보장**: SHA256 체크섬으로 다운로드 검증
- **Ubuntu 기반**: 실제 Ubuntu 22.04.5 ISO를 사용한 안정적인 설치

## 📚 관련 자료

- [KubeSphere 공식 문서](https://kubesphere.io/docs/)
- [K3s 공식 문서](https://docs.k3s.io/)
- [Docker Registry 문서](https://docs.docker.com/registry/)

## 📝 라이선스

이 프로젝트는 교육 및 테스트 목적으로 제공됩니다. 프로덕션 환경에서 사용하기 전에 보안 검토를 권장합니다.

---

**🎉 모든 설정이 완료되었습니다! 이제 Airgapped Lab을 사용할 수 있습니다.**

### 250901 - 자동화 개선 및 문제 해결 완료 (중요)
+- **해결된 문제들**:
+  - SEED_BASE 변수 설정 문제 → 고정 경로 `/usr/local/seed` 사용
+  - ops 패키지 설치 스크립트 경로 문제 → 고정 경로 및 오프라인 설치 지원
+  - 워커 노드 레지스트리 설정 문제 → CA 인증서 및 registries.yaml 자동 복사
+  - vmrun 인증 플래그 순서 문제 → Windows 스크립트에서 수정 완료
+  - 서비스 의존성 문제 → k3s-bootstrap.service와 k8s-ops-packages.service 간의 강제 의존성 제거
+  - vmrun 인증 플래그 중복 문제 → Test-VMRunGuestSyntax 및 Wait-ForVMReady 함수에서 인증 플래그 중복 제거
+- **자동화된 기능들**:
+  - k3s 바이너리 자동 복사 및 설치
+  - 레지스트리 설정 자동 복사
+  - ops 패키지 자동 설치 (tar.gz 압축 해제 포함)
+  - 워커 노드 자동 조인
+  - airgap 이미지 자동 임포트
+  - 서비스 순차 실행 (ops 패키지 설치 후 k3s 부트스트랩)
+  - VM 준비 상태 확인 (vmrun 명령어 구문 오류 해결)
+- **수정된 파일들**: `user-data-master.tpl`, `user-data-worker.tpl`, `01_build_seed_isos.sh`, `Setup-VMs.ps1`
+- **영향**: 완전 자동화된 VM 및 k3s 클러스터 생성, 수동 개입 불필요

## Windows 콘솔 한글 출력 이슈(중요)

일부 Windows 환경에서 PowerShell 실행 로그의 한글이 "완완료료", "단단계계별별"처럼 중복 표시될 수 있습니다. 이는 콘솔 코드페이지와 출력 인코딩이 UTF-8과 불일치할 때 발생합니다. 아래와 같이 UTF-8로 강제 설정하면 해결됩니다.

```powershell
# PowerShell 세션에서 실행
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding  = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
chcp 65001 | Out-Null
```

본 프로젝트의 `windows/Setup-VMs.ps1`에는 위 설정이 자동으로 포함되어 있어, 스크립트 실행만으로 문제를 피할 수 있습니다.

##### vmrun 점검/폴백 로직(추가)
- 점검/검증 명령은 `/bin/bash -lc 'echo vmrun_ok'`를 사용하여 PATH/쉘 차이로 인한 실패를 방지합니다.
- `runProgramInGuest` 실패 시 `runScriptInGuest`로 동일 검증을 재시도하는 폴백 경로가 있습니다.
- `checkToolsState`로 VMware Tools 상태를 먼저 확인하여 `Tools not running`/`Invalid user name or password`/`Usage`를 로그로 구분합니다.
- Tools 미기동 시 대기 백오프: 10초 → 20초 → 30초(상한)로 재시도 간격을 점진적으로 늘립니다.