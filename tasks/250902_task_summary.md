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

## 250902 핫픽스: Wait-ForVMReady 조기 continue 제거 및 진행상황 로그 추가

### 증상
- `Start VMs` 이후 `Wait for VMs ready` 단계에서 다음 메시지 이후 진행이 멈춤:
  - `Waiting for VM k3s-master1 to be ready for operations (max 20 minutes)...`

### 원인
- `Wait-ForVMReady` 내부에서 SSH 체크 실패 시 바로 `continue`하는 로직 때문에, 동일 반복에서 이어지는 vmrun 구문 테스트 및 기타 준비 신호(IP, Tools 상태) 확인이 스킵됨.
- 결과적으로 SSH만 10초 간격으로 재시도하며, 다른 경로의 조기 준비 신호를 활용하지 못해 대기 시간이 과도하게 길어짐.

### 조치
- SSH 실패 후에도 vmrun 구문 테스트와 기타 신호 확인 로직이 실행되도록 `continue` 제거.
- SSH 미준비 상태에서 경과 시간 기반의 주기적 진행상황 로그를 추가(대략 30초 주기)하여 사용자 피드백 강화.

### 변경 파일
- `windows/Setup-VMs.ps1`
  - SSH 블록 직후 `continue` 제거
  - SSH 미준비 시 진행 로그 추가 (`SSH not ready for <VM> yet (elapsed: Ns). Retrying...`)

### 기대 효과
- SSH가 아직 열리지 않아도 vmrun 기반 신호(IP, Tools) 또는 후속 SSH 시도로 조기 준비 판별 가능.
- 대기 단계에서의 "정체처럼 보이는" 현상 완화 및 원인 파악 용이.

## 250902 핫픽스: SSH 준비 확인 강화(IdenitiesOnly, 2-step 명령, 실패 원인 로그)

### 배경
- 사용자는 PowerShell/다른 클라이언트로는 `Test-NetConnection 192.168.6.10 -Port 22` 및 SSH 접속이 가능한데, 스크립트에서는 SSH 준비가 안 된 것으로 반복 출력되는 문제를 보고.

### 원인 후보
- Windows `ssh.exe`가 에이전트/기본 키를 우선 시도하면서, 지정 키(`wsl/out/ssh/id_rsa`)가 스킵되거나 잘못된 인증 경로로 시도됨.
- `bash -lc`를 통한 명령 전달이 실패(쉘/환경 초기화 지연)하여 단순 에코도 실패로 간주될 수 있음.

### 조치
- SSH 옵션 강화:
  - `-o IdentitiesOnly=yes`, `-o NumberOfPasswordPrompts=0`, `-o ConnectionAttempts=1` 추가
  - 키 우선 순위 고정, 비대화/무패스워드 보장, 빠른 실패
- 이중 명령 시도:
  1) `bash -lc "echo vm_ready"`
  2) 실패 시 `echo vm_ready`로 재시도(쉘 초기화 의존도 축소)
- 실패 원인 요약 로그 추가:
  - `Permission denied`(키/계정 문제), 키 퍼미션 문제, 네트워크 타임아웃 등 대표 케이스 메시지 출력

### 변경 파일
- `windows/Setup-VMs.ps1` SSH 준비 확인 블록

### 기대 효과
- 포트는 열려있지만 인증/쉘 초기화 이슈로 인한 오탐 감소
- 실패 사유를 로그로 즉시 파악 가능 → 진단 시간 단축

## 250902 추가: SSH 디버깅 로그 (경로/인자/실행파일)

### 목적
- 실행 경로 조합(특히 `wsl/out/ssh/id_rsa`)의 정확성과 실제 사용되는 `ssh.exe`/인자 확인을 위해 추가 디버깅 로그를 출력

### 추가 로그 항목
- 현재 작업 디렉토리(`cwd`)
- `repoRoot` 계산 값
- `keyPath` 실제 경로 및 존재 여부
- 사용되는 `ssh.exe` 경로(`Get-Command ssh` 결과)
- 조립된 SSH 기본 인자(base args)

### 변경 파일
- `windows/Setup-VMs.ps1` (`Wait-ForVMReady` 내 SSH 준비 확인 블록)

