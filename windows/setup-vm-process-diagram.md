### VM Setup Orchestration (setup-vms.ps1 ↔ Setup-VMs.ps1)

This document illustrates the end-to-end flow between `scripts/setup-vms.ps1` and `windows/Setup-VMs.ps1`, including the SSH-only readiness/completion checks and marker-based completion policy.

```mermaid
flowchart TD
  A["User runs scripts/setup-vms.ps1 (Admin PowerShell)"] --> A1["Detect vmrun path and set env VMRUN_PATH"]
  A --> A2["Set UTF-8 console, show config (VM dir, IPs)"]
  A --> A3["Invoke windows/Setup-VMs.ps1 with parameters"]

  subgraph "Windows/Setup-VMs.ps1"
    direction TB
    B1["Prerequisites"]
    B1 -->|"vmrun/vdiskmanager present, seed ISOs exist"| B2["Cleanup Existing VMs"]
    B2 --> B3["Create Master VM"]
    B3 --> B4["Create Worker VMs"]
    B4 --> B5["Start VMs (GUI→nogui fallback)"]

    B5 --> B6["Wait-ForVMReady (SSH-first)"]
    subgraph B6_details["Wait-ForVMReady"]
      direction TB
      W1["SSH using id_rsa (ConnectTimeout=5)"]
      W1 --> W2["Run 'echo vm_ready'"]
      W2 -->|"success"| W3["Ready"]
      W2 -->|"retry"| W1
    end

    B6 --> B7["Monitor Initialization Completion (SSH-only)"]
    subgraph B7_details["Check-CompletionStatus"]
      direction TB
      C1["Determine role from VmName"]
      C1 --> C2["Build completion cmd"]
      C2 -->|"Master"| C2M["test -f /var/lib/k3s-bootstrap.done"]
      C2 -->|"Worker"| C2W["test -f /var/lib/k3s-agent-bootstrap.done"]
      C2 -->|"Unknown"| C2U["test -f either marker"]
      C2M --> C3["SSH 'bash -lc <cmd>'"]
      C2W --> C3
      C2U --> C3
      C3 -->|"STATE_COMPLETE"| C4["Completed"]
      C3 -->|"Incomplete"| C5["Retry until timeout"]
    end

    B7 --> B8["Disconnect ISOs (modify VMX)"]
    B8 --> B9["Restart VMs"]
    B9 --> B10["Summary & Next Steps"]
  end

  subgraph "Guest(VM)"
    direction TB
    G1["Autoinstall via cloud-init"]
    G1 --> G2["late-commands: copy /cdrom/files → /usr/local/seed"]
    G2 --> G3["Write /var/lib/iso-copy-complete"]
    G1 --> G4["user-data runcmd: write /var/lib/cloud-init-complete"]
    G1 --> G5["Install system units: sync-time, k3s-bootstrap/agent"]
    G5 --> G6["Start k3s server/agent"]
    G6 --> G7["On success write k3s markers"]
    G7 -->|"Master"| G7M["/var/lib/k3s-bootstrap.done"]
    G7 -->|"Worker"| G7W["/var/lib/k3s-agent-bootstrap.done"]
  end

  classDef done fill:#e8fff0,stroke:#2ca02c,color:#2ca02c;
  classDef warn fill:#fff7e6,stroke:#ff9900,color:#ff9900;
  class B6_details,B7_details done;
```

Notes:
- Readiness (B6) and Completion (B7) checks are SSH-only; vmrun guest commands are not required.
- Completion requires k3s bootstrap markers only; early markers (`/var/lib/iso-copy-complete`, `/var/lib/cloud-init-complete`) are not sufficient.
