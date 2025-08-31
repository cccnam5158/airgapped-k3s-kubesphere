# VM 생성 스크립트 실행 과정 도식화

## 전체 실행 흐름

```mermaid
graph TD
    A[사용자 실행] --> B[setup-vms.ps1]
    B --> C[환경 설정 및 검증]
    C --> D[Setup-VMs.ps1 호출]
    D --> E[VM 생성 프로세스]
    E --> F[VM 부팅 및 설정]
    F --> G[완료]
    subgraph "setup-vms.ps1 (진입점)"
        B1[UTF-8 인코딩 설정]
        B2[환경 변수 설정]
        B3[관리자 권한 확인]
        B4[VMware vmrun 경로 확인]
        B5[실행 정책 설정]
    end

    subgraph "Setup-VMs.ps1 (메인 로직)"
        D1[사전 요구사항 검증]
        D2[기존 VM 정리]
        D3[VM 생성]
        D4[VM 부팅]
        D5[ISO 복사 대기]
        D6[ISO 분리]
        D7[VM 재시작]
    end
```

## 상세 실행 과정

### 1. setup-vms.ps1 (진입점 스크립트)

```mermaid
flowchart TD
    A[스크립트 시작] --> B[UTF-8 인코딩 설정]
    B --> C[환경 변수 설정]
    C --> D[관리자 권한 확인]
    D --> E{관리자 권한?}
    E -->|No| F[오류: 관리자 권한 필요]
    E -->|Yes| G[VMware vmrun 경로 확인]
    G --> H{vmrun 찾음?}
    H -->|No| I[오류: VMware Workstation 필요]
    H -->|Yes| J[실행 정책 설정]
    J --> K[Setup-VMs.ps1 호출]
    K --> L[완료 메시지 출력]
```

### 2. Setup-VMs.ps1 (메인 VM 생성 로직)

```mermaid
flowchart TD
    A[Setup-VMs.ps1 시작] --> B[사전 요구사항 검증]
    B --> C{검증 통과?}
    C -->|No| D[오류 종료]
    C -->|Yes| E[기존 VM 정리]
    E --> F[VM 디렉토리 생성]
    F --> G[Master VM 생성]
    G --> H[Worker VM들 생성]
    H --> I{VM 시작?}
    I -->|No| J[VM 생성만 완료]
    I -->|Yes| K[VM 부팅 프로세스]
    K --> L[ISO 복사 대기]
    L --> M[ISO 분리]
    M --> N[VM 재시작]
    N --> O[완료]
```

## 단계별 상세 과정

### Phase 1: 환경 설정 및 검증

```mermaid
graph LR
    A[환경 설정] --> B[인코딩 설정]
    B --> C[변수 설정]
    C --> D[권한 확인]
    D --> E[VMware 확인]
    E --> F[Seed 파일 확인]
    F --> G[네트워크 설정 확인]
```

**실행되는 검증 항목:**
- ✅ 관리자 권한 확인
- ✅ VMware Workstation Pro 설치 확인
- ✅ vmrun 경로 확인 (`C:\Program Files\VMware\VMware Workstation\vmrun.exe`)
- ✅ Seed 디렉토리 존재 확인 (`./wsl/out`)
- ✅ Seed ISO 파일들 확인 (`seed-master1.iso`, `seed-worker1.iso`, `seed-worker2.iso`)

### Phase 2: 기존 VM 정리

```mermaid
graph TD
    A[기존 VM 확인] --> B{VM 존재?}
    B -->|No| C[정리 완료]
    B -->|Yes| D[VM 중지]
    D --> E[VM 등록 해제]
    E --> F[VM 디렉토리 삭제]
    F --> G[기본 디렉토리 정리]
    G --> C
```

**정리 대상:**
- `k3s-master1`
- `k3s-worker1`
- `k3s-worker2`

### Phase 3: VM 생성

```mermaid
graph TD
    A[VM 생성 시작] --> B[VM 디렉토리 생성]
    B --> C[VMX 파일 생성]
    C --> D[가상 디스크 생성]
    D --> E[Master VM 생성]
    E --> F[Worker VM들 생성]
    F --> G[VM 생성 완료]
```

**VMX 설정 내용:**
```ini
# 기본 설정
memsize = "4096"          # 4GB 메모리
numvcpus = "2"            # 2개 CPU
displayName = "k3s-master1"
guestOS = "ubuntu-64"
firmware = "bios"

# 네트워크 설정
ethernet0.connectionType = "hostonly"
ethernet0.vnet = "VMnet1"

# CD-ROM 설정 (Seed ISO)
sata0:1.fileName = "seed-master1.iso"
sata0:1.deviceType = "cdrom-image"
sata0:1.startConnected = "TRUE"

# 부팅 순서
bios.bootOrder = "disk,cdrom"
```

