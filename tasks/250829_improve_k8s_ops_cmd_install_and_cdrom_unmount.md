# K8s 운영 Command 설치 및 CDROM 마운트 해제 개선 작업

## 문제 상황
1. **k8s 운영 command 설치 문제**: deb 파일들이 WSL/scripts에 다운로드되었지만 VM에서 설치되지 않음
2. **CDROM 마운트 해제 로직 문제**: Wait-ForISOCopy에서 cloud-init status가 done으로 완료되지 않아 계속 대기하는 상태

## 작업 사항 (Tasks)

### Task 1: deb 파일을 tar.gz로 압축하는 로직 추가
- **위치**: `wsl/scripts/01_build_seed_isos.sh`
- **작업 내용**:
  - 다운로드된 deb 파일들을 tar.gz로 압축
  - 압축 파일을 seed ISO에 포함
  - 압축 해제 및 자동 설치 스크립트 추가

### Task 2: VM에서 tar.gz 압축 해제 및 자동 설치 로직 추가
- **위치**: `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`
- **작업 내용**:
  - tar.gz 파일 압축 해제
  - deb 파일들 자동 설치 (dpkg -i)
  - 설치 완료 확인 로직

### Task 3: Setup-VMs.ps1의 Wait-ForISOCopy 로직 개선
- **위치**: `windows/Setup-VMs.ps1`
- **작업 내용**:
  - cloud-init status 체크 로직 개선
  - 타임아웃 처리 개선
  - 더 정확한 완료 조건 설정

### Task 4: 설치 완료 확인 로직 추가
- **위치**: `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`
- **작업 내용**:
  - k8s command 설치 완료 마커 파일 생성
  - 설치된 command 목록 확인

## 예상 결과
1. deb 파일들이 tar.gz로 압축되어 VM에 전달됨
2. VM에서 자동으로 압축 해제 및 설치가 완료됨
3. CDROM 마운트 해제가 정확한 시점에 수행됨
4. k8s 운영 command들이 정상적으로 설치됨

## 검증 방법
1. VM에서 `kubectl`, `helm`, `k9s` 등 명령어 실행 확인
2. 설치된 패키지 목록 확인 (`dpkg -l | grep -E "(jq|iftop|iotop|dstat|sysstat|psmisc|yq|iproute2|telnet|dnsutils|htop|ethtool)"`)
3. CDROM 마운트 해제 후 재부팅 시 재설치되지 않음 확인

## 작업 완료 상태

### ✅ Task 1: deb 파일을 tar.gz로 압축하는 로직 추가
- **완료**: `wsl/scripts/01_build_seed_isos.sh`에 tar.gz 압축 로직 추가
- **기능**: deb 파일들을 `k8s-ops-packages.tar.gz`로 압축하여 ISO에 포함

### ✅ Task 2: VM에서 tar.gz 압축 해제 및 자동 설치 로직 추가
- **완료**: `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`에 설치 스크립트 추가
- **기능**: 
  - `/usr/local/bin/install-k8s-ops-packages.sh` 스크립트 생성
  - `k8s-ops-packages.service` systemd 서비스 추가
  - k3s 부트스트랩 서비스가 패키지 설치 완료 후 실행되도록 의존성 설정

### ✅ Task 3: Setup-VMs.ps1의 Wait-ForISOCopy 로직 개선
- **완료**: `windows/Setup-VMs.ps1`의 Wait-ForISOCopy 함수 개선
- **개선사항**:
  - 타임아웃을 20분에서 30분으로 증가
  - VM 응답성 체크 추가
  - cloud-init 상태 체크 개선 (running, done, error, NOT_READY 상태 구분)
  - k8s 패키지 설치 완료 체크 추가
  - 중복 로그 방지를 위한 상태 변경 감지

### ✅ Task 4: 설치 완료 확인 로직 추가
- **완료**: cloud-init 템플릿에 설치 완료 확인 로직 추가
- **기능**:
  - 설치된 패키지 목록을 `/var/log/k8s-ops-packages.log`에 기록
  - 설치 완료 마커 파일 `/var/lib/k8s-ops-installation-complete` 생성
  - idempotency 보장을 위한 조건부 실행

### ✅ 문서 업데이트
- **완료**: `README.md`에 8차 수정사항 문서화
- **내용**: k8s 운영 도구 설치 개선 및 CDROM 마운트 해제 로직 개선 사항 추가
