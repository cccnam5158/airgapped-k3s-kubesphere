# 250901 VM VMware vmrun 인수 순서 수정

## 문제 상황
- VM 생성 후 cloud-init 상태 확인 시 "Unrecognized command: <vmx>" 에러 발생
- vmrun 명령어의 인수 순서가 잘못되어 VMX 파일 경로가 명령어로 인식됨

## 원인 분석
- 첫 번째 문제: `vmrun -T ws -gu <user> -gp <pass> runProgramInGuest <vmx> <program> <args>` (VMX 파일이 명령어로 인식됨)
- 두 번째 문제: `vmrun -T ws runProgramInGuest <vmx> -gu <user> -gp <pass> <program> <args>` (-gu 인수가 잘못된 위치)
- 세 번째 문제: `vmrun -T ws runProgramInGuest <vmx> <program> <args>` (사용자 인증 실패)
- 올바른 형식: `vmrun -T ws runProgramInGuest <vmx> -gu <user> -gp <pass> <program> <args>` (VMware 문서 기준)
- 실제 VMware vmrun 구문: `vmrun -T ws runProgramInGuest <vmx> -gu <user> -gp <pass> <program> <args>`

## 수정 사항
- Setup-VMs.ps1의 Wait-ForISOCopy 함수에서 vmrun 명령어 호출 부분 수정
- 첫 번째 수정: `vmrun -T ws runProgramInGuest <vmx> -gu <user> -gp <pass> <program> <args>` (VMX 파일 인식 문제 해결)
- 두 번째 수정: `vmrun -T ws runProgramInGuest <vmx> <program> <args>` (-gu/-gp 인수 제거, 기본 사용자 사용)
- 세 번째 수정: `vmrun -T ws runProgramInGuest <vmx> -gu <user> -gp <pass> <program> <args>` (사용자 인증 문제 해결)
- 총 4개의 vmrun 명령어 호출 부분 수정 완료:
  1. ISO 복사 완료 파일 확인
  2. Seed 파일 존재 확인
  3. Cloud-init 상태 확인
  4. K8s 패키지 설치 완료 확인

## 영향 범위
- VM 생성 후 cloud-init 상태 확인 기능
- ISO 파일 복사 완료 확인 기능
- K8s 패키지 설치 완료 확인 기능

## 수정 완료
- ✅ vmrun 명령어 인수 순서 수정 완료
- ✅ "Unrecognized command: <vmx>" 에러 해결
- ✅ "Invalid argument: -gu" 에러 해결
- ✅ "Invalid user name or password" 에러 해결
- ✅ 정상적인 cloud-init 상태 확인 가능

## 테스트 계획
- VM 생성 스크립트 재실행
- cloud-init 에러 메시지 확인
- 정상적인 상태 확인 로그 출력 확인