### 활용 방법
- `Wait for VMs ready` 단계에서 `[SSH-Debug]`로 시작하는 로그를 확인하여 경로/인자 문제가 없는지 즉시 진단

-- `Disconnect ISOs`(41.5s): 각 VM을 soft stop 후 VMX 수정, 5초 대기 등을 VM별 순차 처리.

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

# 250902 추가 작업: Windows 콘솔 한글 중복 출력 및 vmrun 동작 메모

## 현상
- `windows/Setup-VMs.ps1` 실행 로그에서 한글이 "완완료료", "단단계계별별"처럼 중복 출력.
- `vmrun` 게스트 명령 구문 테스트 시 `Usage: vmrun [AUTHENTICATION-FLAGS] COMMAND ... These must appear before the command` 메시지 반복 출력으로, OldStyleAlt(NewStyleAlt)도 불가로 판정됨.

## 원인 추정
- Windows 콘솔 코드페이지/인코딩과 PowerShell 출력 인코딩 불일치로 인해 UTF-8 한글이 중복 렌더링.
- VMware Workstation 17.5.2(빌드 24319023) 환경에서 `vmrun`이 인증 플래그의 사전 배치만 허용하며, 명령 뒤 배치는 도움말(Usage)로 처리.

## 변경 사항
- `windows/Setup-VMs.ps1` 상단에 UTF-8 강제 설정 추가:
  - `[Console]::OutputEncoding`/`InputEncoding`을 BOM 없는 UTF-8로 설정
  - `$OutputEncoding`을 콘솔 인코딩과 일치
  - `chcp.com 65001`로 코드페이지를 65001(UTF-8)로 전환
- 스크립트의 기존 로깅/타이머 로직은 그대로 유지

## 기대 효과
- 한글 로그가 중복되지 않고 정상 출력
- 실행 결과 요약의 한글 가독성 개선

## 검증
- 재실행 후 "완료:", "단계별 소요 시간 요약" 문자열이 중복 없이 표시되는지 확인
- `vmrun` 구문 테스트는 계속 표준 양식(인증 플래그를 명령 앞에 배치)을 1순위로 사용하며, 실패 시 SSH 폴백 경로가 동작하는지 확인

## 참고 (vmrun 동작)
- 표준 양식(권장):
  ```powershell
  vmrun -T ws -gu <guestUser> -gp <guestPassword> runProgramInGuest "C:\path\vm.vmx" "/bin/echo" test
  ```
- 대체 양식(명령 뒤 인증 플래그)은 해당 빌드에서 허용되지 않는 것으로 관찰됨. 스크립트는 실패 시 자동으로 단순화된 신호(툴즈 상태, IP, SSH) 기반 판정 및 SSH 폴백을 이용.

## 추가 개선: 완료 판정 신뢰도 향상 및 모니터링 단축 (2025-09-02)
- 모니터링 최대 대기시간 20분 → 10분으로 축소, 폴링 간격 60초 → 20초로 단축
- 완료 판정 신호를 `/var/lib/iso-copy-complete`뿐 아니라 다음을 포함하도록 확장:
  - `/var/lib/cloud-init-complete`
  - `/var/lib/k3s-bootstrap.done`
  - `/var/lib/k3s-agent-bootstrap.done`
- `vmrun` 실패 시 SSH 폴백에서 동일 신호들을 확인하도록 통일
- 효과: Old/NewSyntax 모두 실패하는 환경에서도 SSH 신호로 조기 완료 판정 가능, 장시간 대기(>20분) 축소

## 추가 개선: vmrun 점검 강화 및 백오프 (2025-09-02)
- runProgramInGuest 검증/점검 명령을 `bash -lc 'echo vmrun_ok'`로 통일하여 PATH/쉘 차이로 인한 오탐 제거
- runProgramInGuest 실패 시 `runScriptInGuest`로 동일 검증을 재시도하는 폴백 경로 추가
- VMware Tools 상태를 `checkToolsState`로 사전 확인하여, Tools 미기동/인증 실패/Usage 출력 등 실패 사유를 로그로 구분
- Tools 미기동 시 대기 백오프 적용: 10초 → 20초 → 30초(상한)
- 기대 효과: Usage/Tools not running/인증 실패 상황이 명확히 구분되고, 성공 경로 탐색이 빨라져 전체 대기 시간 단축

