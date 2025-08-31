# scripts/setup-port-forwarding.ps1
param(
  [string]$RegistryIP = "192.168.6.1",
  [int]$Port = 5000
)

Write-Host ("Setting up Windows->WSL2 port proxy for registry {0}:{1} ..." -f $RegistryIP, $Port) -ForegroundColor Cyan

# 1) WSL2 IP 주소 가져오기 (첫 번째 IP만 사용)
$WSLIP = (wsl hostname -I).Trim().Split(' ')[0]
if ([string]::IsNullOrWhiteSpace($WSLIP)) {
  Write-Host "Failed to get WSL2 IP." -ForegroundColor Red
  exit 1
}
Write-Host ("WSL2 eth0 IP: {0}" -f $WSLIP) -ForegroundColor Green

# 2) IP Helper 서비스 확인 (portproxy에 필수)
$svc = Get-Service iphlpsvc -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
  Write-Host "Starting IP Helper service..." -ForegroundColor Yellow
  Start-Service iphlpsvc
}

# 3) 기존 규칙 제거 (중복 방지)
netsh interface portproxy delete v4tov4 listenaddress=$RegistryIP listenport=$Port | Out-Null

# 4) 포트 포워딩 추가 (Windows의 $RegistryIP:$Port -> WSL2 $WSLIP:$Port)
netsh interface portproxy add v4tov4 listenaddress=$RegistryIP listenport=$Port connectaddress=$WSLIP connectport=$Port

# 5) 방화벽 허용 규칙 추가 (없으면 생성)
$ruleName = "Allow Registry $Port TCP"
$rule = (netsh advfirewall firewall show rule name="$ruleName" | Select-String -SimpleMatch "Rule Name")
if (-not $rule) {
  netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=$Port
}

# 6) 확인
Write-Host "Current v4tov4 rules:" -ForegroundColor Cyan
netsh interface portproxy show v4tov4
Write-Host "Done." -ForegroundColor Green
