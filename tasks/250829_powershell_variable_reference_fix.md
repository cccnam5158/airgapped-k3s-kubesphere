# PowerShell 변수 참조 오류 수정

## 문제 상황
- `.\scripts\setup-vms.ps1` 실행 시 PowerShell 변수 참조 오류 발생
- 오류 위치: `windows/Setup-VMs.ps1:513`
- 오류 메시지: "변수 참조가 잘못되었습니다. ':' 뒤에 올바른 변수 이름 문자가 없습니다."

## 원인 분석
- `$cloudInitStatus` 변수에 `:` 문자가 포함된 값이 있을 때 PowerShell이 이를 변수 이름의 일부로 해석
- PowerShell에서 `:` 문자는 변수 이름 구분자로 사용되므로 문제 발생

## 해결 방안
- `${}` 구문을 사용하여 변수 이름을 명확히 구분
- `$cloudInitStatus`를 `${cloudInitStatus}`로 변경

## 작업 내용
1. `windows/Setup-VMs.ps1` 파일의 513번째 줄 수정
2. 유사한 패턴이 있는 다른 부분도 함께 수정
3. 테스트 실행으로 오류 해결 확인

## 상태
- [x] 코드 수정
- [x] 추가 문제 해결
- [ ] 테스트 실행
- [ ] README.md 업데이트 (필요시)

## 수정 내용
1. `windows/Setup-VMs.ps1` 513번째 줄: `$cloudInitStatus` → `${cloudInitStatus}`
2. `windows/Setup-VMs.ps1` 521번째 줄: `$cloudInitStatus` → `${cloudInitStatus}`
3. `windows/Setup-VMs.ps1` 529번째 줄: 숫자 변환 전 정규식 검증 추가
4. `windows/Setup-VMs.ps1` 500-510번째 줄: VM 준비 상태 확인 로직 추가

## 추가 해결된 문제
- VMware Guest OS 인증 오류 방지를 위한 VM 준비 상태 확인 로직 추가
- PowerShell 타입 변환 오류 해결을 위한 정규식 검증 추가
- VM이 완전히 부팅될 때까지 대기하는 안전한 로직 구현

## 해결된 문제
- PowerShell 변수 참조 오류 해결
- `:` 문자가 포함된 cloud-init 상태 값이 변수 이름으로 잘못 해석되는 문제 수정

## 추가 발견된 문제
- VMware Guest OS 인증 오류: "Invalid user name or password for the guest OS"
- PowerShell 타입 변환 오류: 문자열을 Int32로 변환 시도 시 발생
- `completionCheck` 변수에서 숫자 변환 시 오류 발생