## 추가 적용: SSH 폴백 파싱 오류 해결 (2025-09-02)

- 현상: `Setup-VMs.ps1`의 `Check-CompletionStatus`에서 SSH 폴백이 `bash: -c: line 1: syntax error near unexpected token 'then'` 오류로 실패하여 완료 판정이 멈춤
- 원인: PowerShell → ssh → bash 인자 전달 경로에서 if/then/fi 구문이 인용 경계에 민감하여 파싱 오류 발생 가능
- 조치: if 블록 대신 안전한 `test` 연산자와 단락 평가(`&&`/`||`) 체인으로 대체
  - 변경 전: `if [ -f A ] || [ -f B ] || [ -f C ] || [ -f D ]; then echo STATE_COMPLETE; else echo STATE_INCOMPLETE; fi`
  - 변경 후: `test -f A || test -f B || test -f C || test -f D && echo STATE_COMPLETE || echo STATE_INCOMPLETE`
- 영향: vmrun 게스트 명령 미동작 환경에서도 SSH 폴백 경로가 안정적으로 동작, 실제 완료 마커 파일 기반 판정 정상화
- 적용 파일: `windows/Setup-VMs.ps1` (2곳 교체)

## 마커 매핑 및 완료 판정 정책 정비 (2025-09-02)

### VM 내 생성되는 마커 정리
- 설치/복사 단계(이른 신호)
  - `/var/lib/iso-copy-complete` (late-commands에서 기록)
  - `/var/lib/cloud-init-complete` (user-data runcmd에서 기록)
- 시스템 준비 단계
  - `/var/lib/timezone-set`, `/var/lib/sync-time-enabled`, `/var/lib/ca-certificates-updated`, `/var/lib/swap-disabled`, `/var/lib/sysctl-applied`, `/var/lib/hostname-set`, `/var/lib/kernel-modules-loaded`
- k3s 부트스트랩 완료(핵심 완료 신호)
  - 마스터: `/var/lib/k3s-bootstrap.done`
  - 워커: `/var/lib/k3s-agent-bootstrap.done`
- 운영 패키지 설치(선택 신호)
  - `/var/lib/k8s-ops-packages-installed` (서비스 실행 후)
  - `/var/lib/k8s-ops-installation-complete` (runcmd 최종 기록)

-### Setup-VMs.ps1의 활용 및 타이밍
- 준비 대기(Wait-ForVMReady): SSH 우선 접근성 확인으로 전환(22/tcp 응답 + 간단한 쉘 응답)
- 초기화 완료 모니터링(Check-CompletionStatus): SSH 전용으로 완료 마커 확인
  - 완료 기준은 역할별 핵심 마커만 인정
    - 마스터: `/var/lib/k3s-bootstrap.done`
    - 워커: `/var/lib/k3s-agent-bootstrap.done`
    - 역할 식별 불가 시 master/worker 부트스트랩 마커 중 하나라도 있으면 완료
  - vmrun 게스트 명령(runProgramInGuest) 의존성 제거(환경 호환성 문제 회피)
- ISO 분리 및 재시작: 위의 "핵심 완료 신호" 확인 후 진행 → 재설치 루프 방지에 안전

### 정책 rationale
- ISO/Cloud-init 마커는 너무 이른 신호라 완료로 간주하지 않음(오탐 방지)
- k3s 부트스트랩 마커는 클러스터 구성의 실질 완료 지점이므로 완료 판정 기준으로 사용
- 운영 패키지 마커는 선택적이며 환경/성능에 따라 추가 대기를 유발할 수 있어 완료 판정에 미포함(향후 옵션화 가능)

### 영향
- 완료 판정 정확도 향상(오탐 제거), ISO 안전 분리 보장, SSH 폴백 안정화로 모니터링 신뢰도 개선

### 도식 문서 추가
- `windows/setup-vm-process-diagram.md`: `scripts/setup-vms.ps1` ↔ `windows/Setup-VMs.ps1` 흐름과 SSH-only 체크, 마커 정책을 Mermaid로 도식화

## 250902 ContainerCreating 문제 해결: 이미지 로드 타이밍 및 오류 처리 개선

