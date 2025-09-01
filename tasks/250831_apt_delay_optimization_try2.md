# 250831 apt-config 지연 최적화

- 변경점
  - `autoinstall.apt.preserve_sources_list: false` 로 변경
  - `curtin.apt` 하위로 `conf:`/`sources:` 들여쓰기 교정
  - `nameservers.addresses` 블록 시퀀스로 교정
- 기대효과
  - `curtin command apt-config` 단계에서 네트워크 미러 탐색 차단, 타임아웃 1초 적용
- 적용 방법
  - `wsl/scripts/01_build_seed_isos.sh` 실행 → 새 ISO로 VM 설치
- 비고
  - 크리티컬 변경: 에어갭 환경 기본 동작 수정(README 반영 필요) [[memory:7577603]]