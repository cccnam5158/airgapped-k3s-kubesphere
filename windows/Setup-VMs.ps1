# KubeSphere Airgap Lab - VM Setup Script
# Updated to match 00_prep_offline_fixed.sh and 01_build_seed_isos.sh configurations
# 
# Network Configuration:
# - IP Range: 192.168.6.x (matches WSL scripts)
# - Master: 192.168.6.10
# - Workers: 192.168.6.11, 192.168.6.12
# - Gateway: 192.168.6.1
# - DNS: 192.168.6.1
# - Registry: 192.168.6.1:5000
#
# Ubuntu Version: 22.04.5 LTS (matches 01_build_seed_isos.sh)

param(
  [string]$VmBaseDir = "F:\VMs\AirgapLab",
  [string]$HostOnlyNet = "VMnet1",
  [string]$SeedDir = ".\wsl\out",
  [string]$UbuntuIso = "ubuntu-22.04.5-live-server-amd64.iso",
  [int]$VMemGB = 4,
  [int]$VCPU = 2,
  [int]$DiskGB = 40,
  [string]$MasterName = "k3s-master1",
  [string[]]$WorkerNames = @("k3s-worker1","k3s-worker2"),
  [string]$MasterIP = "192.168.6.10",
  [string[]]$WorkerIPs = @("192.168.6.11","192.168.6.12"),
  [switch]$SkipVMStart = $false
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"

# Logging functions
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

# Global variables for VMware tools paths
$script:VMRUN_PATH = $null
$script:VDISKMANAGER_PATH = $null

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if running as administrator
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "This script requires administrator privileges"
        exit 1
    }
    
    # Check if vmrun is available
    $vmrunPath = $env:VMRUN_PATH
    if (-not $vmrunPath) {
        try {
            $null = Get-Command vmrun -ErrorAction Stop
            $script:VMRUN_PATH = "vmrun"
            Write-Success "vmrun command found in PATH"
        } catch {
            Write-Error "vmrun command not found. Please ensure VMware Workstation Pro is installed and vmrun is in PATH"
            exit 1
        }
    } else {
        if (Test-Path $vmrunPath) {
            $script:VMRUN_PATH = $vmrunPath
            Write-Success "vmrun found at: $vmrunPath"
        } else {
            Write-Error "vmrun not found at specified path: $vmrunPath"
            exit 1
        }
    }
    
    # Check if vmware-vdiskmanager is available
    $vdiskmanagerPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
        "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
    )
    
    foreach ($path in $vdiskmanagerPaths) {
        if (Test-Path $path) {
            $script:VDISKMANAGER_PATH = $path
            Write-Success "vmware-vdiskmanager found at: $path"
            break
        }
    }
    
    if (-not $script:VDISKMANAGER_PATH) {
        try {
            $null = Get-Command vmware-vdiskmanager -ErrorAction Stop
            $script:VDISKMANAGER_PATH = "vmware-vdiskmanager"
            Write-Success "vmware-vdiskmanager command found in PATH"
        } catch {
            Write-Error "vmware-vdiskmanager command not found. Please ensure VMware Workstation Pro is installed"
            Write-Error "Expected locations:"
            foreach ($path in $vdiskmanagerPaths) {
                Write-Error "  - $path"
            }
            exit 1
        }
    }
    
    # Check if seed directory exists
    if (-not (Test-Path $SeedDir)) {
        Write-Error "Seed directory not found: $SeedDir"
        Write-Error "Please run the WSL scripts first (00_prep_offline.sh and 01_build_seed_isos.sh)"
        exit 1
    }
    
    # Check if Ubuntu ISO exists (optional - for manual installation)
    if ($UbuntuIso -and -not (Test-Path $UbuntuIso)) {
        Write-Warning "Ubuntu ISO not found: $UbuntuIso"
        Write-Info "You can download Ubuntu 22.04.5 LTS from: https://releases.ubuntu.com/22.04/"
        Write-Info "This ISO is only needed for manual installation. Cloud-init will handle automatic setup."
    }
    
    # Check network configuration
    Write-Info "Network Configuration:"
    Write-Info "  Host-only Network: $HostOnlyNet (should be configured for 192.168.6.x subnet)"
    Write-Info "  Master IP: $MasterIP"
    Write-Info "  Worker IPs: $($WorkerIPs -join ', ')"
    Write-Info "  Gateway: 192.168.6.1 (as configured in WSL scripts)"
    Write-Info "  DNS: 192.168.6.1 (as configured in WSL scripts)"
    
    # Check if seed ISO files exist
    $requiredIsos = @("seed-master1.iso", "seed-worker1.iso", "seed-worker2.iso")
    foreach ($iso in $requiredIsos) {
        $isoPath = Join-Path $SeedDir $iso
        if (-not (Test-Path $isoPath)) {
            Write-Error "Required seed ISO file not found: $isoPath"
            Write-Error "Please run the WSL scripts first (00_prep_offline.sh and 01_build_seed_isos.sh)"
            exit 1
        }
    }
    
    Write-Success "Prerequisites check passed"
}

