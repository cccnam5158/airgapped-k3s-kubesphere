# 현재 환경에 맞는 VM 생성 스크립트
# 사용법: .\setup-vms.ps1

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
$HostOnlyNet = "VMnet1"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SeedDir = Join-Path $scriptPath "..\wsl\out"
$VMemGB = 4
$VCPU = 2
$DiskGB = 40
$MasterName = "k3s-master1"
$WorkerNames = @("k3s-worker1","k3s-worker2")
$MasterIP = "192.168.6.10"
$WorkerIPs = @("192.168.6.11","192.168.6.12")

Write-Host "=" * 60 -ForegroundColor Blue
Write-Host "[SETUP] 현재 환경에 맞는 VM 생성 스크립트를 실행합니다..." -ForegroundColor Blue
Write-Host "=" * 60 -ForegroundColor Blue
Write-Host "VM 디렉토리: $VmBaseDir" -ForegroundColor Yellow
Write-Host "호스트 전용 네트워크: $HostOnlyNet" -ForegroundColor Yellow
Write-Host "마스터 IP: $MasterIP" -ForegroundColor Yellow
Write-Host "워커 IPs: $($WorkerIPs -join ', ')" -ForegroundColor Yellow
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

# VM 생성 및 부팅
Write-Host "[INFO] VM을 생성하고 부팅합니다..." -ForegroundColor Blue
$setupVMsPath = Join-Path $scriptPath "..\windows\Setup-VMs.ps1"

# vmrun 경로를 환경 변수로 전달
$env:VMRUN_PATH = $vmrunPath

& $setupVMsPath -VmBaseDir $VmBaseDir `
  -HostOnlyNet $HostOnlyNet `
  -MasterName $MasterName -WorkerNames $WorkerNames -MasterIP $MasterIP -WorkerIPs $WorkerIPs `
  -SeedDir $SeedDir -VMemGB $VMemGB -VCPU $VCPU -DiskGB $DiskGB

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "[SUCCESS] VM 생성이 완료되었습니다!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "[INFO] 다음 단계:" -ForegroundColor Yellow
Write-Host "1. WSL2에서 클러스터 확인: cd wsl/scripts && ./02_wait_and_config.sh" -ForegroundColor Cyan
Write-Host "2. SSH 접속: ssh -i ../wsl/out/ssh/id_rsa ubuntu@$MasterIP" -ForegroundColor Cyan
Write-Host "3. KubeSphere 콘솔: http://$MasterIP`:30880" -ForegroundColor Cyan
Write-Host "4. Ubuntu 22.04 LTS가 자동으로 설치됩니다 (Cloud-init)" -ForegroundColor Cyan
Write-Host ""