### Phase 4: VM 부팅 및 설정

```mermaid
graph TD
    A[VM 부팅 시작] --> B[Master VM 시작]
    B --> C[Worker VM들 시작]
    C --> D[ISO 복사 대기]
    D --> E{복사 완료?}
    E -->|No| F[대기 중...]
    F --> D
    E -->|Yes| G[ISO 분리]
    G --> H[VM 재시작]
    H --> I[완료]
```

**부팅 프로세스:**
1. **VM 시작**: `vmrun -T ws start <vmx_path>`
2. **ISO 복사 대기**: `/var/lib/iso-copy-complete` 파일 확인
3. **Cloud-init 완료 대기**: `cloud-init status` 확인
4. **ISO 분리**: VMX에서 `sata0:1.startConnected = "FALSE"`
5. **VM 재시작**: 변경사항 적용

### Phase 5: ISO 복사 대기 로직

```mermaid
graph TD
    A[대기 시작] --> B[VM 상태 확인]
    B --> C{VM 실행 중?}
    C -->|No| D[대기 후 재시도]
    D --> B
    C -->|Yes| E[Guest OS 준비 확인]
    E --> F{Guest OS 준비?}
    F -->|No| G[대기 후 재시도]
    G --> E
    F -->|Yes| H[ISO 복사 완료 확인]
    H --> I{복사 완료?}
    I -->|No| J[Cloud-init 상태 확인]
    J --> K[대기 후 재시도]
    K --> H
    I -->|Yes| L[대기 완료]
```

**확인 항목:**
- ✅ VM 실행 상태
- ✅ Guest OS 준비 상태
- ✅ ISO 복사 완료 파일 (`/var/lib/iso-copy-complete`)
- ✅ Cloud-init 상태 (`running` → `done`)
- ✅ K8s 패키지 설치 완료 (`/var/lib/k8s-ops-packages-installed`)

## 네트워크 구성

```mermaid
graph TD
    A[VMnet1] --> B[192.168.6.0/24]
    B --> C[k3s-master1<br/>192.168.6.10]
    B --> D[k3s-worker1<br/>192.168.6.11]
    B --> E[k3s-worker2<br/>192.168.6.12]
    B --> F[Gateway<br/>192.168.6.1]
    F --> G[Registry<br/>192.168.6.1:5000]
```

## 파일 구조

```
F:\VMs\AirgapLab\
├── k3s-master1\
│   ├── k3s-master1.vmx
│   └── k3s-master1.vmdk
├── k3s-worker1\
│   ├── k3s-worker1.vmx
│   └── k3s-worker1.vmdk
└── k3s-worker2\
    ├── k3s-worker2.vmx
    └── k3s-worker2.vmdk
```

## 실행 시간 예상

| 단계 | 예상 시간 | 설명 |
|------|-----------|------|
| 환경 검증 | 1-2분 | 사전 요구사항 확인 |
| 기존 VM 정리 | 2-3분 | VM 중지 및 삭제 |
| VM 생성 | 5-10분 | VMX 및 디스크 생성 |
| VM 부팅 | 10-15분 | 초기 부팅 및 설정 |
| ISO 복사 대기 | 15-30분 | Cloud-init 완료 대기 |
| ISO 분리 및 재시작 | 5-10분 | 설정 적용 |
| **총 예상 시간** | **40-70분** | 전체 프로세스 |

## 오류 처리

```mermaid
graph TD
    A[오류 발생] --> B{오류 유형}
    B -->|권한 오류| C[관리자 권한 필요]
    B -->|VMware 오류| D[VMware 설치 확인]
    B -->|네트워크 오류| E[VMnet1 설정 확인]
    B -->|디스크 오류| F[디스크 공간 확인]
    B -->|ISO 오류| G[Seed 파일 확인]
    C --> H[사용자 안내]
    D --> H
    E --> H
    F --> H
    G --> H
```

## 성공 완료 후 상태

**VM 상태:**
- ✅ 모든 VM이 실행 중
- ✅ ISO가 분리되어 재설치 방지
- ✅ Cloud-init 완료
- ✅ K8s 운영 패키지 설치 완료

**접속 정보:**
- **SSH**: `ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.10`
- **KubeSphere**: `http://192.168.6.10:30880`
- **kubectl**: `k3s kubectl get nodes`

**다음 단계:**
1. `./wsl/scripts/02_wait_and_config.sh` 실행
2. 클러스터 상태 확인
3. KubeSphere 설치 및 설정
