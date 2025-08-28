# VMware Workstation Pro VM 정리 스크립트
# 사용법: .\cleanup-vms.ps1

# 강력한 UTF-8 인코딩 설정
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$env:PYTHONIOENCODING = "utf-8"

# 콘솔 코드 페이지 설정 (한글 지원)
try {
    chcp 65001 | Out-Null
} catch {
    # 코드 페이지 변경 실패 시 무시
}

# 환경 변수 설정
$VmBaseDir = "F:\VMs\AirgapLab"
$MasterName = "k3s-master1"
$WorkerNames = @("k3s-worker1","k3s-worker2")

Write-Host "[CLEANUP] VMware Workstation Pro VM 정리 스크립트를 실행합니다..." -ForegroundColor Blue
Write-Host "   VM 디렉토리: $VmBaseDir" -ForegroundColor Yellow
Write-Host ""

# 관리자 권한 확인
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[ERROR] 이 스크립트는 관리자 권한이 필요합니다." -ForegroundColor Red
    Write-Host "   PowerShell을 관리자 권한으로 실행해주세요." -ForegroundColor Yellow
    exit 1
}

# VMware vmrun 경로 확인 및 설정
Write-Host "[INFO] VMware vmrun 경로를 확인합니다..." -ForegroundColor Blue
$vmrunPaths = @(
    "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
    "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
)

$vmrunPath = $null
foreach ($path in $vmrunPaths) {
    if (Test-Path $path) {
        $vmrunPath = $path
        Write-Host "[SUCCESS] VMware vmrun을 찾았습니다: $vmrunPath" -ForegroundColor Green
        break
    }
}

if (-not $vmrunPath) {
    Write-Host "[ERROR] VMware Workstation Pro가 설치되지 않았거나 vmrun을 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "   VMware Workstation Pro를 설치하고 PATH에 추가해주세요." -ForegroundColor Yellow
    Write-Host "   또는 다음 경로 중 하나에 vmrun.exe가 있는지 확인해주세요:" -ForegroundColor Yellow
    foreach ($path in $vmrunPaths) {
        Write-Host "   - $path" -ForegroundColor Cyan
    }
    exit 1
}

# 실행 정책 설정
Write-Host "[INFO] 실행 정책을 설정합니다..." -ForegroundColor Blue
Set-ExecutionPolicy Bypass -Scope Process -Force

# VM 정리 함수
function Cleanup-VM {
    param([string]$VmName)
    
    Write-Host "[INFO] VM 정리 중: $VmName" -ForegroundColor Blue
    
    # VM 중지
    $vmxPath = Join-Path $VmBaseDir "$VmName\$VmName.vmx"
    if (Test-Path $vmxPath) {
        Write-Host "   VM 중지 중..." -ForegroundColor Yellow
        $result = & $vmrunPath -T ws stop $vmxPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [SUCCESS] VM이 중지되었습니다" -ForegroundColor Green
        } else {
            Write-Host "   [WARNING] VM 중지 실패 (이미 중지된 상태일 수 있음): $result" -ForegroundColor Yellow
        }
        
        # VM 등록 해제
        Write-Host "   VM 등록 해제 중..." -ForegroundColor Yellow
        $result = & $vmrunPath -T ws unregister $vmxPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [SUCCESS] VM 등록이 해제되었습니다" -ForegroundColor Green
        } else {
            Write-Host "   [WARNING] VM 등록 해제 실패: $result" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   [WARNING] VMX 파일을 찾을 수 없습니다: $vmxPath" -ForegroundColor Yellow
    }
    
    # VM 디렉토리 삭제
    $vmDir = Join-Path $VmBaseDir $VmName
    if (Test-Path $vmDir) {
        Write-Host "   VM 디렉토리 삭제 중..." -ForegroundColor Yellow
        try {
            Remove-Item -Path $vmDir -Recurse -Force
            Write-Host "   [SUCCESS] VM 디렉토리가 삭제되었습니다: $vmDir" -ForegroundColor Green
        } catch {
            Write-Host "   [ERROR] VM 디렉토리 삭제 실패: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "   [INFO] VM 디렉토리가 이미 존재하지 않습니다: $vmDir" -ForegroundColor Yellow
    }
}

# 메인 실행
try {
    Write-Host "[INFO] VM 정리를 시작합니다..." -ForegroundColor Blue
    Write-Host "   VM 디렉토리: $VmBaseDir" -ForegroundColor Yellow
    
    # 모든 VM 목록 생성 (마스터 + 워커들)
    $allVMs = @($MasterName) + $WorkerNames
    Write-Host "   대상 VM들: $($allVMs -join ', ')" -ForegroundColor Yellow
    Write-Host ""
    
    # 각 VM 정리
    foreach ($vmName in $allVMs) {
        Cleanup-VM -VmName $vmName
        Write-Host ""
    }
    
    # 기본 디렉토리 정리 (비어있는 경우)
    if (Test-Path $VmBaseDir) {
        $remainingItems = Get-ChildItem -Path $VmBaseDir -Force
        if ($remainingItems.Count -eq 0) {
            try {
                Remove-Item -Path $VmBaseDir -Force
                Write-Host "[SUCCESS] 기본 디렉토리가 완전히 정리되었습니다: $VmBaseDir" -ForegroundColor Green
            } catch {
                Write-Host "[WARNING] 기본 디렉토리 삭제 실패: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[INFO] 기본 디렉토리에 남은 항목이 있습니다: $($remainingItems.Count)개" -ForegroundColor Yellow
            foreach ($item in $remainingItems) {
                Write-Host "   - $($item.Name)" -ForegroundColor Cyan
            }
        }
    }
    
    Write-Host ""
    Write-Host "[SUCCESS] VM 정리가 완료되었습니다!" -ForegroundColor Green
    Write-Host "[INFO] 다음 단계:" -ForegroundColor Yellow
    Write-Host "   1. VM 재생성: .\scripts\setup-vms.ps1" -ForegroundColor Cyan
    Write-Host "   2. 또는 수동으로 VM을 생성하세요" -ForegroundColor Cyan
    
} catch {
    Write-Host "[ERROR] VM 정리 중 오류가 발생했습니다: $_" -ForegroundColor Red
    exit 1
}
