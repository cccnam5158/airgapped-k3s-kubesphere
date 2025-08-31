# VM 내부 K8s 운영 패키지 설치 상태 점검 스크립트 생성

## 작업 개요
- user-data-master.tpl, user-data-worker.tpl, 01_build_seed_isos.sh를 통해 생성된 VM에서
- jq, htop, ethtool, iproute2, dnsutils, telnet, psmisc, sysstat 등의 K8s 운영 패키지들이
- airgapped 환경에서 제대로 설치되었는지 확인하는 점검 스크립트 생성

## 문제 상황
- 템플릿과 빌드 스크립트에서 의도한 대로 패키지 설치가 구성되어 있음
- 하지만 실제 VM에서는 jq 등의 명령어가 설치되지 않은 상황
- VM 내부에서 설치 상태를 점검할 수 있는 스크립트 필요

## 작업 내용
1. VM 내부에서 실행할 수 있는 패키지 설치 상태 점검 스크립트 생성
2. 설치 실패 원인 진단 기능 포함
3. 수동 설치 복구 기능 포함
4. 상세한 로그 및 보고서 생성

## 예상 원인 분석
- cloud-init 실행 순서 문제
- 패키지 의존성 문제
- 파일 권한 문제
- 네트워크 설정 문제 (airgap 환경)
- systemd 서비스 실행 실패

## 생성할 파일
- `wsl/scripts/check-vm-packages.sh`: VM 내부 실행용 점검 스크립트
- `wsl/scripts/fix-vm-packages.sh`: 수동 복구 스크립트

## 상태
- [x] 점검 스크립트 생성
- [x] 복구 스크립트 생성
- [x] README.md 업데이트
- [x] 향후 개선 사항 반영
- [ ] 테스트 및 검증

## 완료된 작업
1. ✅ `wsl/scripts/check-vm-packages.sh` 생성
   - VM 내부에서 K8s 운영 패키지 설치 상태 점검
   - 10단계 종합 점검 기능
   - 자동 수정 및 보고서 생성 기능

2. ✅ `wsl/scripts/fix-vm-packages.sh` 생성
   - VM 내부에서 패키지 설치 문제 수동 복구
   - 백업 생성 및 안전한 복구 기능
   - 10단계 복구 프로세스

3. ✅ README.md 업데이트
   - 프로젝트 구조에 새로운 스크립트 추가
   - VM 내부 점검 및 복구 스크립트 사용법 문서화
   - 점검 항목 및 복구 기능 상세 설명

4. ✅ 향후 개선 사항 반영
   - 01_build_seed_isos.sh: 의존성 패키지 자동 다운로드 추가
   - user-data-master.tpl: 패키지 설치 로직 개선
   - user-data-worker.tpl: 패키지 설치 로직 개선
   - install-packages.sh: 의존성 해결 로직 강화

## 다음 단계
- 실제 VM에서 스크립트 테스트
- 문제 발견 시 추가 개선사항 적용

## 생성된 파일
- `wsl/scripts/check-vm-packages.sh`: VM 내부 실행용 점검 스크립트
- `wsl/scripts/fix-vm-packages.sh`: 수동 복구 스크립트

## 사용법

### 점검 스크립트 사용법
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

### 복구 스크립트 사용법
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

## 점검 항목
1. 시스템 기본 정보 점검
2. cloud-init 실행 상태 점검
3. K8s 운영 패키지 설치 서비스 상태 점검
4. Seed 파일 및 패키지 디렉토리 점검
5. 개별 패키지 설치 상태 점검
6. dpkg 상태 점검
7. 네트워크 및 시스템 설정 점검
8. 문제 진단 및 해결 방안 제시
9. 자동 수정 시도 (옵션)
10. 결과 요약 및 보고서 생성

## 복구 기능
1. 사전 점검 (권한, 디스크 공간 등)
2. 백업 생성 (기존 상태 보존)
3. 현재 설치 상태 확인
4. 설치 파일 검증
5. 기존 설치 정리
6. 패키지 설치 실행
7. 설치 결과 확인
8. 시스템 서비스 상태 복구
9. 시스템 설정 확인
10. 최종 점검 및 보고서 생성

## 향후 개선 사항 (반영 완료)

### 1. 의존성 패키지 자동 다운로드
- jq의 의존성: libjq1
- sysstat의 의존성: libsensors5
- 기타 필요한 의존성 패키지들 자동 포함

### 2. 패키지 설치 순서 최적화
- 의존성이 있는 패키지들을 먼저 설치
- 설치 실패 시 자동 재시도 로직

### 3. cloud-init 템플릿 개선
- k8s-ops-packages.service 등록 로직 강화
- APT 소스 비활성화 로직 개선
- 패키지 설치 완료 마커 생성 로직 추가

### 4. 설치 스크립트 강화
- 의존성 해결 로직 추가
- 설치 실패 시 상세 로그 생성
- 설치 성공률 모니터링
