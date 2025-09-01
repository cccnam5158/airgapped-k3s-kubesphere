# 250901 - 마스터 노드 k3s 복제/클러스터 생성 실패 원인 분석 및 수정

## 요약
- 증상: 마스터 k3s 서버가 정상 기동되지 않고, jq 등 유틸 패키지 미설치.
- 원인(1): Windows 스크립트에서 vmrun 인증 플래그가 명령 뒤에 붙어 게스트 명령 실패 → 준비/완료 상태 체크 실패.
- 원인(2): `user-data-master.tpl`의 runcmd가 부트스트랩 스크립트를 직접 실행하고 동시에 systemd 서비스도 시작하여 중복 실행 및 타이밍 이슈 가능.
- 원인(3): 네임서버 YAML flow sequence 사용으로 파서가 민감할 수 있어 블록 시퀀스로 변경 필요.
- 영향: 초기화 진행 상황 확인 불가, k3s 기동 타이밍 불안정, 일부 유틸 설치가 보이지 않는 증상.

## 새로운 문제 발생 (250901 추가)
- 증상: PowerShell 스크립트 실행 시 `vmrun guest command syntax` 테스트에서 무한 대기
- 원인: `Test-VMRunGuestSyntax` 함수에서 `vmrun` 명령어 실행 시 타임아웃이나 오류 처리 부족
- 영향: VM 생성 후 준비 상태 확인 불가, 스크립트 진행 중단

## 변경 사항
- `windows/Setup-VMs.ps1`: vmrun 인증 플래그 순서를 교정 (인증 플래그를 `runProgramInGuest` 앞에 위치)하여 게스트 명령 성공률 향상.
- `wsl/templates/user-data-master.tpl`: DNS `nameservers.addresses`를 블록 시퀀스로 변경.
- `wsl/templates/user-data-master.tpl`: runcmd에서 부트스트랩 스크립트 직접 실행을 제거하고 systemd 서비스만 사용하도록 변경(중복 실행 제거).
- 추후 문서: README에 주의사항 추가 예정.

## 해결 방안 및 상태
1. vmrun 인증 플래그 순서 교정 완료 (Wait-ForVMReady, Check-CompletionStatus).
2. 부트스트랩 중복 실행 제거 완료 (service만 사용).
3. 네임서버 블록 시퀀스 변경 완료.
4. ops 패키지 설치는 `/usr/local/seed/packages` 유무와 아카이브 존재 시에만 동작하도록 이미 설계됨. 설치 확인 로그는 `/var/log/k8s-ops-packages.log` 및 마커 `/var/lib/k8s-ops-packages-installed`로 확인.

## 검증 방법
1) VM 내부 확인:
   - `sudo tail -n 200 /var/log/k3s-bootstrap.log`
   - `test -x /usr/local/bin/k3s && echo ok || echo missing`
   - `systemctl status k3s --no-pager -l || true`
   - `ss -lntp | grep 6443 || true`
   - `journalctl -u k3s-bootstrap.service -b --no-pager | tail -n 200`
2) 클러스터 상태:
   - `/usr/local/bin/k3s kubectl get nodes -o wide`
3) ops 패키지 확인:
   - `dpkg -l | grep -E '(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)' || true`
   - `cat /var/lib/k8s-ops-packages-installed || true`
4) PowerShell 스크립트 동작 확인:
   - 게스트 에코 테스트 성공 여부 로그에 `[SUCCESS] VM <name> is ready for guest operations` 표시 확인
   - 완료 체크에서 `COPY_COMPLETE` 확인 메시지 출력

## 참고
- 템플릿에서 런타임 변수는 `${DOLLAR}{VAR}` 형태로 반드시 이스케이프 필요 (ISO 빌드 시 `envsubst` 사용).
- `vmrun` 명령어는 VM 상태에 따라 응답 시간이 길어질 수 있으므로 적절한 타임아웃 설정 필요.

## 현재 VM 상태 진단 결과 (250901 16:30)

### 문제점
1. **k3s 서비스 미존재**: `k3s.service`가 아예 생성되지 않음
2. **부트스트랩 서비스 미실행**: `k3s-bootstrap.service` 로그 없음
3. **ops 패키지 서비스 비활성화**: `k8s-ops-packages.service`가 disabled 상태
4. **일부 패키지 누락**: jq, sysstat, iftop, iotop, dstat, yq 등

### 원인 분석
- cloud-init의 runcmd에서 부트스트랩 스크립트 직접 실행을 제거했지만, systemd 서비스 활성화가 누락됨
- ops 패키지 서비스가 자동으로 활성화되지 않음

### 복구 단계
1. ops 패키지 서비스 활성화 및 실행
2. k3s 부트스트랩 서비스 활성화 및 실행
3. k3s 서비스 상태 확인

### 검증 방법
- `systemctl status k3s` - k3s 서비스 존재 확인
- `k3s kubectl get nodes` - 클러스터 상태 확인
- `dpkg -l | grep jq` - jq 패키지 설치 확인

## 복구 완료 상태 (250901 17:15)

### 해결된 문제들
1. ✅ **k3s 서비스 정상 동작**: 마스터 노드에서 k3s 서비스가 정상 실행 중
2. ✅ **이미지 임포트 성공**: 모든 필요한 컨테이너 이미지가 성공적으로 임포트됨
3. ✅ **핵심 파드들 정상 동작**: coredns, traefik, local-path-provisioner, metrics-server 모두 Running 상태
4. ✅ **워커 노드 조인 토큰 준비**: `K105b389db9d922774648db64dc55cb97fd48f8bb1c6eddc39c633c2711f6e4f33c::server:f2a16e45b04266e0315af59814b5990b`

