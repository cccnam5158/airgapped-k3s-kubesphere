# KubeSphere Airgap Lab - VM Management Script
# VM 상태 확인, 시작, 중지, VMware Workstation에서 열기 기능 제공

param(
    [string]$VmBaseDir = "F:\VMs\AirgapLab",
    [string]$Action = "status",  # status, start, stop, open, list
    [string]$VmName = ""  # 특정 VM 이름 (선택사항)
)

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

# 색상 정의
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"
$Cyan = "Cyan"

# 로깅 함수
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Red
}

# VMware 도구 경로 확인
function Get-VMwareTools {
    $vmrunPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )
    
    $vmrunPath = $null
    foreach ($path in $vmrunPaths) {
        if (Test-Path $path) {
            $vmrunPath = $path
            break
        }
    }
    
    if (-not $vmrunPath) {
        Write-Error "VMware Workstation Pro가 설치되지 않았거나 vmrun을 찾을 수 없습니다."
        exit 1
    }
    
    return $vmrunPath
}

# VM 목록 가져오기
function Get-VMList {
    $vms = @()
    
    if (Test-Path $VmBaseDir) {
        $vmDirs = Get-ChildItem -Path $VmBaseDir -Directory
        foreach ($dir in $vmDirs) {
            $vmxFile = Join-Path $dir.FullName "$($dir.Name).vmx"
            if (Test-Path $vmxFile) {
                $vms += @{
                    Name = $dir.Name
                    Path = $vmxFile
                    Directory = $dir.FullName
                }
            }
        }
    }
    
    return $vms
}

# VM 상태 확인
function Get-VMStatus {
    param([string]$vmrunPath, [array]$vms)
    
    Write-Info "VM 상태를 확인합니다..."
    Write-Host ""
    
    if ($vms.Count -eq 0) {
        Write-Warning "VM을 찾을 수 없습니다: $VmBaseDir"
        return
    }
    
    # 헤더 출력
    Write-Host "VM 이름" -NoNewline -ForegroundColor $Cyan
    Write-Host "                    " -NoNewline
    Write-Host "상태" -NoNewline -ForegroundColor $Cyan
    Write-Host "      " -NoNewline
    Write-Host "경로" -ForegroundColor $Cyan
    Write-Host "-" * 80 -ForegroundColor $Blue
    
    foreach ($vm in $vms) {
        # VM 이름 출력 (20자 고정 너비)
        $vmName = $vm.Name.PadRight(20)
        Write-Host $vmName -NoNewline -ForegroundColor $Cyan
        
        # VM 상태 확인
        try {
            $result = & $vmrunPath -T ws list 2>&1
            if ($LASTEXITCODE -eq 0) {
                if ($result -match $vm.Name) {
                    Write-Host "실행 중" -NoNewline -ForegroundColor $Green
                } else {
                    Write-Host "중지됨" -NoNewline -ForegroundColor $Red
                }
            } else {
                Write-Host "확인불가" -NoNewline -ForegroundColor $Red
            }
        } catch {
            Write-Host "확인불가" -NoNewline -ForegroundColor $Red
        }
        
        # 상태 뒤에 공백 추가
        Write-Host "      " -NoNewline
        
        # 경로 출력
        Write-Host $vm.Path -ForegroundColor $Yellow
    }
    
    Write-Host "-" * 80 -ForegroundColor $Blue
    Write-Host ""
}

# VM 시작
function Start-VMs {
    param([string]$vmrunPath, [array]$vms, [string]$targetVm = "")
    
    Write-Info "VM을 시작합니다..."
    
    $vmsToStart = $vms
    if ($targetVm -ne "") {
        $vmsToStart = $vms | Where-Object { $_.Name -eq $targetVm }
        if ($vmsToStart.Count -eq 0) {
            Write-Error "VM을 찾을 수 없습니다: $targetVm"
            return
        }
    }
    
    foreach ($vm in $vmsToStart) {
        Write-Info "VM 시작 중: $($vm.Name)"
        
        # GUI 모드로 시작 (VMware Workstation에서 보이도록)
        $result = & $vmrunPath -T ws start $vm.Path 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "VM 시작됨: $($vm.Name) (GUI 모드)"
        } else {
            Write-Warning "GUI 모드 시작 실패, 백그라운드 모드로 시도..."
            $result = & $vmrunPath -T ws start $vm.Path nogui 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "VM 시작됨: $($vm.Name) (백그라운드 모드)"
                Write-Warning "VM이 백그라운드에서 실행 중입니다. VMware Workstation에서 보이지 않을 수 있습니다."
            } else {
                Write-Error "VM 시작 실패: $($vm.Name)"
                Write-Error "오류: $result"
            }
        }
    }
}

