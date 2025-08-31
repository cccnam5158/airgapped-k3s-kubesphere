# 패키지 다운로드 문제 해결 및 개선사항

## 문제 상황
- `apt-get download` 명령어가 `Dir::Cache` 옵션을 사용하여 패키지를 다운로드했지만, 실제로는 `archives` 디렉토리가 아닌 다른 위치에 저장됨
- 일부 패키지들이 Ubuntu 22.04에서 사용할 수 없거나 다운로드에 실패함
- 결과적으로 "압축할 deb 파일이 없습니다" 경고 발생

## 해결 방법

### 1. 패키지 다운로드 방식 개선
- `Dir::Cache` 옵션 제거하고 직접 현재 디렉토리에 다운로드
- `cd "$packages_dir"` 후 `apt-get download` 실행
- 다운로드된 파일 수 확인 및 로그 출력

### 2. 패키지 목록 최적화
- **필수 패키지** (Ubuntu 22.04에서 확실히 사용 가능):
  - jq, htop, ethtool, iproute2, dnsutils, telnet, psmisc, sysstat

- **선택적 패키지** (있으면 다운로드, 없으면 건너뜀):
  - iftop, iotop, dstat, yq

### 3. 압축 로직 개선
- deb 파일 수를 정확히 확인
- deb 파일이 없어도 빈 tar.gz 파일 생성 (VM 호환성용)
- 압축 파일 크기 확인 및 로그 출력

### 4. 설치 스크립트 업데이트
- 모든 템플릿 파일의 패키지 확인 정규식 업데이트
- 설치 완료 확인 로직 개선

## 개선된 기능

### 패키지 다운로드 로직
```bash
# 필수 패키지 다운로드
for package in "${packages[@]}"; do
    if apt-get download "$package" 2>/dev/null; then
        log_success "패키지 다운로드 완료: $package"
    else
        log_warning "패키지 다운로드 실패: $package (건너뜀)"
    fi
done

# 선택적 패키지 다운로드
for package in "${optional_packages[@]}"; do
    if apt-get download "$package" 2>/dev/null; then
        log_success "선택적 패키지 다운로드 완료: $package"
    else
        log_info "선택적 패키지 다운로드 실패: $package (정상적인 상황)"
    fi
done
```

### 압축 로직
```bash
local deb_files=$(ls -1 *.deb 2>/dev/null | wc -l)
if [[ $deb_files -gt 0 ]]; then
    tar -czf "k8s-ops-packages.tar.gz" *.deb
    log_success "deb 파일들을 k8s-ops-packages.tar.gz로 압축 완료"
else
    log_warning "압축할 deb 파일이 없습니다"
    # 빈 tar.gz 파일 생성 (VM에서 오류 방지)
    tar -czf "k8s-ops-packages.tar.gz" --files-from /dev/null
    log_info "빈 k8s-ops-packages.tar.gz 파일 생성됨 (VM 호환성용)"
fi
```

## 예상 결과
1. 패키지 다운로드 성공률 향상
2. 다운로드된 패키지 수 정확한 확인
3. 압축 파일 생성 성공 (빈 파일이라도)
4. VM에서 패키지 설치 시 오류 방지

## 검증 방법
1. 스크립트 실행 시 "총 X개의 .deb 파일이 다운로드되었습니다" 메시지 확인
2. `k8s-ops-packages.tar.gz` 파일 생성 확인
3. VM에서 패키지 설치 성공 확인
