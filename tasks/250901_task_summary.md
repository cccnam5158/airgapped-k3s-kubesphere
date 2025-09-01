# 250901 - 마스터 노드 k3s 복제/클러스터 생성 실패 원인 분석 및 수정

## 요약
- 증상: 마스터 노드에서 `k3s` 바이너리 복사 및 k3s 클러스터 부트스트랩이 완료되지 않음.
- 원인: `wsl/templates/user-data-master.tpl` 내 `setup-k3s-master.sh`에서 `${SEED_BASE}`가 `envsubst` 단계에서 비워져 경로가 깨짐. 일부 위치만 `${DOLLAR}{SEED_BASE}`로 이스케이프되어 있고, k3s 복제를 담당하는 두 군데는 이스케이프 누락됨.
- 영향: `k3s` 복사 실패 → `Error: k3s binary not found in seed`로 종료 → k3s 서버 미기동.

## 새로운 문제 발생 (250901 추가)
- 증상: PowerShell 스크립트 실행 시 `vmrun guest command syntax` 테스트에서 무한 대기
- 원인: `Test-VMRunGuestSyntax` 함수에서 `vmrun` 명령어 실행 시 타임아웃이나 오류 처리 부족
- 영향: VM 생성 후 준비 상태 확인 불가, 스크립트 진행 중단

## 변경 사항
- `user-data-master.tpl`의 `${SEED_BASE}` 2곳을 `${DOLLAR}{SEED_BASE}`로 수정하여 빌드 타임 변환을 방지하고 런타임에 올바른 경로로 평가되도록 함.
- `README.md`에 중요 변경 기록 추가.

## 해결 방안 (새로운 문제)
1. `Test-VMRunGuestSyntax` 함수에 타임아웃 추가
2. `vmrun` 명령어 실행 시 오류 처리 강화
3. 무한 대기 방지를 위한 fallback 메커니즘 구현

## 검증 방법
1) VM 내부 확인:
   - `sudo tail -n 200 /var/log/k3s-bootstrap.log`
   - `test -x /usr/local/bin/k3s && echo ok || echo missing`
   - `systemctl status k3s --no-pager -l || true`
   - `ss -lntp | grep 6443 || true`
2) 클러스터 상태:
   - `/usr/local/bin/k3s kubectl get nodes -o wide`
3) 재발 방지 확인:
   - `grep -n "\${DOLLAR}{SEED_BASE}" wsl/templates/user-data-master.tpl`
4) PowerShell 스크립트 문제 해결 확인:
   - `Test-VMRunGuestSyntax` 함수 타임아웃 동작 확인
   - VM 준비 상태 확인 정상 동작 확인

## 참고
- 템플릿에서 런타임 변수는 `${DOLLAR}{VAR}` 형태로 반드시 이스케이프 필요 (ISO 빌드 시 `envsubst` 사용).
- `vmrun` 명령어는 VM 상태에 따라 응답 시간이 길어질 수 있으므로 적절한 타임아웃 설정 필요.