# VM 중지
function Stop-VMs {
    param([string]$vmrunPath, [array]$vms, [string]$targetVm = "")
    
    Write-Info "VM을 중지합니다..."
    
    $vmsToStop = $vms
    if ($targetVm -ne "") {
        $vmsToStop = $vms | Where-Object { $_.Name -eq $targetVm }
        if ($vmsToStop.Count -eq 0) {
            Write-Error "VM을 찾을 수 없습니다: $targetVm"
            return
        }
    }
    
    foreach ($vm in $vmsToStop) {
        Write-Info "VM 중지 중: $($vm.Name)"
        
        $result = & $vmrunPath -T ws stop $vm.Path 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "VM 중지됨: $($vm.Name)"
        } else {
            Write-Error "VM 중지 실패: $($vm.Name)"
            Write-Error "오류: $result"
        }
    }
}

# VMware Workstation에서 VM 열기
function Open-VMInWorkstation {
    param([array]$vms, [string]$targetVm = "")
    
    Write-Info "VMware Workstation에서 VM을 엽니다..."
    
    $vmsToOpen = $vms
    if ($targetVm -ne "") {
        $vmsToOpen = $vms | Where-Object { $_.Name -eq $targetVm }
        if ($vmsToOpen.Count -eq 0) {
            Write-Error "VM을 찾을 수 없습니다: $targetVm"
            return
        }
    }
    
    foreach ($vm in $vmsToOpen) {
        Write-Info "VMware Workstation에서 열기: $($vm.Name)"
        
        try {
            Start-Process -FilePath "vmware.exe" -ArgumentList $vm.Path
            Write-Success "VMware Workstation에서 VM 열기 성공: $($vm.Name)"
        } catch {
            Write-Error "VMware Workstation에서 VM 열기 실패: $($vm.Name)"
            Write-Error "오류: $($_.Exception.Message)"
        }
    }
}

# 메인 실행
function Main {
    Write-Host "=" * 60 -ForegroundColor $Blue
    Write-Host "[MANAGE] KubeSphere Airgap Lab - VM 관리 도구" -ForegroundColor $Blue
    Write-Host "=" * 60 -ForegroundColor $Blue
    Write-Host "VM 디렉토리: $VmBaseDir" -ForegroundColor $Yellow
    Write-Host "작업: $Action" -ForegroundColor $Yellow
    if ($VmName -ne "") {
        Write-Host "대상 VM: $VmName" -ForegroundColor $Yellow
    }
    Write-Host ""
    
    # VMware 도구 확인
    $vmrunPath = Get-VMwareTools
    Write-Success "VMware vmrun 경로: $vmrunPath"
    Write-Host ""
    
    # VM 목록 가져오기
    $vms = Get-VMList
    
    # 작업 실행
    switch ($Action.ToLower()) {
        "status" {
            Get-VMStatus -vmrunPath $vmrunPath -vms $vms
        }
        "start" {
            Start-VMs -vmrunPath $vmrunPath -vms $vms -targetVm $VmName
        }
        "stop" {
            Stop-VMs -vmrunPath $vmrunPath -vms $vms -targetVm $VmName
        }
        "open" {
            Open-VMInWorkstation -vms $vms -targetVm $VmName
        }
        "list" {
            Write-Info "VM 목록:"
            foreach ($vm in $vms) {
                Write-Host "  - $($vm.Name)" -ForegroundColor $Cyan
            }
        }
        default {
            Write-Error "알 수 없는 작업: $Action"
            Write-Info "사용 가능한 작업: status, start, stop, open, list"
            exit 1
        }
    }
    
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor $Blue
}

# 스크립트 실행
Main
