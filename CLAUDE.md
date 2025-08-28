# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **airgapped Kubernetes lab environment** that sets up a complete offline k3s cluster with KubeSphere on VMware Workstation. The project creates a self-contained environment that works entirely without internet connectivity by pre-mirroring all required container images and dependencies.

## Key Architecture Components

### Environment Structure
- **Host Environment**: Windows 10/11 with VMware Workstation Pro
- **Build Environment**: WSL2 Ubuntu 22.04 for image preparation and ISO creation  
- **Target Environment**: 3 Ubuntu 22.04.5 LTS VMs (1 master + 2 workers)
- **Network**: Isolated VMnet1 network (192.168.6.0/24) with local container registry

### Core Components
- **k3s**: v1.33.4-rc1+k3s1 (lightweight Kubernetes)
- **KubeSphere**: v4.1.3 (container management platform)
- **Local Registry**: Docker registry:2 running on 192.168.6.1:5000
- **Mirrored Images**: 26+ pre-pulled container images for offline operation

## Common Development Commands

### Environment Setup (PowerShell as Administrator)
```powershell
# Check prerequisites and environment
.\scripts\check-env.ps1

# Setup port forwarding for registry access
.\scripts\setup-port-forwarding.ps1

# Test registry connectivity 
.\scripts\test-registry-access.ps1

# Clean up VMs
.\scripts\cleanup-vms.ps1
```

### Build Process (WSL2 Ubuntu)
```bash
# 1. Prepare offline environment (downloads images, creates certificates)
cd wsl/scripts
./00_prep_offline_fixed.sh

# 2. Build Ubuntu seed ISOs with cloud-init configuration
./01_build_seed_isos.sh

# 3. Verify cluster after VM creation
./02_wait_and_config.sh

# Clean up build artifacts
./01_build_seed_isos.sh --cleanup-only
```

### VM Management (PowerShell as Administrator) 
```powershell
# Create and start all VMs
.\windows\Setup-VMs.ps1

# Create VMs without starting them
.\windows\Setup-VMs.ps1 -SkipVMStart

# Customize VM resources
.\windows\Setup-VMs.ps1 -VMemGB 8 -VCPU 4 -DiskGB 60
```

### Container Registry Operations (WSL2)
```bash
# Check registry status
docker ps | grep registry

# View mirrored images catalog
curl -k https://localhost:5000/v2/_catalog | jq

# Restart registry if needed
docker restart airgap-registry
```

### Cluster Access
```bash
# SSH to master node
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.10

# SSH to worker nodes  
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.11
ssh -i ./wsl/out/ssh/id_rsa ubuntu@192.168.6.12

# Access kubectl on master
k3s kubectl get nodes -o wide
k3s kubectl get pods -A
```

## Project Structure and Key Files

### Configuration Files
- `wsl/examples/images-fixed.txt` - List of container images to mirror for offline use
- `wsl/templates/user-data-master.tpl` - cloud-init template for k3s master node
- `wsl/templates/user-data-worker.tpl` - cloud-init template for k3s worker nodes
- `wsl/out/registries.yaml` - k3s registry configuration for airgapped setup

### Build Scripts
- `wsl/scripts/00_prep_offline_fixed.sh` - Downloads and mirrors all container images, creates TLS certificates
- `wsl/scripts/01_build_seed_isos.sh` - Creates Ubuntu seed ISOs with embedded cloud-init and k3s components
- `wsl/scripts/02_wait_and_config.sh` - Waits for VMs to boot and verifies cluster formation

### Windows Scripts  
- `scripts/check-env.ps1` - Validates Windows environment prerequisites
- `scripts/setup-port-forwarding.ps1` - Configures Windows port forwarding for registry access
- `windows/Setup-VMs.ps1` - Creates and configures VMware VMs

### Output Locations
- `wsl/out/` - All generated artifacts (ISOs, certificates, SSH keys, binaries)
- `wsl/out/registry/` - Docker registry storage volume
- `wsl/out/ssh/id_rsa` - SSH private key for VM access
- `wsl/out/certs/` - TLS certificates for registry

## Network Configuration

| Component | IP Address | Purpose |
|-----------|------------|---------|
| Windows Host/Registry | 192.168.6.1:5000 | Container registry endpoint |
| k3s Master | 192.168.6.10 | Kubernetes control plane |
| k3s Worker 1 | 192.168.6.11 | Kubernetes worker node |
| k3s Worker 2 | 192.168.6.12 | Kubernetes worker node |

**Important**: All VMs use VMnet1 (host-only network) to maintain complete network isolation while allowing access to the Windows-hosted container registry.

## Working with this Project

### Making Changes to VM Configuration
1. Modify templates in `wsl/templates/` for cloud-init changes
2. Update image lists in `wsl/examples/` for container changes  
3. Rebuild ISOs with `./01_build_seed_isos.sh` after template changes
4. Recreate VMs with `.\windows\Setup-VMs.ps1` after ISO changes

### Debugging Build Issues
- Check logs in `wsl/scripts/build_log_*.log` files
- Use `docker logs airgap-registry` to debug registry issues
- Verify file permissions on generated artifacts in `wsl/out/`
- Check WSL2 Docker daemon with `docker info`

### Extending the Environment
- Add new container images to `wsl/examples/images-fixed.txt`
- Update k3s version by changing download URLs in `00_prep_offline_fixed.sh`
- Modify VM specs by updating parameters in `Setup-VMs.ps1`
- Add new cloud-init steps in template files for additional software

## Important Notes

- **No Git Repository**: This project is not version-controlled; changes are made directly to files
- **Windows Dependencies**: Requires VMware Workstation Pro and WSL2 Ubuntu 22.04
- **Airgapped Design**: All internet connectivity happens only during initial image mirroring phase
- **Version Compatibility**: k3s v1.33.4-rc1 is specifically chosen for KubeSphere v4.1.3 compatibility
- **Certificate Management**: Uses self-signed certificates for the local container registry