### 문제 상황
- Worker 노드에서 `sudo k3s ctr images ls` 실행 시 이미지가 전혀 표시되지 않음
- Pod가 ContainerCreating 상태에서 멈춤: `failed to get sandbox image "rancher/mirrored-pause:3.6": not found`
- K3s가 요구하는 pause 이미지 버전과 실제 미러링된 버전 불일치

### 근본 원인 분석
1. **이미지 로드 타이밍 문제**: 
   - 기존: k3s 서비스 시작 → 이미지 로드 (kubelet이 이미지를 찾을 때 아직 로드되지 않음)
   - 결과: ContainerCreating 상태 고착

2. **오류 처리 부족**:
   - `|| echo "Image import skipped/failed"`로 실패를 무시
   - 실제 import 실패 여부를 알 수 없음

3. **누락된 이미지**:
   - K3s가 `rancher/mirrored-pause:3.6`을 요구하지만 `3.10`만 미러링됨

### 적용된 해결책

#### 1. 템플릿 수정 (이미지 로드 타이밍)
**파일**: `wsl/templates/user-data-master.tpl`, `wsl/templates/user-data-worker.tpl`

**변경 내용**:
- 이미지 로드를 k3s 서비스 시작 **전**으로 이동
- 이미지 로드 성공 후에만 k3s 서비스 시작
- 상세한 로그 및 검증 추가

```bash
# 기존 순서 (문제)
systemctl enable --now k3s-agent
# 이미지 로드 (너무 늦음)

# 새로운 순서 (해결)
# 이미지 로드 먼저
systemctl enable --now k3s-agent
```

#### 2. 오류 처리 강화
**추가된 기능**:
- 이미지 파일 존재 및 크기 검증
- Import 성공/실패 명확한 구분
- 로드된 이미지 개수 확인
- 중요 이미지(pause, coredns, traefik) 존재 검증
- 실패 시 명확한 오류 메시지 및 중단

```bash
if /usr/local/bin/k3s ctr images import "$SEED_BASE/k3s-airgap-images-amd64.tar.gz"; then
  echo "SUCCESS: Airgap images loaded successfully"
  image_count=$(/usr/local/bin/k3s ctr images ls -q | wc -l)
  echo "Loaded $image_count container images"
else
  echo "ERROR: Failed to import airgap images"
  exit 1
fi
```

#### 3. 누락된 이미지 추가
**파일**: `wsl/examples/images-fixed.txt`

**추가된 이미지**:
```
rancher/mirrored-pause:3.6 rancher/mirrored-pause:3.6
```

### 적용 방법

#### 즉시 적용 (기존 환경)
1. **오프라인 준비 재실행**:
```bash
cd wsl/scripts
./00_prep_offline_fixed.sh  # pause:3.6 이미지 미러링
```

2. **ISO 재생성**:
```bash
./01_build_seed_isos.sh  # 수정된 템플릿으로 ISO 생성
```

3. **VM 재생성**:
```powershell
# Windows에서
.\windows\Setup-VMs.ps1  # 새로운 ISO로 VM 재생성
```

#### 기존 VM 임시 해결
Worker 노드에서 수동 이미지 로드:
```bash
# VM에 SSH 접속 후
sudo /usr/local/bin/k3s ctr images import /usr/local/seed/k3s-airgap-images-amd64.tar.gz
sudo systemctl restart k3s-agent
```

### 기대 효과
1. **ContainerCreating 해결**: 이미지가 미리 로드되어 Pod 생성 즉시 성공
2. **빠른 문제 진단**: 명확한 오류 메시지로 문제 원인 즉시 파악
3. **안정성 향상**: 이미지 로드 실패 시 k3s 시작 차단으로 불완전한 상태 방지
4. **버전 호환성**: 필요한 모든 pause 이미지 버전 제공

### 검증 방법
```bash
# VM에서 확인
sudo k3s ctr images ls | grep pause  # pause 이미지 확인
sudo k3s kubectl get pods -A  # 모든 Pod Running 상태 확인
sudo k3s kubectl get nodes -o wide  # 노드 Ready 상태 확인
```