# Create VM function
function New-VM {
    param(
        [string]$Name,
        [string]$IP,
        [string]$SeedIso,
        [string]$HostOnlyNet
    )
    
    Write-Info "Creating VM: $Name"
    
    $vmDir = Join-Path $VmBaseDir $Name
    New-Item -ItemType Directory -Force -Path $vmDir | Out-Null

    # Convert ISO path to absolute path
    $absoluteIsoPath = (Get-Item $SeedIso).FullName
    Write-Info "Using ISO file: $absoluteIsoPath"

    # Enhanced VMX configuration
    $vmx = @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
memsize = "$($VMemGB*1024)"
numvcpus = "$VCPU"
displayName = "$Name"
guestOS = "ubuntu-64"
firmware = "bios"
vhv.enable = "FALSE"
hypervisor.cpuid.v0 = "FALSE"
ethernet0.present = "TRUE"
ethernet0.connectionType = "hostonly"
ethernet0.vnet = "$HostOnlyNet"
ethernet0.addressType = "generated"
ethernet0.wakeOnPcktRcv = "FALSE"
# Completely disable network boot
ethernet0.bootProto = "static"
ethernet0.startConnected = "TRUE"
ethernet0.allowGuestConnectionControl = "FALSE"
sata0.present = "TRUE"
sata0:1.present = "TRUE"
sata0:1.fileName = "$absoluteIsoPath"
sata0:1.deviceType = "cdrom-image"
sata0:1.startConnected = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "$Name.vmdk"
sata0:0.redo = ""
usb.present = "FALSE"
sound.present = "FALSE"
floppy0.present = "FALSE"
accelerate3D = "FALSE"
tools.syncTime = "TRUE"
tools.guestlib = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
replay.supported = "FALSE"
replay.filename = ""
# Prefer disk on subsequent boots to avoid reinstall loop
bios.bootOrder = "disk,cdrom"
bios.bootDelay = "2000"
bios.forceSetupOnce = "FALSE"
bios.hddOrder = "sata0:0"
bios.cdromOrder = "sata0:1"
bios.networkBoot = "FALSE"
bios.bootRetry = "TRUE"
bios.bootRetryDelay = "5000"
# Disable PXE boot
bios.pxeBoot = "FALSE"
"@

    $vmxPath = Join-Path $vmDir "$Name.vmx"
    Set-Content -Path $vmxPath -Value $vmx -Encoding ASCII
    
    # Verify VMX file was created correctly
    if (-not (Test-Path $vmxPath)) {
        Write-Error "Failed to create VMX file: $vmxPath"
        exit 1
    }
    
    # Check VMX file content
    $vmxContent = Get-Content -Path $vmxPath -Raw
    if (-not $vmxContent -or $vmxContent.Length -lt 100) {
        Write-Error "VMX file appears to be empty or corrupted: $vmxPath"
        exit 1
    }
    
    Write-Info "VMX file created successfully: $vmxPath"

    # Create disk
    Write-Info "Creating virtual disk for $Name..."
    Push-Location $vmDir
    try {
        $diskSize = "${DiskGB}GB"
        $diskFile = "$Name.vmdk"
        
        # Remove existing disk file if it exists
        if (Test-Path $diskFile) {
            Write-Info "Removing existing disk file: $diskFile"
            Remove-Item -Path $diskFile -Force
        }
        
        Write-Info "Creating disk '$diskFile' with size $diskSize"
        $diskResult = & $script:VDISKMANAGER_PATH -c -s $diskSize -a lsilogic -t 1 $diskFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create virtual disk (exit code: $LASTEXITCODE, output: $diskResult)"
        }
        Write-Success "Virtual disk created successfully: $diskFile"
    } catch {
        Write-Error "Failed to create virtual disk for $Name : $_"
        exit 1
    } finally {
        Pop-Location
    }

    # Verify VMX file exists and return absolute path
    if (-not (Test-Path $vmxPath)) {
        Write-Error "VMX file was not created: $vmxPath"
        exit 1
    }
    
    $absoluteVmxPath = (Get-Item $vmxPath).FullName
    Write-Success "Created VM $Name at $absoluteVmxPath with host-only network $HostOnlyNet"
    return $absoluteVmxPath
}

