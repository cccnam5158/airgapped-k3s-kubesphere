# 250901 VM Guest Ready Diagnosis & Improvements

- **이슈 요약**: Windows `Setup-VMs.ps1` 실행 시 "is ready for guest operations" 로그가 반복 출력되고, ISO 복사 완료 판정이 지연될 수 있음.
- **원인**:
  - 게스트 준비 판정이 주기 재시도로 인해 반복 로그 발생
  - 게스트 자격 증명 하드코딩(`ubuntu/ubuntu`)으로 실제 비밀번호 변경 시 인증 지연
  - 완료 신호(`/var/lib/iso-copy-complete`) 단일 의존으로 타이밍 문제시 대기 연장
- **개선 내용**:
  - VMware Tools 상태(`checkToolsState`) 기반 대기, 상태 변화시에만 1회 로그
  - `-gu/-gp` 파라미터화(스크립트 인자/환경변수 `INSTALL_USER_PASSWORD` 연동)
  - runProgramInGuest 결과 문자열 `Trim()` 처리로 비교 신뢰성 향상
  - `/usr/local/seed` 존재 시 ISO 복사 완료로 간주하는 보조 신호 추가
  - VM 내부(runcmd)에서 `/usr/local/seed`가 있으면 `/var/lib/iso-copy-complete` 보강 생성
- **영향**:
  - 진행 로그 노이즈 감소, 완료 판정 신뢰성/속도 향상, 사용자 비밀번호 커스터마이즈 호환성 확보

## 완료 체크리스트
- [x] `windows/Setup-VMs.ps1` 개선(자격 증명 파라미터화, Tools 상태 대기, Trim)
- [x] `user-data-master.tpl` runcmd 보강 마커 추가
- [x] `user-data-worker.tpl` runcmd 보강 마커 추가


