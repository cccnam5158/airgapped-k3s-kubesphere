# Simple VM Status Check Script
# This script checks VM status without complex guest operations

param(
    [string]$VmBaseDir = "F:\VMs\AirgapLab",
    [string]$MasterName = "k3s-master1",
    [string[]]$WorkerNames = @("k3s-worker1","k3s-worker2")
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"

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

# Find vmrun
$vmrunPath = $null

# Try environment variable first
if ($env:VMRUN_PATH -and (Test-Path $env:VMRUN_PATH)) {
    $vmrunPath = $env:VMRUN_PATH
    Write-Info "Using vmrun from VMRUN_PATH: $vmrunPath"
} else {
    # Try common installation paths
    $vmrunPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )
    
    foreach ($path in $vmrunPaths) {
        if (Test-Path $path) {
            $vmrunPath = $path
            Write-Info "Found vmrun at: $vmrunPath"
            break
        }
    }
    
    # Finally try PATH
    if (-not $vmrunPath) {
        try {
            $null = Get-Command vmrun -ErrorAction Stop
            $vmrunPath = "vmrun"
            Write-Info "Using vmrun from PATH"
        } catch {
            Write-Warning "vmrun command not found in any location"
            Write-Info "Expected locations:"
            foreach ($path in $vmrunPaths) {
                Write-Info "  - $path"
            }
            Write-Info "Please ensure VMware Workstation Pro is installed"
            exit 1
        }
    }
}

Write-Info "Checking VM status..."
Write-Info ""

# List all running VMs
Write-Info "Currently running VMs:"
$runningVMs = & $vmrunPath -T ws list 2>$null
if ($runningVMs) {
    $runningVMs | ForEach-Object { 
        if ($_ -notmatch "Total running VMs") {
            Write-Success "  $_"
        }
    }
} else {
    Write-Warning "No VMs currently running"
}

Write-Info ""

# Check each VM individually
$allVMs = @($MasterName) + $WorkerNames

foreach ($vmName in $allVMs) {
    $vmDir = Join-Path $VmBaseDir $vmName
    $vmxPath = Join-Path $vmDir "$vmName.vmx"
    
    Write-Info "Checking VM: $vmName"
    Write-Info "  VMX Path: $vmxPath"
    
    if (-not (Test-Path $vmxPath)) {
        Write-Warning "  Status: VMX file not found"
        continue
    }
    
    # Check if VM is running
    $isRunning = & $vmrunPath -T ws list 2>$null | Select-String $vmName
    if ($isRunning) {
        Write-Success "  Status: Running"
        
        # Check VMware Tools status
        try {
            $toolsState = (& $vmrunPath -T ws checkToolsState $vmxPath 2>$null | Out-String).Trim()
            if ($toolsState -match "running") {
                Write-Success "  Tools: VMware Tools running"
            } elseif ($toolsState -match "installed") {
                Write-Warning "  Tools: VMware Tools installed but not running"
            } else {
                Write-Warning "  Tools: $toolsState"
            }
        } catch {
            Write-Warning "  Tools: Unable to check VMware Tools status"
        }
        
        # Try to get IP address (this usually works even without guest authentication)
        try {
            $ipResult = & $vmrunPath -T ws getGuestIPAddress $vmxPath -wait 10 2>$null
            if ($ipResult -and $ipResult -notmatch "Error" -and $ipResult -match "\d+\.\d+\.\d+\.\d+") {
                Write-Success "  IP Address: $ipResult"
            } else {
                Write-Info "  IP Address: Not available yet"
            }
        } catch {
            Write-Info "  IP Address: Unable to determine"
        }
        
    } else {
        Write-Warning "  Status: Not running"
    }
    
    Write-Info ""
}

Write-Info "VM Status Check Complete"
Write-Info ""
Write-Info "Next steps if VMs are running:"
Write-Info "1. Wait for VMs to fully boot (usually 5-10 minutes)"
Write-Info "2. Check VM consoles in VMware Workstation for boot progress"
Write-Info "3. Try SSH connection: ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.10"
Write-Info "4. If SSH works, run: ./wsl/scripts/02_wait_and_config.sh"