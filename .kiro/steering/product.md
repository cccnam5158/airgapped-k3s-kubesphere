# Product Overview

## Airgapped Kubernetes Lab Environment

This project provides a complete offline Kubernetes cluster setup using VMware Workstation Pro on Windows 10/11. It creates an airgapped k3s cluster with KubeSphere management platform, designed for secure environments where internet connectivity is restricted or prohibited.

### Key Features
- **Complete Offline Operation**: All components run without internet connectivity
- **Automated Setup**: Script-based installation and configuration
- **Current Environment Optimized**: Tailored for Windows 10/11 + WSL2 + VMware Workstation
- **Latest Versions**: k3s v1.33.4-rc1, KubeSphere v4.1.3
- **Compatibility Assured**: Tested version combinations for stability
- **Local Docker Registry**: Image mirroring for offline support

### Target Users
- System administrators learning Kubernetes in secure environments
- Developers needing isolated Kubernetes testing environments
- Organizations requiring airgapped container orchestration
- Educational institutions teaching Kubernetes concepts

### Architecture
- **Windows Host**: Runs VMware Workstation and PowerShell automation scripts
- **WSL2 Build Environment**: Ubuntu 22.04 LTS for image mirroring and ISO generation
- **VM Target Environment**: 1 Master + 2 Worker nodes running Ubuntu 22.04.5 LTS
- **Network**: Host-only network (192.168.6.0/24) for complete isolation

### Core Components
- k3s v1.33.4-rc1+k3s1 (lightweight Kubernetes)
- KubeSphere v4.1.3 (container platform)
- Ubuntu 22.04.5 LTS (VM operating system)
- Docker Registry 2.8.1 (private registry)
- 26 pre-mirrored container images