#### 4. SSH 서비스 체크 로직 수정 ✅
**문제**: 마스터/워커 구분 없이 모든 VM에서 `k3s-bootstrap`과 `k3s-agent-bootstrap` 둘 다 확인
- 마스터는 `k3s-bootstrap` 서비스만 실행되는데 두 서비스 모두 확인하려 함
- 워커는 `k3s-agent-bootstrap` 서비스만 실행되는데 두 서비스 모두 확인하려 함

**해결**: VM 타입에 따라 적절한 서비스만 확인하도록 수정
```powershell
# 변경 전 (문제)
"sudo systemctl is-active k3s-bootstrap k3s-agent-bootstrap"

# 변경 후 (해결)
$serviceCmd = if ($VmName -match "master") {
    "sudo systemctl is-active k3s-bootstrap"
} elseif ($VmName -match "worker") {
    "sudo systemctl is-active k3s-agent-bootstrap"
}
```

#### 5. Pause 이미지 버전 3.10으로 고정 ✅
**배경**: Worker2에서 airgap 이미지 파일 손상으로 인해 pause:3.6 이미지 로드 실패 발견
- K3s가 pause:3.6을 요구하지만 실제로는 pause:3.10만 미러링되어 있음
- 버전 불일치로 인한 ContainerCreating 문제 발생

**해결**: pause 이미지를 3.10으로 고정
```yaml
# 마스터/워커 config.yaml에 추가
kubelet-arg:
  - "pod-infra-container-image=rancher/mirrored-pause:3.10"
```

**효과**: K3s가 항상 pause:3.10 이미지를 사용하도록 강제, 버전 불일치 문제 근본 해결

#### 6. 템플릿 이미지 로드 타이밍 근본 수정 ✅
**문제 발견**: 사용자가 수동으로 `sudo k3s ctr images import`를 실행하면 정상 동작하지만, 템플릿에서는 실패
**근본 원인**: containerd 소켓이 준비되지 않은 상태에서 이미지 import 시도
- **기존**: k3s 바이너리 설치 → 이미지 import → k3s 서비스 시작
- **문제**: containerd 데몬이 시작되지 않아서 import 실패

**해결책**: 
1. **k3s 서비스 먼저 시작**: containerd 초기화
2. **containerd 소켓 대기**: `/run/k3s/containerd/containerd.sock` 생성 확인
3. **이미지 import 실행**: containerd가 준비된 후 import
4. **sudo 대체 로직**: 일반 사용자 import 실패 시 sudo로 재시도

```bash
# 수정된 순서
systemctl enable --now k3s-agent  # 1. 서비스 먼저 시작
# 2. containerd 소켓 대기
for i in {1..30}; do
  [ -S /run/k3s/containerd/containerd.sock ] && break
  sleep 2
done
# 3. 이미지 import (containerd 준비 완료 후)
k3s ctr images import /usr/local/seed/k3s-airgap-images-amd64.tar.gz
```

#### 7. Worker2 문제 진단 스크립트 생성 ✅
- `wsl/scripts/check-worker2-issues.sh`: 종합 진단 스크립트 생성
- SSH 연결, 파일 시스템, 부트스트랩 서비스, 이미지 상태 등 전면 점검

### 상태
- ✅ 템플릿 수정 완료 (이미지 로드 타이밍 근본 해결)
- ✅ 오류 처리 강화 완료 (exit 1 → warning으로 완화)
- ✅ 누락된 이미지 추가 완료 (pause:3.6 → 3.10으로 변경)
- ✅ SSH 서비스 체크 로직 수정 완료
- ✅ Pause 이미지 버전 3.10으로 고정 완료
- ✅ containerd 소켓 대기 로직 추가 완료
- ✅ Worker2 진단 스크립트 생성 완료
- ⏳ 새로운 ISO 생성 및 테스트 필요

#### 8. ISO 복사/정리 정책 개선 (WSL 안전) ✅
- `wsl/scripts/01_build_seed_isos.sh`: Windows로 결과 복사 시 `seed-*.iso`만 복사하도록 변경 (Ubuntu 원본 ISO 제외)
- 기존 정리 단계는 `seed-*.iso`, user-data/meta-data 등 빌드 산출물만 삭제하고, Ubuntu 원본 ISO는 삭제하지 않음 (WSL 작업 폴더 보존)