# 250902 타임스탬프 로깅 및 단계별 소요 시간 계측

## 작업 배경
- Windows 환경의 `windows/Setup-VMs.ps1` 실행 로그에 시간 정보가 없어 단계별 진행 상황과 대기 시간 파악이 어려움.
- 각 주요 단계(사전 검사, 클린업, VM 생성/시작, 준비 대기, 초기화 모니터링, ISO 분리, 재시작 등)의 소요 시간을 계측해 문제 구간을 빠르게 식별 필요.

## 작업 목표
- 모든 로그 메시지에 타임스탬프(yyyy-MM-dd HH:mm:ss) 추가.
- 단계 타이머 유틸(`Start-Stage`, `End-Stage`, `Write-StageSummary`) 도입.
- 메인 실행 흐름에 단계별 타이머 삽입 및 총/단계 소요 시간 요약 출력.

## 변경 대상
- `windows/Setup-VMs.ps1`

## 구현 계획
1. 로깅 함수(`Write-Info/Success/Warning/Error`)에 타임스탬프 프리픽스 추가.
2. 전역 타이머 상태(`$script:StageTimers`, `$script:StageRecords`)와 헬퍼 3종 추가.
3. 메인 실행부에 단계 타이머 삽입(Prerequisites, Cleanup, Create Master/Workers, Start VMs, Wait, Monitor, Disconnect ISOs, Restart, Total).
4. 요약 출력(`Write-StageSummary`) 및 총 소요 시간 표시.

## 검증 항목
- 로그 라인에 모두 타임스탬프가 표시되는지.
- 단계 완료 시 “완료: <단계명> (소요: Xs)” 형태로 출력되는지.
- 마지막에 단계별/총 소요 요약이 출력되는지.

## 비고
- 기능 변경은 없고 가시성 개선 작업이므로 README 변경은 보류.

## 작업 결과
- 모든 로그 라인에 `yyyy-MM-dd HH:mm:ss` 타임스탬프 추가됨.
- `Start-Stage`, `End-Stage`, `Write-StageSummary` 유틸 도입 및 전역 상태 추가.
- 주요 단계에 타이머 삽입:
  - Prerequisites, Cleanup existing VMs, Create master VM, Create worker VMs,
  - Start VMs, Wait for VMs ready, Monitor initialization completion,
  - Disconnect ISOs, Restart VMs, Total
- 실행 종료 시 단계별 요약과 총 소요 시간 출력.

# 250902 작업 요약

## 요청
- K3s 기본 컴포넌트(traefik, servicelb 등)가 모두 배포되도록 마스터 템플릿 수정

## 변경 사항
- `wsl/templates/user-data-master.tpl`의 K3s `config.yaml` 생성 구간에서 `disable` 항목 제거
  - 제거 대상: `traefik`, `servicelb`

## 기대 효과
- 기본 Ingress Controller(Traefik)와 ServiceLB, 기타 기본 애드온이 클러스터에 자동 배포

## 검증 방법
- 마스터 노드에서 다음 확인
  - `sudo k3s ctr images ls`로 기본 이미지 세트 확인
  - `k3s kubectl -n kube-system get pods -o wide`로 `traefik`, `svclb-*`, `local-path-provisioner`, `coredns`, `metrics-server` 상태 확인

## 상태
- 적용 완료(마스터 템플릿 수정)
- README 업데이트 예정 포함하여 반영 완료



## 250902 Setup-VMs 실행 결과 분석 및 개선안

### 실행 결과 요약(소요 시간)
- Prerequisites: 0s
- Cleanup existing VMs: 0s
- Create master VM: 0.5s
- Create worker VMs: 0.9s
- Start VMs: 32.5s
- Wait for VMs ready: 959.1s
- Monitor initialization completion: 13s
- Disconnect ISOs: 41.5s
- Restart VMs: 15.4s
- Total: 1062.8s (~17분 43초)

### 병목 구간
- 가장 큰 병목은 `Wait for VMs ready`(약 16분, 전체의 ~90%).
  - 원인1: `Wait-ForVMReady`에서 VMware Tools 가동 후 고정 대기(`$minToolsWaitTime = 300s`)를 VM 별 순차 적용(마스터 → 워커1 → 워커2).
  - 원인2: 게스트 명령 테스트(`vmrun runProgramInGuest`)가 실패하여 단순화된 체크로 전환되며, 그 전에 최대 60초 타임아웃을 VM 별로 소모.
- `Disconnect ISOs`(41.5s): 각 VM을 soft stop 후 VMX 수정, 5초 대기 등을 VM별 순차 처리.

