# 250829 템플릿 DOLLAR 이스케이프 점검/적용

## 배경
`envsubst` 실행 시 런타임 셸 변수(`$i`, `$p`, `$SEED_BASE` 등)가 빌드 타임에 비어지거나 오염되는 문제를 방지하기 위해 `${DOLLAR}{VAR}` 형태로 이스케이프가 필요합니다. 본 작업은 해당 누락 구간을 점검하여 일관되게 적용합니다.

## 범위
- `wsl/templates/user-data-master.tpl`
  - `sync-time.sh` 스크립트 전반의 런타임 변수 참조에 `${DOLLAR}` 적용
- `wsl/templates/user-data-worker.tpl`
  - `setup-k3s-worker.sh`의 진행 메시지에서 `$i` → `${DOLLAR}i` 보강

## 변경 사항
- 마스터 템플릿 `sync-time.sh` 내부:
  - `log`, `dbg` 함수의 `$1` → `${DOLLAR}1`
  - `resolve_seed_file`, `sync_with_wsl_host`, `choose_and_set_time` 전 구간의 `$var`, `${var}` 참조를 `${DOLLAR}var`, `${DOLLAR}{var}`로 치환
  - 빌드 타임 치환 대상(대문자 환경변수: `REGISTRY_HOST_IP`, `REGISTRY_PORT`)은 유지
  - `agetty` 오버라이드의 `$TERM` → `${DOLLAR}TERM`
  - `setup-k3s-master.sh`의 진행표시 `${DOLLAR}i` 출력, `Using local seed at`의 `${DOLLAR}{SEED_BASE}` 출력 보강
- 워커 템플릿:
  - 에이전트 조인 대기 로그에서 `$i`를 `${DOLLAR}i`로 변경
  - `agetty` 오버라이드의 `$TERM` → `${DOLLAR}TERM`

## 검증 방법
- `wsl/scripts/01_build_seed_isos.sh` 실행 전 `envsubst`로 렌더링된 결과에서 `${DOLLAR}`가 `$`로 남아있는지 확인
- 생성된 ISO의 해당 스크립트 본문에서 런타임 변수들이 원형 `$VAR`/`${VAR}` 형태로 유지되는지 확인

## 비고
- 빌드 타임 치환 대상(대문자 환경 변수)은 그대로 두고, 런타임 셸 변수만 `${DOLLAR}`로 보호했습니다.

