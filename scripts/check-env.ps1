# Simple Environment Check Script
Write-Host "=== Airgapped Lab Environment Check ===" -ForegroundColor Blue

# Check OS
Write-Host "1. OS Check..." -ForegroundColor Yellow
$os = Get-WmiObject -Class Win32_OperatingSystem
Write-Host "   OS: $($os.Caption)" -ForegroundColor Cyan
Write-Host "   Version: $($os.Version)" -ForegroundColor Cyan

# Check WSL2
Write-Host "2. WSL2 Check..." -ForegroundColor Yellow
try {
    # Check if WSL is enabled
    $wslEnabled = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslEnabled.State -eq "Enabled") {
        Write-Host "   WSL: Enabled" -ForegroundColor Green
        
        # Check WSL distributions
        $wslList = wsl -l -v 2>$null
        if ($wslList) {
            Write-Host "   WSL Distributions:" -ForegroundColor Green
            $wslList | ForEach-Object {
                if ($_ -match "Ubuntu") {
                    Write-Host "     $_" -ForegroundColor Green
                } else {
                    Write-Host "     $_" -ForegroundColor Cyan
                }
            }
        } else {
            Write-Host "   No WSL distributions found" -ForegroundColor Yellow
            Write-Host "   Run: wsl --install -d Ubuntu" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   WSL: Not Enabled" -ForegroundColor Red
        Write-Host "   Run: wsl --install" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   WSL: Error checking status" -ForegroundColor Red
    Write-Host "   Run: wsl --install" -ForegroundColor Yellow
}

# Check VMware
Write-Host "3. VMware Check..." -ForegroundColor Yellow
$vmwarePaths = @(
    "C:\Program Files (x86)\VMware\VMware Workstation",
    "C:\Program Files\VMware\VMware Workstation",
    "C:\Program Files (x86)\VMware\VMware Player",
    "C:\Program Files\VMware\VMware Player"
)

$vmwareFound = $false
foreach ($path in $vmwarePaths) {
    if (Test-Path $path) {
        Write-Host "   VMware: Found at $path" -ForegroundColor Green
        $vmwareFound = $true
        break
    }
}

if (-not $vmwareFound) {
    Write-Host "   VMware: Not Found" -ForegroundColor Red
    Write-Host "   Please install VMware Workstation or Player" -ForegroundColor Yellow
}

# Check vmrun
Write-Host "4. vmrun Check..." -ForegroundColor Yellow
$vmrunFound = $false

# Method 1: Check if vmrun is in PATH
try {
    $vmrun = Get-Command vmrun -ErrorAction Stop
    Write-Host "   vmrun: Available in PATH" -ForegroundColor Green
    $vmrunFound = $true
} catch {
    # Method 2: Check common VMware installation paths
    $vmrunPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files (x86)\VMware\VMware Player\vmrun.exe",
        "C:\Program Files\VMware\VMware Player\vmrun.exe"
    )
    
    foreach ($path in $vmrunPaths) {
        if (Test-Path $path) {
            Write-Host "   vmrun: Found at $path" -ForegroundColor Green
            Write-Host "   Add to PATH: $($path | Split-Path -Parent)" -ForegroundColor Yellow
            $vmrunFound = $true
            break
        }
    }
    
    if (-not $vmrunFound) {
        Write-Host "   vmrun: Not Found" -ForegroundColor Red
        Write-Host "   Please ensure VMware is properly installed" -ForegroundColor Yellow
    }
}

# Check VMware Networks
Write-Host "5. VMware Networks..." -ForegroundColor Yellow
$networks = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -like "192.168.*" -and $_.InterfaceAlias -like "*VMware*"}
if ($networks) {
    Write-Host "   Available Networks:" -ForegroundColor Green
    foreach ($net in $networks) {
        Write-Host "     $($net.InterfaceAlias): $($net.IPAddress)" -ForegroundColor Cyan
    }
} else {
    Write-Host "   No VMware Networks Found" -ForegroundColor Red
    Write-Host "   VMware networks will be created during setup" -ForegroundColor Yellow
}

# Check Admin Rights
Write-Host "6. Admin Rights..." -ForegroundColor Yellow
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) {
    Write-Host "   Admin Rights: Yes" -ForegroundColor Green
} else {
    Write-Host "   Admin Rights: No" -ForegroundColor Red
    Write-Host "   Run PowerShell as Administrator" -ForegroundColor Yellow
}

# Check Disk Space
Write-Host "7. Disk Space..." -ForegroundColor Yellow
$drive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
if ($drive) {
    $freeGB = [math]::Round($drive.FreeSpace / 1GB, 2)
    Write-Host "   C: Drive Free Space: $freeGB GB" -ForegroundColor Cyan
    if ($freeGB -ge 20) {
        Write-Host "   Disk Space: Sufficient" -ForegroundColor Green
    } else {
        Write-Host "   Disk Space: Low (Need 20GB+)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   C: Drive: Not Found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Recommended Settings ===" -ForegroundColor Blue
Write-Host "Registry Host IP: 192.168.6.1" -ForegroundColor Cyan
Write-Host "Master IP: 192.168.6.10" -ForegroundColor Cyan
Write-Host "Worker1 IP: 192.168.6.11" -ForegroundColor Cyan
Write-Host "Worker2 IP: 192.168.6.12" -ForegroundColor Cyan
Write-Host "Host-Only Network: VMnet1" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== Troubleshooting ===" -ForegroundColor Blue
if (-not $vmrunFound) {
    Write-Host "1. Install VMware Workstation/Player" -ForegroundColor Yellow
    Write-Host "2. Add VMware directory to PATH" -ForegroundColor Yellow
    Write-Host "3. Restart PowerShell" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Blue
Write-Host "1. Run: source env-config.sh (in WSL2)" -ForegroundColor Green
Write-Host "2. Run: cd wsl/scripts" -ForegroundColor Green
Write-Host "3. Run: ./00_prep_offline.sh" -ForegroundColor Green
Write-Host "4. Run: ./01_build_seed_isos.sh" -ForegroundColor Green
Write-Host "5. Run: .\setup-vms.ps1 (in PowerShell as Admin)" -ForegroundColor Green
