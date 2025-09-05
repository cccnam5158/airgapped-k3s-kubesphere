# 250904 - 외부(WSL) Nexus3 프라이빗 레지스트리 전환/일반화

## 목적
- 로컬 `registry:2` 컨테이너 대신, WSL에서 docker run으로 실행 중인 Nexus3를 기본 프라이빗 레지스트리로 사용
- 특정 도메인(예: gaiderunner.ai)에 종속되지 않도록 일반화(host:port 기반)
- **VM에서의 registry 인증 문제 해결**: registries.yaml에 인증 정보 포함
- **환경변수 자동 설정**: 사용자가 별도 설정 없이 바로 실행 가능하도록 개선

## 주요 변경 파일
- `wsl/scripts/00_prep_offline_fixed.sh`
  - **환경변수 자동 설정 함수 추가**: `setup_environment()` 함수로 모든 환경변수 자동 설정
  - **비밀번호 입력 요청**: `REGISTRY_PASSWORD`가 없으면 사용자에게 입력 요청 (기본값: `nam0941!@#`)
  - **환경변수 정보 출력**: 설정된 모든 환경변수를 로그로 표시
  - `USE_EXTERNAL_REGISTRY` 플래그 추가(기본 true)
  - `EXTERNAL_REGISTRY_PUSH_HOST`, `EXTERNAL_REGISTRY_PUSH_PORT` 환경변수로 푸시 엔드포인트 설정(기본 `localhost:5000`)
  - VM 풀 엔드포인트는 `REGISTRY_HOST_IP:REGISTRY_PORT` 유지(윈도우 portproxy 통해 WSL로 전달)
  - `docker login` + `/v2/` 헬스체크 추가(셀프사인 인증서 대응 `curl -k`)
  - 미러 타깃을 `${REGISTRY_PUSH_HOST}:${REGISTRY_PUSH_PORT}/<target>`로 통일
  - `registries.yaml`의 미러 엔드포인트를 `${REGISTRY_PULL_HOST}:${REGISTRY_PULL_PORT}`로 생성
  - **인증 정보 포함**: `configs.*.auth.username/password` 추가 (외부 레지스트리 모드에서)
  - `configs.*.tls.insecure_skip_verify`를 `REGISTRY_TLS_INSECURE`(기본 true)로 제어
  - 외부 모드에서는 로컬 인증서 생성/로컬 registry:2 기동 생략

## 실행 방법

### 🚀 간단한 실행 방법 (권장)
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

### 🔧 수동 환경변수 설정 (고급 사용자)
```bash
export USE_EXTERNAL_REGISTRY=true
export EXTERNAL_REGISTRY_PUSH_HOST=localhost
export EXTERNAL_REGISTRY_PUSH_PORT=5000
export REGISTRY_USERNAME=admin
export REGISTRY_PASSWORD='******'   # 환경변수만 사용 권장
# VM이 접근할 Windows Host IP:Port (기본 192.168.6.1:5000)
export REGISTRY_HOST_IP=192.168.6.1
export REGISTRY_PORT=5000
# Nexus3가 셀프사인 인증서라면 그대로 true 유지
export REGISTRY_TLS_INSECURE=true

bash wsl/scripts/00_prep_offline_fixed.sh
```

## VM 네트워크 경로
- VM → `REGISTRY_HOST_IP:REGISTRY_PORT` (예: `192.168.6.1:5000`) → Windows portproxy → WSL(내부 Nexus3)
- Windows 포트 프록시는 `scripts/setup-port-forwarding.ps1`로 구성

## 보안/인증서
- 공인 인증서가 아니라면 기본값(`REGISTRY_TLS_INSECURE=true`) 유지로 동작
- CA 배포 방식을 사용할 경우, `REGISTRY_TLS_INSECURE=false`로 설정하고 VM에 CA 설치 후 `registries.yaml`의 `configs`에 `ca_file` 추가 로직을 확장 가능

## 영향 범위
- 외부 인터넷 다운로드 경로 변경 없음
- 프라이빗 레지스트리 연결 체크 방식(`docker login` + `/v2/`)으로 전환
- k3s가 참조하는 `registries.yaml`이 VM 접근 가능한 호스트:포트를 가리키도록 생성됨
- **VM에서의 이미지 풀 인증 문제 해결**: UNAUTHORIZED 오류 방지

## 확인 체크리스트
- WSL: `docker login localhost:5000` 성공
- WSL: `curl -k https://localhost:5000/v2/` 200 OK
- Windows: `./scripts/setup-port-forwarding.ps1` 적용 후 `netsh interface portproxy show v4tov4`에 규칙 존재
- VM: `curl -k -u admin:password https://192.168.6.1:5000/v2/` 200 OK (인증 포함)
- VM: `sudo k3s ctr images pull 192.168.6.1:5000/registry.k8s.io/pause:3.10` 성공
- 클러스터: 워커 노드에서 이미지 풀 에러 없음

## 생성되는 registries.yaml 예시
```yaml
mirrors:
  "192.168.6.1:5000":
    endpoint:
      - "https://192.168.6.1:5000"
  # ... 기타 mirrors ...

configs:
  "192.168.6.1:5000":
    tls:
      insecure_skip_verify: true
    auth:
      username: admin
      password: nam0941!@#
```

## 문제 해결
- **UNAUTHORIZED 오류**: registries.yaml에 인증 정보가 포함되어 k3s가 정상적으로 이미지를 pull할 수 있음
- **TLS 인증서 오류**: `insecure_skip_verify: true`로 셀프사인 인증서 환경 지원
- **네트워크 연결**: Windows portproxy를 통한 VM → WSL 레지스트리 접근 경로 확보