### 워커 노드 조인 명령
```bash
# 각 워커 노드에서 실행
sudo k3s agent --server https://192.168.6.10:6443 --token K105b389db9d922774648db64dc55cb97fd48f8bb1c6eddc39c633c2711f6e4f33c::server:f2a16e45b04266e0315af59814b5990b
```

### 다음 단계
1. 워커 노드들에서 위 명령 실행
2. 마스터에서 `k3s kubectl get nodes`로 조인 확인
3. ops 패키지 설치 완료 확인
4. 전체 클러스터 기능 테스트

## 최종 완료 상태 (250901 17:20)

### 완전히 해결된 문제들
1. ✅ **k3s 서비스 정상 동작**: 마스터 노드에서 k3s 서비스가 정상 실행 중
2. ✅ **이미지 임포트 성공**: 모든 필요한 컨테이너 이미지가 성공적으로 임포트됨
3. ✅ **핵심 파드들 정상 동작**: coredns, traefik, local-path-provisioner, metrics-server 모두 Running 상태
4. ✅ **ops 패키지 설치 완료**: jq, htop, ethtool, iproute2, dnsutils, telnet, psmisc, sysstat, iftop, iotop, dstat 모두 설치됨
5. ✅ **워커 노드 조인 토큰 준비**: `K105b389db9d922774648db64dc55cb97fd48f8bb1c6eddc39c633c2711f6e4f33c::server:f2a16e45b04266e0315af59814b5990b`

### 설치된 ops 패키지 목록
- jq (1.6-2.1ubuntu3.1)
- htop (3.0.5-7build2)
- ethtool (1:5.16-1ubuntu0.2)
- iproute2 (5.15.0-1ubuntu2)
- dnsutils (1:9.18.30-0ubuntu0.22.04.2)
- telnet (0.17-44build1)
- psmisc (23.4-2build3)
- sysstat (12.5.2-2ubuntu0.2)
- iftop (1.0~pre4-7)
- iotop (0.6-24-g733f3f8-1.1ubuntu0.1)
- dstat (0.7.4-6.1)

### 워커 노드 조인 명령
```bash
# 각 워커 노드에서 실행
sudo k3s agent --server https://192.168.6.10:6443 --token K105b389db9d922774648db64dc55cb97fd48f8bb1c6eddc39c633c2711f6e4f33c::server:f2a16e45b04266e0315af59814b5990b
```

### 최종 검증 명령
```bash
# 마스터 노드에서 클러스터 상태 확인
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A

# ops 패키지 확인
jq --version
htop --version
```

### 다음 단계
1. 워커 노드들에서 조인 명령 실행
2. 마스터에서 `k3s kubectl get nodes`로 조인 확인
3. 전체 클러스터 기능 테스트
4. Kubesphere 설치 준비 완료

## 자동화 개선 사항 (250901 17:30)

### 해결된 문제들의 자동화 적용
1. ✅ **SEED_BASE 변수 설정 문제**: 부트스트랩 스크립트에서 고정 경로 `/usr/local/seed` 사용
2. ✅ **ops 패키지 설치 스크립트 경로 문제**: 패키지 디렉토리 경로를 고정하고 오프라인 설치 지원
3. ✅ **워커 노드 레지스트리 설정**: CA 인증서 및 registries.yaml 자동 복사
4. ✅ **vmrun 인증 플래그 순서**: Windows 스크립트에서 이미 수정 완료
5. ✅ **서비스 의존성 문제**: k3s-bootstrap.service와 k8s-ops-packages.service 간의 강제 의존성 제거
6. ✅ **vmrun 인증 플래그 중복 문제**: Test-VMRunGuestSyntax 및 Wait-ForVMReady 함수에서 인증 플래그 중복 제거

### 수정된 파일들
- `wsl/templates/user-data-master.tpl`: 부트스트랩 스크립트 및 ops 패키지 설치 스크립트 개선, 서비스 의존성 최적화
- `wsl/templates/user-data-worker.tpl`: 워커 노드 부트스트랩 스크립트 및 ops 패키지 설치 스크립트 개선, 서비스 의존성 최적화
- `wsl/scripts/01_build_seed_isos.sh`: 패키지 설치 스크립트 개선
- `windows/Setup-VMs.ps1`: vmrun 인증 플래그 중복 문제 해결

### 자동화된 기능들
1. **k3s 바이너리 복사**: 고정 경로에서 자동 복사
2. **레지스트리 설정**: registries.yaml 및 CA 인증서 자동 복사
3. **ops 패키지 설치**: tar.gz 압축 해제 및 오프라인 설치
4. **워커 노드 조인**: 마스터 API 대기 및 자동 조인
5. **이미지 임포트**: airgap 이미지 자동 임포트
6. **서비스 순차 실행**: ops 패키지 설치 후 k3s 부트스트랩 실행
7. **VM 준비 상태 확인**: vmrun 명령어 구문 오류 해결로 정확한 VM 상태 확인

### 향후 실행 방법
1. **ISO 빌드**: `./wsl/scripts/01_build_seed_isos.sh`
2. **VM 생성**: `./windows/Setup-VMs.ps1`
3. **자동 완료**: 모든 설정이 자동으로 적용됨

### 검증 방법
- 마스터 노드: `sudo k3s kubectl get nodes`
- 워커 노드: `sudo k3s kubectl get nodes`
- ops 패키지: `dpkg -l | grep -E "(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)"`