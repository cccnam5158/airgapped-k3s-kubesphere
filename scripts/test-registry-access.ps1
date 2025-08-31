param(
    [string]$RegistryIP = "192.168.6.1",
    [int]$Port = 5000
)

Write-Host "Registry access test" -ForegroundColor Green
Write-Host ""

# 1) Get WSL2 IP (first IP only)
Write-Host "Checking WSL2 IP..." -ForegroundColor Blue
$WSLIP = (wsl hostname -I).Trim().Split(' ')[0]
if ([string]::IsNullOrWhiteSpace($WSLIP)) {
    Write-Host "WSL2 IP not found." -ForegroundColor Red
    exit 1
}
Write-Host ("WSL2 IP: {0}" -f $WSLIP) -ForegroundColor Green

# 2) Check registry container in WSL2
Write-Host "Checking registry container in WSL2..." -ForegroundColor Blue
# Use single quotes to avoid any interpolation issues; keep Docker Go template braces as-is
$RegistryRunning = wsl docker ps --format 'table {{.Names}}\t{{.Status}}' | Select-String -SimpleMatch 'airgap-registry'
if ($null -ne $RegistryRunning) {
    Write-Host ("Registry is running: {0}" -f $RegistryRunning) -ForegroundColor Green
} else {
    Write-Host "Registry container not running." -ForegroundColor Red
    Write-Host "Start it in WSL2 with:" -ForegroundColor Yellow
    Write-Host "  cd wsl/scripts; ./00_prep_offline_fixed.sh" -ForegroundColor Yellow
    exit 1
}

# 3) Check port forwarding on Windows host
Write-Host "Checking port forwarding rule..." -ForegroundColor Blue
$PortForwarding = netsh interface portproxy show all | Select-String "$RegistryIP.*$Port.*$WSLIP"
if ($null -ne $PortForwarding) {
    Write-Host "Port forwarding rule found." -ForegroundColor Green
} else {
    Write-Host "Port forwarding rule NOT found." -ForegroundColor Red
    Write-Host "Configure it with:" -ForegroundColor Yellow
    Write-Host "  .\scripts\setup-port-forwarding.ps1" -ForegroundColor Yellow
    exit 1
}

# 4) Test from Windows host
Write-Host "Testing from Windows host..." -ForegroundColor Blue
try {
    $url = "https://{0}:{1}/v2/_catalog" -f $RegistryIP, $Port
    
    # PowerShell 버전에 따라 다른 매개변수 사용
    $PSVersion = $PSVersionTable.PSVersion.Major
    if ($PSVersion -ge 6) {
        $Response = Invoke-WebRequest -Uri $url -SkipCertificateCheck -TimeoutSec 10
    } else {
        # PowerShell 5.x 이하에서는 -SkipCertificateCheck 대신 다른 방법 사용
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $Response = Invoke-WebRequest -Uri $url -TimeoutSec 10
    }
    
    if ($Response.StatusCode -eq 200) {
        Write-Host "Windows host access OK." -ForegroundColor Green
        try {
            $Catalog = $Response.Content | ConvertFrom-Json
            if ($Catalog -and $Catalog.repositories) {
                Write-Host ("  Image count: {0}" -f $Catalog.repositories.Count) -ForegroundColor Cyan
            } else {
                Write-Host "  JSON parsed but repositories not found." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  JSON parse failed. Check response content." -ForegroundColor Yellow
        }
    } else {
        Write-Host ("Windows host got HTTP {0}" -f $Response.StatusCode) -ForegroundColor Red
    }
} catch {
    Write-Host "Windows host access FAILED." -ForegroundColor Red
    Write-Host ("  Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# 5) Test from inside WSL2
Write-Host "Testing from inside WSL2..." -ForegroundColor Blue
try {
    $WSLResponse = wsl curl -s -k ("https://localhost:{0}/v2/_catalog" -f $Port)
    if (-not [string]::IsNullOrWhiteSpace($WSLResponse)) {
        Write-Host "WSL2 access OK." -ForegroundColor Green
        try {
            $WSLCatalog = $WSLResponse | ConvertFrom-Json
            if ($WSLCatalog -and $WSLCatalog.repositories) {
                Write-Host ("  Image count: {0}" -f $WSLCatalog.repositories.Count) -ForegroundColor Cyan
            } else {
                Write-Host "  JSON parsed but repositories not found." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  JSON parse failed. Check response content." -ForegroundColor Yellow
        }
    } else {
        Write-Host "WSL2 access FAILED (empty response)." -ForegroundColor Red
    }
} catch {
    Write-Host "WSL2 access FAILED." -ForegroundColor Red
    Write-Host ("  Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# 6) Summary and commands to run on VMs
Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host ("  WSL2 IP: {0}" -f $WSLIP) -ForegroundColor White
Write-Host ("  Registry IP: {0}" -f $RegistryIP) -ForegroundColor White
Write-Host ("  Port: {0}" -f $Port) -ForegroundColor White
Write-Host ("  Port forwarding: {0}" -f ($null -ne $PortForwarding)) -ForegroundColor White

Write-Host ""
Write-Host "VM test commands" -ForegroundColor Cyan
Write-Host ("  curl -k https://{0}:{1}/v2/_catalog" -f $RegistryIP, $Port) -ForegroundColor Yellow
Write-Host ("  curl -k https://{0}:{1}/v2/registry.k8s.io/metrics-server/tags/list" -f $RegistryIP, $Port) -ForegroundColor Yellow

Write-Host ""
Write-Host "Test completed." -ForegroundColor Green