# Main execution
try {
    Write-Info "Starting VM creation process..."
    
    # Check prerequisites
    Test-Prerequisites
    
    # Clean up existing VMs if they exist
    Write-Info "Checking for existing VMs..."
    $existingVMs = @($MasterName) + $WorkerNames
    
    # First, try to unregister VMs from VMware Workstation
    Write-Info "Unregistering VMs from VMware Workstation..."
    foreach ($vmName in $existingVMs) {
        $vmDir = Join-Path $VmBaseDir $vmName
        $vmxPath = Join-Path $vmDir "$vmName.vmx"
        
        if (Test-Path $vmxPath) {
            Write-Info "Unregistering VM: $vmName"
            try {
                # Stop VM if running
                Write-Info "Stopping VM: $vmName"
                & $script:VMRUN_PATH -T ws stop $vmxPath hard 2>$null
                Start-Sleep -Seconds 2
                
                # Unregister VM
                Write-Info "Unregistering VM: $vmName"
                & $script:VMRUN_PATH -T ws unregister $vmxPath 2>$null
                Write-Success "Unregistered VM: $vmName"
            } catch {
                Write-Warning "Failed to unregister VM $vmName : $_"
            }
        }
    }
    
    # Then remove VM directories
    Write-Info "Removing VM directories..."
    foreach ($vmName in $existingVMs) {
        $vmDir = Join-Path $VmBaseDir $vmName
        if (Test-Path $vmDir) {
            Write-Warning "Found existing VM directory: $vmDir"
            Write-Info "Removing existing VM directory: $vmName"
            try {
                # Remove directory
                Remove-Item -Path $vmDir -Recurse -Force
                Write-Success "Removed existing VM directory: $vmName"
            } catch {
                Write-Warning "Failed to remove existing VM directory $vmName : $_"
            }
        }
    }
    
    # Clean up any remaining files in the base directory
    Write-Info "Cleaning up base directory..."
    try {
        Get-ChildItem -Path $VmBaseDir -Recurse -Force | Remove-Item -Recurse -Force 2>$null
        Write-Success "Cleaned up base directory: $VmBaseDir"
    } catch {
        Write-Warning "Some files could not be removed from base directory"
    }
    
    # Create base directory
    New-Item -ItemType Directory -Force -Path $VmBaseDir | Out-Null
    Write-Success "VM base directory created: $VmBaseDir"

    # Create master VM
    $masterIso = Join-Path $SeedDir "seed-master1.iso"
    $masterVmx = New-VM -Name $MasterName -IP $MasterIP -SeedIso $masterIso -HostOnlyNet $HostOnlyNet
    Write-Info "Master VMX path: $masterVmx"
    
    # Create worker VMs
    $workerVmx = @()
    for ($i=0; $i -lt $WorkerNames.Count; $i++) {
        $iso = Join-Path $SeedDir ("seed-worker{0}.iso" -f ($i+1))
        $workerVmxPath = New-VM -Name $WorkerNames[$i] -IP $WorkerIPs[$i] -SeedIso $iso -HostOnlyNet $HostOnlyNet
        $workerVmx += $workerVmxPath
        Write-Info "Worker VMX path: $workerVmxPath"
    }

    # Boot VMs if not skipped
    if (-not $SkipVMStart) {
        Write-Info "Starting VMs..."
        
        # Start master first
        Write-Info "Starting master VM: $MasterName"
        Write-Info "VMX file: $masterVmx"
        
        # Verify VMX file exists
        if (-not (Test-Path $masterVmx)) {
            Write-Error "VMX file does not exist: $masterVmx"
            exit 1
        }
        
        Write-Info "VMX file exists and is accessible"
        
        # Try different start methods
        $startSuccess = $false
        
        # Method 1: Try with GUI (preferred for visibility in VMware Workstation)
        Write-Info "Attempting to start VM with GUI (visible in VMware Workstation)..."
        $result = & $script:VMRUN_PATH -T ws start $masterVmx 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Master VM started successfully with GUI"
            $startSuccess = $true
        } else {
            Write-Warning "Failed to start with GUI (exit code: $LASTEXITCODE)"
            Write-Warning "Error output: $result"
            
            # Method 2: Try with nogui as fallback
            Write-Info "Attempting to start VM with nogui (background mode)..."
            $result = & $script:VMRUN_PATH -T ws start $masterVmx nogui 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Master VM started successfully with nogui"
                Write-Warning "VM is running in background. You may not see it in VMware Workstation GUI"
                $startSuccess = $true
            } else {
                Write-Warning "Failed to start with nogui (exit code: $LASTEXITCODE)"
                Write-Warning "Error output: $result"
            }
        }
        
        if (-not $startSuccess) {
            Write-Warning "All start methods failed for master VM"
            Write-Info "You may need to start the VM manually from VMware Workstation"
            Write-Info "VMX file location: $masterVmx"
        }
        
        # Wait a bit before starting workers
        Start-Sleep -Seconds 10
        
        # Start worker VMs
        for ($i=0; $i -lt $workerVmx.Count; $i++) {
            Write-Info "Starting worker VM: $($WorkerNames[$i])"
            Write-Info "VMX file: $($workerVmx[$i])"
            
            # Verify VMX file exists
            if (-not (Test-Path $workerVmx[$i])) {
                Write-Warning "VMX file does not exist: $($workerVmx[$i])"
                continue
            }
            
            Write-Info "VMX file exists and is accessible"
            
            # Try different start methods
            $startSuccess = $false
            
            # Method 1: Try with GUI (preferred for visibility in VMware Workstation)
            Write-Info "Attempting to start worker VM with GUI (visible in VMware Workstation)..."
            $result = & $script:VMRUN_PATH -T ws start $workerVmx[$i] 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Worker VM started successfully with GUI: $($WorkerNames[$i])"
                $startSuccess = $true
            } else {
                Write-Warning "Failed to start with GUI (exit code: $LASTEXITCODE)"
                Write-Warning "Error output: $result"
                
                # Method 2: Try with nogui as fallback
                Write-Info "Attempting to start worker VM with nogui (background mode)..."
                $result = & $script:VMRUN_PATH -T ws start $workerVmx[$i] nogui 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Worker VM started successfully with nogui: $($WorkerNames[$i])"
                    Write-Warning "VM is running in background. You may not see it in VMware Workstation GUI"
                    $startSuccess = $true
                } else {
                    Write-Warning "Failed to start with nogui (exit code: $LASTEXITCODE)"
                    Write-Warning "Error output: $result"
                }
            }
            
            if (-not $startSuccess) {
                Write-Warning "All start methods failed for worker VM: $($WorkerNames[$i])"
                Write-Info "You may need to start the VM manually from VMware Workstation"
                Write-Info "VMX file location: $($workerVmx[$i])"
            }
            
            Start-Sleep -Seconds 5
        }
        
        Write-Success "All VMs started successfully"
        
        # Wait for initial boot and then safely disconnect ISO to prevent reinstall loop
        Write-Info "Waiting for VMs to complete initial boot and file copy..."
        
        # Function to wait for ISO copy completion (improved version)
        function Wait-ForISOCopy {
            param(
                [string]$VmxPath,
                [string]$VmName,
                [int]$MaxWaitMinutes = 30
            )
            
            Write-Info "Waiting for ISO file copy completion on $VmName (max $MaxWaitMinutes minutes)..."
            $startTime = Get-Date
            $timeout = $startTime.AddMinutes($MaxWaitMinutes)
            $lastStatus = ""
            
            while ((Get-Date) -lt $timeout) {
                try {
                    # First, check if VM is responsive
                    $vmStatus = & $script:VMRUN_PATH -T ws list 2>$null | Select-String $VmName
                    if (-not $vmStatus) {
                        Write-Warning "VM $VmName not found in running VMs list, waiting..."
                        Start-Sleep -Seconds 30
                        continue
                    }
                    
                    # Wait for VM to be ready for guest operations (avoid authentication errors)
                    $vmReady = $false
                    $readyAttempts = 0
                    while (-not $vmReady -and $readyAttempts -lt 10) {
                        $readyAttempts++
                        try {
                            # Simple ping test to check if guest OS is ready
                            $pingTest = & $script:VMRUN_PATH -T ws -gu ubuntu -gp ubuntu runProgramInGuest $VmxPath "/bin/echo" "test" 2>$null
                            if ($LASTEXITCODE -eq 0) {
                                $vmReady = $true
                                Write-Info "VM $VmName is ready for guest operations"
                            } else {
                                Write-Info "VM $VmName not ready yet (attempt $readyAttempts/10), waiting..."
                                Start-Sleep -Seconds 15
                            }
                        } catch {
                            Write-Info "VM $VmName not ready yet (attempt $readyAttempts/10), waiting..."
                            Start-Sleep -Seconds 15
                        }
                    }
                    
                    if (-not $vmReady) {
                        Write-Warning "VM $VmName not ready for guest operations after 10 attempts, skipping this cycle"
                        Start-Sleep -Seconds 30
                        continue
                    }
                    
                    # Check if ISO copy completion file exists
                    $result = & $script:VMRUN_PATH -T ws -gu ubuntu -gp ubuntu runProgramInGuest $VmxPath "/bin/bash" "-c" "test -f /var/lib/iso-copy-complete && echo 'COMPLETE' || echo 'INCOMPLETE'" 2>$null
                    
                    if ($result -eq "COMPLETE") {
                        Write-Success "ISO file copy completed on $VmName"
                        return $true
                    }
                    
                    # Check cloud-init status with better error handling
                    $cloudInitStatus = & $script:VMRUN_PATH -T ws -gu ubuntu -gp ubuntu runProgramInGuest $VmxPath "/bin/bash" "-c" "cloud-init status 2>/dev/null || echo 'NOT_READY'" 2>$null
                    
                    # Check for specific cloud-init states
                    if ($cloudInitStatus -like "*running*") {
                        if ($lastStatus -ne "running") {
                            Write-Info "Cloud-init running on $VmName, waiting..."
                            $lastStatus = "running"
                        }
                    } elseif ($cloudInitStatus -like "*done*") {
                        if ($lastStatus -ne "done") {
                            Write-Info "Cloud-init completed on $VmName, checking file copy..."
                            $lastStatus = "done"
                        }
                    } elseif ($cloudInitStatus -like "*error*") {
                        Write-Warning ("Cloud-init error on " + $VmName + ": " + $cloudInitStatus)
                        $lastStatus = "error"
                    } elseif ($cloudInitStatus -like "*NOT_READY*") {
                        if ($lastStatus -ne "not_ready") {
                            Write-Info "VM $VmName still booting (cloud-init not ready)..."
                            $lastStatus = "not_ready"
                        }
                    } else {
                        if ($lastStatus -ne "unknown") {
                            Write-Info ("VM " + $VmName + " status: " + $cloudInitStatus)
                            $lastStatus = "unknown"
                        }
                    }
                    
                    # Additional check: look for specific completion indicators
                    $completionCheck = & $script:VMRUN_PATH -T ws -gu ubuntu -gp ubuntu runProgramInGuest $VmxPath "/bin/bash" "-c" "ls -la /usr/local/seed/ 2>/dev/null | wc -l || echo '0'" 2>$null
                    if ($completionCheck -and $completionCheck -match '^\d+$' -and [int]$completionCheck -gt 0) {
                        Write-Info "Seed files detected on $VmName, checking for completion..."
                    }
                    
                    # Check if k8s packages installation is complete
                    $k8sPackagesCheck = & $script:VMRUN_PATH -T ws -gu ubuntu -gp ubuntu runProgramInGuest $VmxPath "/bin/bash" "-c" "test -f /var/lib/k8s-ops-packages-installed && echo 'PACKAGES_INSTALLED' || echo 'PACKAGES_NOT_READY'" 2>$null
                    if ($k8sPackagesCheck -eq "PACKAGES_INSTALLED") {
                        Write-Info "K8s packages installation completed on $VmName"
                    }
                    
                    Start-Sleep -Seconds 30
                    
                } catch {
                    Write-Warning "Error checking $VmName status: $_"
                    Start-Sleep -Seconds 30
                }
            }
            
            Write-Warning "Timeout waiting for ISO copy completion on $VmName after $MaxWaitMinutes minutes"
            Write-Info "Last known status: $lastStatus"
            return $false
        }
        
        # Wait for master VM
        $masterCopyComplete = Wait-ForISOCopy -VmxPath $masterVmx -VmName $MasterName
        
        # Wait for worker VMs
        $workerCopyComplete = @()
        for ($i=0; $i -lt $workerVmx.Count; $i++) {
            $workerCopyComplete += Wait-ForISOCopy -VmxPath $workerVmx[$i] -VmName $WorkerNames[$i]
        }
        
        Write-Info "Disconnecting ISO files to prevent reinstall loop..."
        
        # Disconnect ISO from master VM using VMX modification
        Write-Info "Disconnecting ISO from master VM: $MasterName"
        try {
            # Stop VM first
            & $script:VMRUN_PATH -T ws stop $masterVmx soft 2>$null
            Start-Sleep -Seconds 5
            
            # Modify VMX to disable CD-ROM
            $vmxContent = Get-Content -Path $masterVmx -Raw
            $vmxContent = $vmxContent -replace 'sata0:1\.startConnected = "TRUE"', 'sata0:1.startConnected = "FALSE"'
            Set-Content -Path $masterVmx -Value $vmxContent -Encoding ASCII
            
            Write-Success "ISO safely disconnected from master VM (VMX modified)"
        } catch {
            Write-Warning "Failed to disconnect ISO from master VM: $_"
        }
        
        # Disconnect ISO from worker VMs using VMX modification
        for ($i=0; $i -lt $workerVmx.Count; $i++) {
            Write-Info "Disconnecting ISO from worker VM: $($WorkerNames[$i])"
            try {
                # Stop VM first
                & $script:VMRUN_PATH -T ws stop $workerVmx[$i] soft 2>$null
                Start-Sleep -Seconds 5
                
                # Modify VMX to disable CD-ROM
                $vmxContent = Get-Content -Path $workerVmx[$i] -Raw
                $vmxContent = $vmxContent -replace 'sata0:1\.startConnected = "TRUE"', 'sata0:1.startConnected = "FALSE"'
                Set-Content -Path $workerVmx[$i] -Value $vmxContent -Encoding ASCII
                
                Write-Success "ISO safely disconnected from worker VM: $($WorkerNames[$i]) (VMX modified)"
            } catch {
                Write-Warning "Failed to disconnect ISO from worker VM $($WorkerNames[$i]): $_"
            }
        }
        
        Write-Success "ISO disconnection completed"
        
        # Restart VMs to apply VMX changes
        Write-Info "Restarting VMs to apply VMX changes..."
        
        # Restart master VM
        Write-Info "Restarting master VM: $MasterName"
        try {
            & $script:VMRUN_PATH -T ws start $masterVmx 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Master VM restarted successfully"
            } else {
                Write-Warning "Failed to restart master VM, you may need to start it manually"
            }
        } catch {
            Write-Warning "Failed to restart master VM: $_"
        }
        
        # Restart worker VMs
        for ($i=0; $i -lt $workerVmx.Count; $i++) {
            Write-Info "Restarting worker VM: $($WorkerNames[$i])"
            try {
                & $script:VMRUN_PATH -T ws start $workerVmx[$i] 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Worker VM restarted successfully: $($WorkerNames[$i])"
                } else {
                    Write-Warning "Failed to restart worker VM: $($WorkerNames[$i]), you may need to start it manually"
                }
            } catch {
                Write-Warning "Failed to restart worker VM $($WorkerNames[$i]): $_"
            }
            Start-Sleep -Seconds 5
        }
        
    } else {
        Write-Info "VM startup skipped (use -SkipVMStart to skip)"
    }

    # Display summary
    Write-Success "VM creation completed successfully!"
    Write-Info "VM Summary:"
    Write-Info "  Master: $MasterName ($MasterIP) - $masterVmx"
    for ($i=0; $i -lt $WorkerNames.Count; $i++) {
        Write-Info "  Worker$($i+1): $($WorkerNames[$i]) ($($WorkerIPs[$i])) - $($workerVmx[$i])"
    }
    Write-Info ""
    Write-Info "Next steps:"
    Write-Info "1. Wait for VMs to boot and cloud-init to complete"
    Write-Info "2. Run the verification script: ./wsl/scripts/02_wait_and_config.sh"
    Write-Info "3. SSH to master: ssh -i ./wsl/out/ssh/id_rsa ubuntu@$MasterIP"
    Write-Info ""
    Write-Info "Network Information:"
    Write-Info "  - Master: $MasterName ($MasterIP)"
    Write-Info "  - Workers: $($WorkerNames -join ', ') ($($WorkerIPs -join ', '))"
    Write-Info "  - Registry: 192.168.6.1:5000"
    Write-Info "  - Gateway: 192.168.6.1"
    
} catch {
    Write-Error "An error occurred: $_"
    exit 1
}
