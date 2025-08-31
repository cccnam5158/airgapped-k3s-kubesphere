# 패키지 다운로드 디렉토리 정리

## 작업 개요
- deb 패키지들이 `wsl/scripts/` 디렉토리에 직접 다운로드되어 지저분한 상태
- `wsl/scripts/ops-packages/` 디렉토리로 다운로드 위치 변경
- 프로젝트 구조 정리 및 가독성 향상

## 문제 상황
- 현재 deb 패키지들이 `wsl/scripts/` 디렉토리에 직접 다운로드됨
- 스크립트 파일들과 패키지 파일들이 섞여 있어 디렉토리가 지저분함
- git 추적에서 제외되지 않아 불필요한 파일들이 포함될 수 있음

## 작업 내용
1. `wsl/scripts/01_build_seed_isos.sh` 수정
   - 패키지 다운로드 디렉토리를 `wsl/scripts/ops-packages/`로 변경
   - 다운로드 후 압축 파일을 VM용 디렉토리로 복사
   - 작업 디렉토리 복원 로직 추가

2. `.gitignore` 파일 업데이트
   - `wsl/scripts/ops-packages/` 디렉토리 추가

3. `README.md` 파일 업데이트
   - 프로젝트 구조에 새로운 디렉토리 반영

## 상태
- [x] 01_build_seed_isos.sh 수정
- [x] .gitignore 업데이트
- [x] README.md 업데이트
- [ ] 테스트 및 검증

## 완료된 작업

### 1. ✅ 01_build_seed_isos.sh 수정
- **패키지 다운로드 디렉토리 변경**:
  ```bash
  # 기존: $files_dir/packages (VM용 디렉토리에서 직접 다운로드)
  # 변경: $(dirname "$0")/ops-packages (스크립트 디렉토리 하위)
  local download_dir="$(dirname "$0")/ops-packages"
  mkdir -p "$download_dir"
  ```

- **다운로드 프로세스 개선**:
  ```bash
  # 1. ops-packages 디렉토리에서 다운로드
  cd "$download_dir"
  
  # 2. 패키지 다운로드 및 압축
  # 3. 압축 파일을 VM용 디렉토리로 복사
  cp "k8s-ops-packages.tar.gz" "$packages_dir/"
  
  # 4. 작업 디렉토리 복원
  cd "$(dirname "$0")"
  ```

- **로깅 개선**:
  ```bash
  log_info "패키지 다운로드 위치: $download_dir"
  log_info "VM용 패키지 위치: $packages_dir"
  ```

### 2. ✅ .gitignore 업데이트
```gitignore
# Build outputs and large files
wsl/out/
wsl/iso/
wsl/registry/
wsl/scripts/ops-packages/  # 새로 추가
```

### 3. ✅ README.md 업데이트
```markdown
│   ├── scripts/                # WSL2 실행 스크립트
│   │   ├── 00_prep_offline_fixed.sh # 오프라인 준비
│   │   ├── 01_build_seed_isos.sh # Seed ISO 생성
│   │   ├── 02_wait_and_config.sh # 클러스터 설정
│   │   ├── check-vm-packages.sh # 패키지 점검
│   │   ├── fix-vm-packages.sh   # 패키지 복구
│   │   └── ops-packages/        # K8s 운영 패키지 다운로드 디렉토리 (자동 생성)
```

## 새로운 디렉토리 구조

### 다운로드 프로세스
```
1. wsl/scripts/ops-packages/     # 패키지 다운로드 위치
   ├── jq_1.6-2.1ubuntu3.1_amd64.deb
   ├── htop_3.0.5-7build2_amd64.deb
   ├── ...
   └── k8s-ops-packages.tar.gz   # 압축 파일

2. wsl/out/ubuntu-seed-work/     # VM용 파일 위치
   └── files/packages/
       ├── k8s-ops-packages.tar.gz  # 복사된 압축 파일
       └── install-packages.sh      # 설치 스크립트
```

### 장점
- **깔끔한 구조**: 스크립트와 패키지 파일 분리
- **git 추적 제외**: ops-packages 디렉토리는 .gitignore에 포함
- **재사용성**: 다운로드된 패키지를 다른 용도로도 활용 가능
- **디버깅 용이**: 패키지 다운로드 상태를 쉽게 확인 가능

## 다음 단계
- 실제 스크립트 실행 테스트
- 패키지 다운로드 및 압축 과정 검증
- VM에서 패키지 설치 테스트

## 사용법

### 패키지 다운로드 확인
```bash
# 다운로드된 패키지 확인
ls -la wsl/scripts/ops-packages/

# 압축 파일 확인
ls -la wsl/scripts/ops-packages/k8s-ops-packages.tar.gz
```

### 패키지 정리
```bash
# 필요시 패키지 디렉토리 정리
rm -rf wsl/scripts/ops-packages/
```

### 재다운로드
```bash
# 01_build_seed_isos.sh 재실행 시 자동으로 다시 다운로드
./wsl/scripts/01_build_seed_isos.sh
```
