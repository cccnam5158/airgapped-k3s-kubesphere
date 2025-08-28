#!/usr/bin/env bash

# k3s diagnostic script for master/worker nodes (airgapped)
# - Collects system, cloud-init, k3s bootstrap, process/port, files, and cluster info
# - Safe to run without root; uses sudo -n when available; continues on errors

set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }

# Run a command that may need root; prefer sudo -n if not root
run_root() {
  if is_root; then
    bash -lc "$*" 2>&1
    return
  fi
  if have_cmd sudo && sudo -n true 2>/dev/null; then
    sudo bash -lc "$*" 2>&1
  else
    warn "Not root and passwordless sudo unavailable. Attempting without sudo: $*"
    bash -lc "$*" 2>&1
  fi
}

sec() {
  echo
  echo "========== $* =========="
}

main() {
  sec "Basic system info"
  date || true
  uname -a || true
  echo -n "whoami: "; whoami || true
  echo -n "hostname: "; hostname || true
  echo -n "lsb_release: "; (lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | sed -n '1,3p' || true)

  sec "Network"
  (have_cmd ip && ip -br a) || (ifconfig -a 2>/dev/null || true)
  (have_cmd ip && ip r) || (route -n 2>/dev/null || true)
  echo "DNS (resolv.conf):"; head -n 50 /etc/resolv.conf 2>/dev/null || true
  echo "Kernel modules (overlay, br_netfilter):"; run_root 'lsmod | egrep "(^| )overlay|br_netfilter" || true'
  echo "sysctl k8s params:"; run_root 'sysctl -a 2>/dev/null | egrep "bridge-nf|ip_forward" || true'

  sec "cloud-init status/logs"
  (have_cmd cloud-init && run_root 'cloud-init status --long') || warn "cloud-init not present"
  echo "- tail cloud-init.log:"; run_root 'tail -n 200 /var/log/cloud-init.log' || true
  echo "- grep k3s bootstrap refs:"; run_root 'grep -n "k3s-bootstrap\|k3s-agent-bootstrap\|setup-k3s-" /var/log/cloud-init.log' || true

  sec "k3s bootstrap units and scripts"
  run_root 'systemctl is-enabled k3s-bootstrap 2>/dev/null || true'; run_root 'systemctl is-active k3s-bootstrap 2>/dev/null || true'; run_root 'systemctl is-failed k3s-bootstrap 2>/dev/null || true'
  run_root 'systemctl is-enabled k3s-agent-bootstrap 2>/dev/null || true'; run_root 'systemctl is-active k3s-agent-bootstrap 2>/dev/null || true'; run_root 'systemctl is-failed k3s-agent-bootstrap 2>/dev/null || true'
  ls -l /etc/systemd/system/k3s-bootstrap.service 2>/dev/null || true
  ls -l /etc/systemd/system/k3s-agent-bootstrap.service 2>/dev/null || true
  ls -l /usr/local/bin/setup-k3s-master.sh 2>/dev/null || true
  ls -l /usr/local/bin/setup-k3s-worker.sh 2>/dev/null || true
  echo "- last logs (k3s-bootstrap):"; run_root 'journalctl -u k3s-bootstrap -n 120 --no-pager' || true
  echo "- last logs (k3s-agent-bootstrap):"; run_root 'journalctl -u k3s-agent-bootstrap -n 120 --no-pager' || true

  sec "Seed and config files"
  ls -ld /usr/local/seed 2>/dev/null || true
  ls -l /usr/local/seed 2>/dev/null | head -n 50 || true
  ls -l /usr/local/bin/k3s 2>/dev/null || echo "k3s binary missing at /usr/local/bin/k3s"
  [ -x /usr/local/bin/k3s ] && /usr/local/bin/k3s -v || true
  ls -l /etc/rancher/k3s/registries.yaml 2>/dev/null || true
  ls -l /usr/local/share/ca-certificates/airgap-registry-ca.crt 2>/dev/null || true
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "k3s kubeconfig present: /etc/rancher/k3s/k3s.yaml"
    grep -n 'server:' /etc/rancher/k3s/k3s.yaml || true
  else
    warn "k3s kubeconfig not found yet"
  fi

  sec "k3s process/ports"
  ps -ef | grep -E "\[k\]3s|kube|containerd" || true
  (have_cmd ss && ss -lntp 2>/dev/null | egrep ':(6443|10250|2379)') || (netstat -lntp 2>/dev/null | egrep ':(6443|10250|2379)' || true)

  sec "k3s server token (masked)"
  if [ -f /var/lib/rancher/k3s/server/token ]; then
    tok=$(head -c 8 /var/lib/rancher/k3s/server/token 2>/dev/null || true)
    echo "token starts with: ${tok}******** (full token not shown)"
  else
    echo "token file not present (expected on master after init)"
  fi

  sec "k3s containerd and images"
  [ -x /usr/local/bin/k3s ] && /usr/local/bin/k3s ctr version 2>/dev/null || true
  [ -x /usr/local/bin/k3s ] && /usr/local/bin/k3s ctr images ls 2>/dev/null | head -n 30 || true
  if [ -f /usr/local/seed/k3s-airgap-images-amd64.tar.gz ]; then
    echo "airgap image tar exists at /usr/local/seed/k3s-airgap-images-amd64.tar.gz"
  fi

  sec "Cluster queries (best-effort)"
  # try various kubectl invocations
  KUBECTL_CMD=""
  for c in "kubectl" "/usr/local/bin/k3s kubectl"; do
    if bash -lc "$c version --short" >/dev/null 2>&1; then KUBECTL_CMD="$c"; break; fi
  done
  if [ -n "$KUBECTL_CMD" ]; then
    ok "Using kubectl: $KUBECTL_CMD"
    bash -lc "$KUBECTL_CMD get nodes -o wide" 2>&1 || true
    bash -lc "$KUBECTL_CMD get pods -A --no-headers | head -n 30" 2>&1 || true
    bash -lc "$KUBECTL_CMD cluster-info" 2>&1 || true
  else
    warn "kubectl not available yet"
  fi

  sec "Agent -> master reachability test"
  # if kubeconfig exists, extract server host; else try default 192.168.6.10
  MASTER_HOST=""
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    MASTER_HOST=$(grep -m1 'server:' /etc/rancher/k3s/k3s.yaml | sed -E 's/.*https:\/\/([^:]+):.*/\1/' 2>/dev/null || true)
  fi
  [ -z "$MASTER_HOST" ] && MASTER_HOST="192.168.6.10"
  echo "Testing TCP 6443 to $MASTER_HOST ..."
  timeout 3 bash -lc "</dev/tcp/$MASTER_HOST/6443" 2>/dev/null && echo "port 6443 reachable" || echo "port 6443 NOT reachable"

  sec "Done"
}

main "$@"