### 미완료/오탐 지점
- `vmrun` 게스트 명령이 모두 실패하여 실제 완료 지표(`/var/lib/iso-copy-complete`) 확인을 건너뜀.
  - `Check-CompletionStatus`에서 게스트 명령 불가 시 `true`로 간주하는 로직 때문에 "All VMs have completed" 메시지는 오탐 가능.

### 개선안(제안)
- 성능/시간 단축
  - `Wait-ForVMReady` 병렬화: 마스터/워커를 동시에 대기(Background Job)하여 총 대기 시간을 5~7분 수준으로 축소.
  - 고정 대기 300s → 가변 대기(예: 90~120s 기본 + 신호 기반 조기 종료). 신호: `getGuestIPAddress -wait`, cloud-init 완료 파일, SSH 포트 응답 등.
  - `Disconnect ISOs` 병렬화(워커 동시 처리) 및 불필요한 `Start-Sleep 5s` 축소.

- 신뢰도 향상
  - `vmrun` 인자 순서 양쪽 모두 시도: 현재는 인증 플래그를 명령 앞에만 배치. 추가로 다음 형태도 시도: `vmrun -T ws runProgramInGuest <vmx> -gu <user> -gp <pass> <program> <args>`.
  - 1회 성공 후 VM별/세션별 캐시(Hashtable)하여 재시도/타임아웃 중복 제거.
  - 게스트 명령 실패 시에도 Windows의 `ssh.exe`와 준비된 키(`wsl/out/ssh/id_rsa`)로 원격 명령 대체 실행(포트 22/네트워크 확인 후).
  - 완료판정은 반드시 실체 파일(`/var/lib/iso-copy-complete` 또는 cloud-init boot-finished) 확인로 대체하여 오탐 제거.

- UX/로깅
  - `vmrun` 실패 사유 분류(Usage/인증 실패/Tools not running/권한 문제)와 1라인 요약을 단계 요약에 포함.
  - 각 VM별 준비완료 ETA 및 경과 표시(병렬 대기 시 진행률 보이기).

### 예상 효과
- 총 소요 시간: ~17분 → 약 6~9분로 단축(환경에 따라 상이).
- 완료 판정의 정확성 향상(오탐 제거) 및 재시도/타임아웃 감소로 안정화.

### 구현 항목(작업 리스트)
1) `Wait-ForVMReady` 병렬 처리 + 고정 300s 축소/가변화.
2) `vmrun` 인자 순서 양식 추가 시도 및 1회 성공값 캐시.
3) 게스트 명령 실패 시 SSH 대체 경로 도입(키/호스트 도구 사용).
4) `Check-CompletionStatus`에서 실제 파일 기반 판정 필수화.
5) `Disconnect ISOs` 워커 병렬 처리 및 대기 시간 최적화.

상기 항목을 우선 적용 후, README에는 `vmrun` 인자 순서 호환성 주의 사항을 "Known issues/Workarounds"로 추가 예정.

---

## 250902 레지스트리 TLS SAN 문제 해결 요약

### 현상
- 워커에서 `curl https://192.168.6.1:5000/v2/` 시 `connection reset by peer`.
- kubelet 이벤트: pause 이미지 `rancher/mirrored-pause:3.6` pull 실패, 레지스트리 HEAD 요청이 reset.

### 원인
- 레지스트리 인증서가 `CN=localhost`, SAN에 `192.168.6.1` 미포함 → TLS 이름 검증 실패.

### 변경 사항
- `wsl/scripts/00_prep_offline_fixed.sh`
  - 인증서 생성 시 `CN=${REGISTRY_HOST_IP}`로 설정하고 SAN에 `IP:${REGISTRY_HOST_IP},IP:127.0.0.1,DNS:localhost` 추가.
  - `REGISTRY_HOST_IP`/`REGISTRY_PORT` 변수화 및 전 구간 반영(포트포워딩/미러링/헬스체크 로그).
  - `registries.yaml` 생성 시 모든 미러 엔드포인트를 `https://${REGISTRY_HOST_IP}:${REGISTRY_PORT}`로 통일.
- 템플릿(`user-data-master.tpl`, `user-data-worker.tpl`)에서 CA/registries.yaml 복사 및 `update-ca-certificates` 실행 경로 확인.

### 검증 방법
- VM: `openssl s_client -connect 192.168.6.1:5000 -servername 192.168.6.1 -showcerts </dev/null | openssl x509 -noout -subject -ext subjectAltName`
- VM: `curl -vk https://192.168.6.1:5000/v2/`
- 클러스터: `kubectl -n kube-system get pods` 에서 기본 컴포넌트 Running 확인

### 비고
- 환경에 따라 `REGISTRY_HOST_IP`를 오버라이드 가능. 기본값은 `192.168.6.1`.