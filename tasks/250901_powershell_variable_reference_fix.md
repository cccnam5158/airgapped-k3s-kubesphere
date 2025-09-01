# 250901 PowerShell 변수 참조 문제 수정

## 문제 상황
- `Setup-VMs.ps1` 실행 시 PowerShell 구문 오류 발생
- 오류 메시지: "변수 참조가 잘못되었습니다. ':' 뒤에 올바른 변수 이름 문자가 없습니다."
- 위치: 484번째 줄 근처의 `$($guestSyntax.Name)` 부분

## 원인 분석
- `Test-VMRunGuestSyntax` 함수가 해시테이블 `@{ Name = "..."; Args = @(...) }` 반환
- 코드에서 `$guestSyntax.Name`, `$guestSyntax.Args` 형태로 접근 시도
- PowerShell에서 해시테이블 속성 접근 시 `$guestSyntax['Name']`, `$guestSyntax['Args']` 형태 사용 필요

## 수정 내용
1. **484번째 줄**: `$($guestSyntax.Name)` → `$($guestSyntax['Name'])`
2. **494번째 줄**: `$guestSyntax.Args` → `$guestSyntax['Args']`
3. **553번째 줄**: `$guestSyntax` → `$guestSyntax['Args']`
4. **560번째 줄**: `$guestSyntax` → `$guestSyntax['Args']`

## 수정된 파일
- `windows/Setup-VMs.ps1` - PowerShell 변수 참조 구문 수정

## 상태
- ✅ 완료
