#cloud-config
autoinstall:
  version: 1
  # 자동 설치를 위한 기본 구성
  early-commands:
    - systemctl stop ssh
    - echo "=== Cloud-init early-commands 시작 (Worker) ===" >> /var/log/cloud-init-debug.log
    - date >> /var/log/cloud-init-debug.log
    - echo "네트워크 인터페이스 비활성화 중..." >> /var/log/cloud-init-debug.log
    - systemctl stop networking 2>/dev/null || true
    - ip link set dev eth0 down 2>/dev/null || true
    - ip link set dev enp0s3 down 2>/dev/null || true
    - ip link set dev ens33 down 2>/dev/null || true
    - echo "네트워크 인터페이스 비활성화 완료" >> /var/log/cloud-init-debug.log
    - echo "DNS 설정 비활성화 중..." >> /var/log/cloud-init-debug.log
    - echo "nameserver 127.0.0.1" > /etc/resolv.conf
    - echo "DNS 설정 비활성화 완료" >> /var/log/cloud-init-debug.log
    - echo "언어 설정 강제 적용 중..." >> /var/log/cloud-init-debug.log
    - bash -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen'
    - bash -c 'echo "LANG=en_US.UTF-8" > /etc/default/locale'
    - bash -c 'echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale'
    - bash -c 'echo "KEYBOARD_LAYOUT=us" > /etc/default/keyboard'
    - echo "언어 설정 강제 적용 완료" >> /var/log/cloud-init-debug.log
    - echo "APT 타임아웃 설정 적용 중..." >> /var/log/cloud-init-debug.log
    - |
      bash -c 'cat > /etc/apt/apt.conf.d/99-timeouts <<EOF
      Acquire::Retries "0";
      Acquire::http::Timeout "1";
      Acquire::https::Timeout "1";
      Acquire::ftp::Timeout "1";
      Acquire::cdrom::Timeout "1";
      Acquire::gpgv::Timeout "1";
      Acquire::http::Pipeline-Depth "0";
      Acquire::Languages "none";
      Acquire::Check-Valid-Until "false";
      Acquire::Check-Date "false";
      Acquire::AllowInsecureRepositories "true";
      Acquire::AllowDowngradeToInsecureRepositories "true";
      EOF'
    - echo 'Acquire::http::Proxy "false";' > /etc/apt/apt.conf.d/00-no-net
    - echo "APT 타임아웃 설정 완료" >> /var/log/cloud-init-debug.log
    - echo "APT 주기 작업 및 unattended-upgrades 비활성화 중..." >> /var/log/cloud-init-debug.log
    - systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null || true
    - systemctl disable apt-daily.service apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null || true
    - systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    - systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    - systemctl mask apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
    - |
      bash -c 'cat > /etc/apt/apt.conf.d/10periodic <<EOF
      APT::Periodic::Enable "0";
      APT::Periodic::Update-Package-Lists "0";
      APT::Periodic::Unattended-Upgrade "0";
      EOF'
    - |
      bash -c 'cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
      APT::Periodic::Update-Package-Lists "0";
      APT::Periodic::Unattended-Upgrade "0";
      EOF'
    - echo "APT 주기 작업 및 unattended-upgrades 비활성화 완료" >> /var/log/cloud-init-debug.log
    - echo "네트워크 APT 소스 비활성화(airgap) 진행... (cdrom 보존)" >> /var/log/cloud-init-debug.log
    - bash -c 'cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true'
    - bash -c 'sed -i "s/^deb http/# deb http/; s/^deb https/# deb https/" /etc/apt/sources.list 2>/dev/null || true'
    - bash -c 'for f in /etc/apt/sources.list.d/*.list; do [ -e "$f" ] || continue; sed -i "s/^deb http/# deb http/; s/^deb https/# deb https/" "$f"; done; exit 0'
    - bash -c 'mkdir -p /etc/apt/disabled-sources; for f in /etc/apt/sources.list.d/*.sources; do [ -e "$f" ] || continue; mv "$f" /etc/apt/disabled-sources/; done; exit 0'
    - bash -c 'echo "APT::Get::AllowUnauthenticated \"true\";" > /etc/apt/apt.conf.d/99-allow-unauth'
    - bash -c 'echo "APT::Get::AllowDowngrades \"true\";" >> /etc/apt/apt.conf.d/99-allow-unauth'
    - echo "네트워크 APT 소스 비활성화 완료 (cdrom 유지)" >> /var/log/cloud-init-debug.log
  # 언어 및 키보드 설정 (자동 설치를 위해 명시적 설정)
  locale: en_US.UTF-8
  keyboard:
    layout: us
    variant: ''
  timezone: Asia/Seoul
  
  # APT mirror auto-detection tweaks for airgap speed
  apt:
    preserve_sources_list: false
    geoip: false
    primary:
      - arches: [default]
        uri: "file:/cdrom"

  curtin:
    apt:
      preserve_sources_list: false
      geoip: false
      primary:
        - arches: [default]
          uri: "file:/cdrom"
      conf: |
        Acquire::Retries "0";
        Acquire::http::Timeout "1";
        Acquire::https::Timeout "1";
        Acquire::ftp::Timeout "1";
        Acquire::cdrom::Timeout "1";
        Acquire::gpgv::Timeout "1";
        Acquire::http::Pipeline-Depth "0";
        Acquire::Languages "none";
        Acquire::Check-Valid-Until "false";
        Acquire::Check-Date "false";
        Acquire::AllowInsecureRepositories "true";
        Acquire::AllowDowngradeToInsecureRepositories "true";
      sources:
        cdrom:
          source: "deb [trusted=yes] file:/cdrom jammy main"
    
  # 인터랙티브 프롬프트 비활성화 (모든 섹션 비활성화)
  interactive-sections: []
  
  # 자동 설치를 위한 추가 설정
  shutdown: reboot
  reboot: true
  
  # 완전 자동 설치를 위한 추가 설정
  packages:
    - openssh-server
    - curl
    - wget
    - ca-certificates
  # 네트워크 설정 (정적 IP)
  network:
    version: 2
    ethernets:
      en0:
        match:
          name: "e*"
        optional: true
        dhcp4: false
        addresses:
          - ${WORKER_IP}/24
        gateway4: ${GATEWAY_IP}
        nameservers:
          addresses:
            - ${DNS_IP}
  # SSH 서버 설치 (패스워드 인증 비활성화, 키 기반 인증만 허용)
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ${SSH_PUBLIC_KEY}
  # 스토리지 설정 (전체 디스크 사용)
  storage:
    layout:
      name: direct
  # 사용자 설정 (임시 패스워드, 설치 후 비활성화)
  identity:
    hostname: k3s-worker1
    username: ubuntu
    password: ${PASSWORD_HASH}
  # 설치 후 재부팅
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - mkdir -p /target/usr/local/seed
    - if [ -d /cdrom/files ]; then cp -a /cdrom/files/. /target/usr/local/seed/; fi
    - sync
    - echo "=== Cloud-init late-commands 완료 (Worker) ===" >> /var/log/cloud-init-debug.log
    - date >> /var/log/cloud-init-debug.log
    - echo "설치 완료, 재부팅 준비 중..." >> /var/log/cloud-init-debug.log
    - echo "ISO 파일 복사 완료" > /target/var/lib/iso-copy-complete

  user-data:
    # 에어갭 환경에서는 package_update/upgrade 비활성화
    package_update: false
    package_upgrade: false
    # 표준 시간대 설정 (KST)
    timezone: Asia/Seoul
    
    # SSH 키 추가 (기존 ubuntu 사용자에)
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

    write_files:
      # Cloud-init 로깅 설정
      - path: /etc/cloud/cloud.cfg.d/99-debug.cfg
        permissions: '0644'
        content: |
          # Cloud-init 디버그 로깅 활성화
          debug: true
          verbose: true
          # 로그 레벨 설정
          log_level: DEBUG
          # 로그 파일 설정
          log_file: /var/log/cloud-init.log
          # 콘솔 출력 활성화
          output:
            all: [console, log]

      # Speed up apt by lowering retries/timeouts in airgapped installs
      - path: /etc/apt/apt.conf.d/99-timeouts
        permissions: '0644'
        content: |
          Acquire::Retries "0";
          Acquire::http::Timeout "1";
          Acquire::https::Timeout "1";
          Acquire::ftp::Timeout "1";
          Acquire::cdrom::Timeout "1";
          Acquire::gpgv::Timeout "1";
          Acquire::Languages "none";
          Acquire::Check-Valid-Until "false";
          Acquire::Check-Date "false";
          Acquire::AllowInsecureRepositories "true";
          Acquire::AllowDowngradeToInsecureRepositories "true";

      # CA certificate will be copied from CD by setup script to avoid YAML literal issues

      # Network configuration for Kubernetes
      - path: /etc/sysctl.d/99-k8s.conf
        permissions: '0644'
        content: |
          net.bridge.bridge-nf-call-iptables = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward = 1
          vm.swappiness = 0
          kernel.keys.root_maxkeys = 1000000
          kernel.keys.root_maxbytes = 25000000

      # Disable swap permanently
      - path: /etc/systemd/system/disable-swap.service
        permissions: '0644'
        content: |
          [Unit]
          Description=Disable Swap
          After=multi-user.target
          
          [Service]
          Type=oneshot
          ExecStart=/sbin/swapoff -a
          ExecStart=/bin/sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
          RemainAfterExit=true
          
          [Install]
          WantedBy=multi-user.target

      # SSH 보안 설정 강화
      - path: /etc/ssh/sshd_config.d/99-security.conf
        permissions: '0644'
        content: |
          # 패스워드 인증 비활성화
          PasswordAuthentication no
          PermitEmptyPasswords no
          # 키 기반 인증만 허용
          PubkeyAuthentication yes
          AuthorizedKeysFile .ssh/authorized_keys
          # 루트 로그인 비활성화
          PermitRootLogin no
          # SSH 프로토콜 버전 2만 사용
          Protocol 2
          # 연결 타임아웃 설정
          ClientAliveInterval 300
          ClientAliveCountMax 2

      # Console auto-login for ubuntu on tty1
      - path: /etc/systemd/system/getty@tty1.service.d/override.conf
        permissions: '0644'
        content: |
          [Service]
          ExecStart=
          ExecStart=-/sbin/agetty --autologin ubuntu --noclear %I ${DOLLAR}TERM

      # Serial console auto-login on ttyS0 (matches kernel console=ttyS0)
      - path: /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf
        permissions: '0644'
        content: |
          [Service]
          ExecStart=
          ExecStart=-/sbin/agetty --autologin ubuntu --keep-baud 115200,38400,9600 %I ${DOLLAR}TERM

      # K8s 운영 패키지 설치 스크립트
      - path: /usr/local/bin/install-k8s-ops-packages.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/bin/bash
          set -euo pipefail
          
          log() { echo "[k8s-ops-install] $1"; }
          
          # 이미 설치된 경우 스킵
          if [[ -f /var/lib/k8s-ops-packages-installed ]]; then
            log "marker exists; skip"
            exit 0
          fi
          
          log "K8s 운영 패키지 설치 시작..."
          
          # 패키지 디렉토리 확인 (고정 경로 사용)
          packages_dir="/usr/local/seed/packages"
          if [[ ! -d "$packages_dir" ]]; then
            log "패키지 디렉토리 없음: $packages_dir (skip)"
            echo "$(date): no packages dir; skipped" > /var/lib/k8s-ops-packages-installed
            exit 0
          fi
          
          cd "$packages_dir"
          
          # tar.gz 파일이 있으면 압축 해제 (없으면 스킵)
          if [[ -s "k8s-ops-packages.tar.gz" ]]; then
            log "k8s-ops-packages.tar.gz 압축 해제 중..."
            tar -xzf "k8s-ops-packages.tar.gz"
            log "압축 해제 완료"
          else
            log "압축 파일 없음 또는 빈 파일 (skip)"
            echo "$(date): empty/no archive; skipped" > /var/lib/k8s-ops-packages-installed
            exit 0
          fi
          
          # 설치 순서 최적화: 의존성 패키지 먼저 설치
          log "의존성 패키지 먼저 설치 중..."
          for deb_file in lib*.deb; do
            if [[ -f "$deb_file" ]]; then
              log "의존성 패키지 설치 중: $deb_file"
              dpkg -i "$deb_file" || log "의존성 패키지 설치 실패: $deb_file"
            fi
          done
          
          # 오프라인 고정 옵션 (sources 비활성화)
          APT_OFFLINE_OPTS='-o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=/dev/null -o APT::Get::List-Cleanup=0'
          
          # 의존성 문제 해결 (1차; 오프라인)
          log "1차 의존성 해결 (offline apt-get -f)"
          apt-get ${APT_OFFLINE_OPTS} -y install -f || log "1차 의존성 해결 실패(무시)"
          
          # 주요 패키지들 설치
          log "주요 패키지들 설치 중..."
          for deb_file in *.deb; do
            if [[ -f "$deb_file" && ! "$deb_file" =~ ^lib ]]; then
              log "패키지 설치 중: $deb_file"
              dpkg -i "$deb_file" || log "패키지 설치 실패: $deb_file"
            fi
          done
          
          # 의존성 문제 해결 (2차; 오프라인)
          log "2차 의존성 해결 (offline apt-get -f)"
          apt-get ${APT_OFFLINE_OPTS} -y install -f || log "2차 의존성 해결 실패(무시)"
          
          # 설치 완료 확인
          log "설치된 패키지 확인 중..."
          dpkg -l | grep -E "(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)" || log "설치된 패키지 없음"
          
          # 설치 성공률 계산
          total_packages=8
          installed_count=0
          for cmd in jq htop ethtool ip dig telnet fuser iostat; do
            if command -v "$cmd" >/dev/null 2>&1; then
              installed_count=$((installed_count + 1))
            fi
          done
          success_rate=$(( (installed_count * 100) / total_packages ))
          
          log "설치 성공률: $installed_count/$total_packages ($success_rate%)"
          
          # 설치 완료 마커 파일 생성
          echo "$(date): k8s 운영 패키지 설치 완료 (성공률: $success_rate%)" > /var/lib/k8s-ops-packages-installed
          log "패키지 설치 완료!"
          
          # 정리
          rm -f *.deb
          log "임시 deb 파일들 정리 완료"

      # Systemd service to bootstrap K3s agent at first boot (retries)
      - path: /etc/systemd/system/k3s-agent-bootstrap.service
        permissions: '0644'
        content: |
          [Unit]
          Description=K3s Worker Bootstrap
          After=local-fs.target network-online.target sync-time.service k8s-ops-packages.service
          Wants=network-online.target sync-time.service
          ConditionPathExists=/usr/local/bin/setup-k3s-worker.sh

          [Service]
          Type=simple
          User=root
          ExecStart=/usr/local/bin/setup-k3s-worker.sh
          Restart=on-failure
          RestartSec=5s

          [Install]
          WantedBy=multi-user.target

      # K8s 운영 패키지 설치 서비스
      - path: /etc/systemd/system/k8s-ops-packages.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Install K8s Operations Packages
          After=local-fs.target network-online.target
          Wants=network-online.target
          ConditionPathExists=/usr/local/bin/install-k8s-ops-packages.sh

          [Service]
          Type=oneshot
          User=root
          ExecStart=/usr/local/bin/install-k8s-ops-packages.sh
          RemainAfterExit=true
          StandardOutput=journal
          StandardError=journal

          [Install]
          WantedBy=multi-user.target

      # Time sync script (pick the newest between HTTP Date and seed epoch)
      - path: /usr/local/bin/sync-time.sh
        permissions: '0755'
        content: |
          #!/bin/bash
          set -euo pipefail
          REGISTRY_HOST_IP="${REGISTRY_HOST_IP}"
          REGISTRY_PORT="${REGISTRY_PORT}"

          log() { echo "[sync-time] ${DOLLAR}1"; }
          dbg() { echo "[DEBUG] ${DOLLAR}1" >&2; }

          disable_ntp() {
            if command -v timedatectl >/dev/null 2>&1; then
              dbg "Disabling NTP via timedatectl"
              timedatectl set-ntp false || true
            fi
          }

          resolve_seed_file() {
            local m p
            for p in \
              "/usr/local/seed/build-timestamp" \
              "/cdrom/files/build-timestamp" \
              "/cdrom/build-timestamp" \
              "/mnt/cdrom/files/build-timestamp" \
              "/mnt/cdrom/build-timestamp"; do
              [[ -f "${DOLLAR}p" ]] && { dbg "Found seed file: ${DOLLAR}p"; echo "${DOLLAR}p"; return 0; }
            done
            m=/mnt/cdrom
            mkdir -p "${DOLLAR}m"
            dbg "Trying to mount CD-ROM to ${DOLLAR}m"
            mount /dev/sr0 "${DOLLAR}m" 2>/dev/null || mount /dev/cdrom "${DOLLAR}m" 2>/dev/null || mount /dev/scd0 "${DOLLAR}m" 2>/dev/null || true
            for p in "/files/build-timestamp" "/build-timestamp"; do
              [[ -f "${DOLLAR}m${DOLLAR}p" ]] && { dbg "Found seed file after mount: ${DOLLAR}m${DOLLAR}p"; echo "${DOLLAR}m${DOLLAR}p"; return 0; }
            done
            dbg "Seed file not found"
            return 1
          }

          sync_with_wsl_host() {
            local wsl_time=""
            dbg "Attempting to read Windows LocalDateTime from WMIC"

            if [[ -f /mnt/c/Windows/System32/wbem/wmic.exe ]]; then
              local windows_time
              windows_time=$(/mnt/c/Windows/System32/wbem/wmic.exe os get localdatetime /value 2>/dev/null | grep "LocalDateTime" | cut -d= -f2)
              dbg "Raw WMIC LocalDateTime: ${DOLLAR}windows_time"

              if [[ -n "${DOLLAR}windows_time" ]]; then
                local dt_raw=$(echo "${DOLLAR}windows_time" | cut -d. -f1)
                local offset=$(echo "${DOLLAR}windows_time" | grep -o '+[0-9]\+$' || true)
                dbg "dt_raw=${DOLLAR}dt_raw offset=${DOLLAR}offset"

                local year="${DOLLAR}{dt_raw:0:4}"
                local month="${DOLLAR}{dt_raw:4:2}"
                local day="${DOLLAR}{dt_raw:6:2}"
                local hour="${DOLLAR}{dt_raw:8:2}"
                local minute="${DOLLAR}{dt_raw:10:2}"
                local second="${DOLLAR}{dt_raw:12:2}"
                dbg "Parsed: ${DOLLAR}year-${DOLLAR}month-${DOLLAR}day ${DOLLAR}hour:${DOLLAR}minute:${DOLLAR}second"

                if [[ "${DOLLAR}offset" =~ ^\+[0-9]+$ ]]; then
                  mins=${DOLLAR}{offset#+}
                  hh=$((mins/60))
                  mm=$((mins%60))
                  offset=$(printf "+%02d%02d" ${DOLLAR}hh ${DOLLAR}mm)
                else
                  offset="+0900"
                fi
                dbg "Normalized offset=${DOLLAR}offset"

                local timestr="${DOLLAR}year-${DOLLAR}month-${DOLLAR}day ${DOLLAR}hour:${DOLLAR}minute:${DOLLAR}second ${DOLLAR}offset"
                dbg "Final timestr for date -d: ${DOLLAR}timestr"

                local epoch
                epoch=$(date -d "${DOLLAR}timestr" +%s 2>/dev/null || true)
                dbg "Epoch parsed from timestr: ${DOLLAR}epoch"

                if [[ -n "${DOLLAR}epoch" ]]; then
                  log "Windows 호스트 시간 기반: epoch=${DOLLAR}epoch → ${DOLLAR}(date -d @${DOLLAR}epoch)"
                  wsl_time="${DOLLAR}epoch"
                fi
              fi
            else
              dbg "wmic.exe not found"
            fi

            if [[ -z "${DOLLAR}wsl_time" ]]; then
              dbg "WMIC unavailable, fallback to current system UTC time"
              wsl_time=$(date -u +%s 2>/dev/null)
              dbg "Fallback epoch=${DOLLAR}wsl_time"
            fi

            [[ -n "${DOLLAR}wsl_time" ]] && echo "${DOLLAR}wsl_time"
          }

          choose_and_set_time() {
            local e_seed="" e_http="" e_wsl="" src=""

            dbg "Step1: probing HTTP header from registry"
            local url="https://${REGISTRY_HOST_IP}:${REGISTRY_PORT}/v2/"
            dbg "URL=${DOLLAR}url"
            for i in 1 2 3; do
              local hdr=$(curl -k -sI --connect-timeout 2 "${DOLLAR}url" 2>/dev/null | awk -F': ' '/^[Dd]ate:/ {sub(/^[Dd]ate: /,""); print; exit}') || true
              dbg "curl iteration=${DOLLAR}i hdr='${DOLLAR}hdr'"
              if [[ -n "${DOLLAR}hdr" ]]; then
                e_http=$(date -u -d "${DOLLAR}hdr" +%s 2>/dev/null || true)
                dbg "HTTP header epoch=${DOLLAR}e_http"
                [[ -n "${DOLLAR}e_http" ]] && break
              fi
              sleep 3
            done

            dbg "Step2: seed epoch file"
            local f=$( (set +e; resolve_seed_file) 2>/dev/null || true )
            [[ -n "${DOLLAR}f" ]] && dbg "Seed file=${DOLLAR}f"
            if [[ -n "${DOLLAR}f" && -f "${DOLLAR}f" ]]; then
              e_seed=$(awk -F'=' '/^EPOCH_SECONDS=/{print ${DOLLAR}2}' "${DOLLAR}f" | tr -cd '0-9' | head -n1)
              dbg "Seed epoch=${DOLLAR}e_seed"
            fi

            dbg "Step3: WSL host time"
            e_wsl=$(sync_with_wsl_host)
            dbg "WSL epoch candidate=${DOLLAR}e_wsl"

            dbg "Candidate summary: http=${DOLLAR}e_http seed=${DOLLAR}e_seed wsl=${DOLLAR}e_wsl"

            local target_epoch=""
            if [[ -n "${DOLLAR}e_http" ]]; then
              target_epoch="${DOLLAR}e_http"; src="http"
            elif [[ -n "${DOLLAR}e_seed" ]]; then
              target_epoch="${DOLLAR}e_seed"; src="seed"
            elif [[ -n "${DOLLAR}e_wsl" ]]; then
              target_epoch="${DOLLAR}e_wsl"; src="wsl"
            fi

            dbg "Selected source=${DOLLAR}src epoch=${DOLLAR}target_epoch"

            if [[ -n "${DOLLAR}target_epoch" ]]; then
              export TZ=UTC
              dbg "Set TZ=UTC"
              if command -v timedatectl >/dev/null 2>&1; then
                dbg "timedatectl set-local-rtc 0"
                timedatectl set-local-rtc 0 2>/dev/null || true
              fi
              dbg "Setting system time..."
              if date -u -s "@${DOLLAR}target_epoch"; then
                log "시간 설정 성공"
                hwclock --systohc 2>/dev/null || true
                dbg "hwclock --systohc 호출됨"
                if command -v timedatectl >/dev/null 2>&1; then
                  timedatectl set-timezone Asia/Seoul 2>/dev/null || true
                  dbg "timedatectl set-timezone Asia/Seoul"
                fi
                log "UTC now=$(date -u) local=$(date)"
                return 0
              fi
            fi

            log "시간 소스 없음"
            return 1
          }

          disable_ntp
          choose_and_set_time || log "Time sync skipped"

      # Systemd unit for time sync
      - path: /etc/systemd/system/sync-time.service
        permissions: '0644'
        content: |
          [Unit]
          Description=Sync system time with WSL registry or seed timestamp
          After=local-fs.target network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStartPre=/bin/sleep 5
          ExecStart=/usr/local/bin/sync-time.sh
          RemainAfterExit=true

          [Install]
          WantedBy=multi-user.target

      # K3s worker installation script
      - path: /usr/local/bin/setup-k3s-worker.sh
        permissions: '0755'
        content: |
          #!/bin/bash
          set -euo pipefail
          # Idempotency: skip if already completed
          if [ -f /var/lib/k3s-agent-bootstrap.done ]; then
            echo "K3s worker setup already completed, skipping."
            exit 0
          fi
          
          echo "Starting K3s worker setup..."
          
          # Set SEED_BASE directly (fixed variable assignment)
          SEED_BASE="/usr/local/seed"
          
          # Copy k3s binary
          if [ -f "$SEED_BASE/k3s" ] || ls -1 "$SEED_BASE"/k3s* >/dev/null 2>&1; then
            if [ -f "$SEED_BASE/k3s" ]; then SRC="$SEED_BASE/k3s"; else SRC=$(ls -1 "$SEED_BASE"/k3s* 2>/dev/null | head -n1); fi
            install -m 0755 "$SRC" /usr/local/bin/k3s
            echo "K3s binary copied successfully"
          else
            echo "Error: k3s binary not found in seed"
            exit 1
          fi
          
          # Copy registry configuration
          mkdir -p /etc/rancher/k3s
          if [ -f "$SEED_BASE/registries.yaml" ]; then
            install -m 0644 "$SEED_BASE/registries.yaml" /etc/rancher/k3s/registries.yaml
            echo "Registry configuration copied"
          fi
          
          # Copy CA certificate
          if [ -f "$SEED_BASE/airgap-registry-ca.crt" ]; then
            install -m 0644 "$SEED_BASE/airgap-registry-ca.crt" /usr/local/share/ca-certificates/airgap-registry-ca.crt
            echo "CA certificate copied"
            # Refresh CA trust store immediately
            update-ca-certificates || true
          fi
          
          # Wait for master API (6443) to be reachable without curl
          echo "Waiting for master API (port 6443) to be reachable..."
          for i in {1..30}; do
            if timeout 2 bash -c "echo > /dev/tcp/${MASTER_IP}/6443" 2>/dev/null; then
              echo "Master is reachable!"
              break
            fi
            echo "Waiting for master... ($i/30)"
            sleep 10
          done
          
          # Write k3s-agent config and install systemd unit for persistence
          mkdir -p /etc/rancher/k3s
          cat > /etc/rancher/k3s/config.yaml << EOF
          server: https://${MASTER_IP}:6443
          token: ${TOKEN}
          kubelet-arg:
            - "pod-infra-container-image=rancher/mirrored-pause:3.10"
          EOF

          cat > /etc/systemd/system/k3s-agent.service << 'EOF'
          [Unit]
          Description=K3s Agent
          After=network.target sync-time.service
          ConditionPathExists=/usr/local/bin/k3s

          [Service]
          Type=simple
          ExecStart=/usr/local/bin/k3s agent
          Restart=always
          RestartSec=5s
          KillMode=process
          LimitNOFILE=1048576
          TasksMax=infinity

          [Install]
          WantedBy=multi-user.target
          EOF

          systemctl daemon-reload
          systemctl enable --now k3s-agent

          # Wait for containerd socket to be ready
          echo "Waiting for containerd socket to be ready..."
          for i in {1..30}; do
            if [ -S /run/k3s/containerd/containerd.sock ]; then
              echo "containerd socket is ready!"
              break
            fi
            echo "Waiting for containerd socket... ($i/30)"
            sleep 2
          done

          # Load airgap images AFTER starting k3s-agent (containerd is ready)
          if [ -f "$SEED_BASE/k3s-airgap-images-amd64.tar.gz" ]; then
            echo "Loading airgap images after k3s-agent startup..."
            echo "Image file size: $(du -h "$SEED_BASE/k3s-airgap-images-amd64.tar.gz" | cut -f1)"

            # Wait a bit more for k3s to fully initialize
            sleep 5

            # Prepare log and fallback copy to k3s agent images autoload dir
            LOG_FILE="/var/log/k3s-image-import.log"
            echo "[$(date -u)] Begin image import" | tee -a "$LOG_FILE"
            mkdir -p /var/lib/rancher/k3s/agent/images
            cp -f "$SEED_BASE/k3s-airgap-images-amd64.tar.gz" \
              /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.gz 2>/dev/null || true

            # Try multiple import strategies (namespace, gzip pipe)
            if /usr/local/bin/k3s ctr -n k8s.io images import "$SEED_BASE/k3s-airgap-images-amd64.tar.gz" 2>&1 | tee -a "$LOG_FILE"; then
              echo "SUCCESS: Imported with k8s.io namespace" | tee -a "$LOG_FILE"
            elif /usr/local/bin/k3s ctr images import "$SEED_BASE/k3s-airgap-images-amd64.tar.gz" 2>&1 | tee -a "$LOG_FILE"; then
              echo "SUCCESS: Imported without explicit namespace" | tee -a "$LOG_FILE"
            elif gunzip -c "$SEED_BASE/k3s-airgap-images-amd64.tar.gz" | /usr/local/bin/k3s ctr -n k8s.io images import - 2>&1 | tee -a "$LOG_FILE"; then
              echo "SUCCESS: Imported via gunzip pipe" | tee -a "$LOG_FILE"
            else
              echo "ERROR: Failed to import airgap images via all strategies" | tee -a "$LOG_FILE"
            fi

            # Verify images were loaded
            image_count=$(/usr/local/bin/k3s ctr -n k8s.io images ls -q | wc -l)
            echo "Loaded $image_count container images (k8s.io namespace)" | tee -a "$LOG_FILE"
            echo "Critical images check:" | tee -a "$LOG_FILE"
            /usr/local/bin/k3s ctr -n k8s.io images ls | grep -E "(pause|coredns|traefik)" \
              | tee -a "$LOG_FILE" || echo "No critical images found" | tee -a "$LOG_FILE"
          else
            echo "WARNING: Airgap images not found at $SEED_BASE/k3s-airgap-images-amd64.tar.gz"
            echo "This will cause all pods to fail with ContainerCreating status"
            echo "Available files in seed directory:"
            ls -la "$SEED_BASE/" || echo "Cannot list seed directory"
            echo "Continuing without pre-loaded images - images must be available via registry"
          fi

          # Eject CD-ROM once to avoid boot loop (safe after seed copied)
          cat > /usr/local/bin/eject-if-safe.sh << 'EOF'
          #!/bin/sh
          set -eu
          if [ -d /usr/local/seed ] && [ "$(ls -A /usr/local/seed 2>/dev/null | wc -l)" -gt 0 ]; then
            if command -v eject >/dev/null 2>&1; then
              eject -r /dev/cdrom 2>/dev/null || eject -r /dev/sr0 2>/dev/null || true
            fi
          fi
          EOF
          chmod 0755 /usr/local/bin/eject-if-safe.sh

          cat > /etc/systemd/system/eject-cdrom.service << 'EOF'
          [Unit]
          Description=Eject CD-ROM once after install (safe)
          After=k3s-agent.service local-fs.target
          ConditionPathIsDirectory=/usr/local/seed

          [Service]
          Type=oneshot
          ExecStart=/usr/local/bin/eject-if-safe.sh

          [Install]
          WantedBy=multi-user.target
          EOF
          systemctl enable --now eject-cdrom.service || true

          # Wait for agent to join
          echo "Waiting for agent to join cluster..."
          for i in {1..30}; do
            if /usr/local/bin/k3s kubectl get nodes >/dev/null 2>&1; then
              break
            fi
            echo "Waiting... ($i/30)"
            sleep 10
          done
          
          # Cleanup
          umount /tmp/seed 2>/dev/null || true
          
          echo "K3s worker setup completed!"
          mkdir -p /var/lib
          touch /var/lib/k3s-agent-bootstrap.done

    runcmd:
      # Cloud-init 완료 표시 파일 생성 (idempotency 보장)
      - [ bash, -c, "echo 'Cloud-init completed at $(date)' > /var/lib/cloud-init-complete" ]

      # 타임존을 먼저 설정 (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/timezone-set ]; then timedatectl set-timezone Asia/Seoul && timedatectl set-local-rtc 0 && echo 'Timezone set' > /var/lib/timezone-set; fi" ]
     
      # ISO 복사 보강 마커 (seed 존재 시 보완 생성)
      - [ bash, -c, "if [ -d /usr/local/seed ] && [ ! -f /var/lib/iso-copy-complete ]; then echo 'ISO copy verified at $(date)' > /var/lib/iso-copy-complete; fi" ]
      
      # 시간 동기화 실행 (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/sync-time-enabled ]; then systemctl enable sync-time.service && systemctl start sync-time.service && echo 'Sync-time enabled' > /var/lib/sync-time-enabled; fi" ]
      
      # Update CA certificates (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/ca-certificates-updated ]; then update-ca-certificates && echo 'CA certificates updated' > /var/lib/ca-certificates-updated; fi" ]

      # Disable swap (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/swap-disabled ]; then swapoff -a && systemctl enable disable-swap.service && systemctl start disable-swap.service && echo 'Swap disabled' > /var/lib/swap-disabled; fi" ]

      # Apply sysctl settings (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/sysctl-applied ]; then sysctl --system && echo 'Sysctl applied' > /var/lib/sysctl-applied; fi" ]

      # Hostname은 identity에서 설정됨

      # Load kernel modules (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/kernel-modules-loaded ]; then modprobe overlay && modprobe br_netfilter && echo 'Kernel modules loaded' > /var/lib/kernel-modules-loaded; fi" ]

      # Run worker bootstrap only if not already completed (idempotency)
      - [ bash, -c, "if [ ! -f /var/lib/k3s-agent-bootstrap.done ]; then systemctl daemon-reload && sed -i 's/\\r$//' /usr/local/bin/setup-k3s-worker.sh /etc/systemd/system/k3s-agent-bootstrap.service 2>/dev/null || true && systemctl enable k3s-agent-bootstrap.service && systemctl start k3s-agent-bootstrap.service; else echo 'K3s agent bootstrap already completed, skipping'; fi" ]

      # Apply auto-login overrides (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/autologin-configured ]; then systemctl restart getty@tty1.service && systemctl restart serial-getty@ttyS0.service && echo 'Auto-login configured' > /var/lib/autologin-configured; fi" ]

      # Create kubectl alias (한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/kubectl-alias-created ]; then echo 'alias kubectl=\"k3s kubectl\"' >> /home/ubuntu/.bashrc && echo 'Kubectl alias created' > /var/lib/kubectl-alias-created; fi" ]

      # K8s 운영 패키지 설치 서비스 활성화 및 실행 (순차적 실행)
      - [ bash, -c, "systemctl daemon-reload && systemctl enable k8s-ops-packages.service && systemctl start k8s-ops-packages.service" ]
      
      # 설치된 패키지 확인 및 로그 생성
      - [ bash, -c, "echo '=== Installed K8s Operations Packages ===' > /var/log/k8s-ops-packages.log && dpkg -l | grep -E '(jq|htop|ethtool|iproute2|dnsutils|telnet|psmisc|sysstat|iftop|iotop|dstat|yq)' >> /var/log/k8s-ops-packages.log 2>&1 || echo 'No packages found' >> /var/log/k8s-ops-packages.log" ]
      
      # 설치 완료 마커 파일 생성 (최종 확인)
      - [ bash, -c, "echo '$(date): All K8s operations packages installation completed successfully' > /var/lib/k8s-ops-installation-complete" ]

      # SSH 서비스 재시작 (보안 설정 적용, 한 번만 실행)
      - [ bash, -c, "if [ ! -f /var/lib/ssh-restarted ]; then systemctl restart ssh && echo 'SSH restarted' > /var/lib/ssh-restarted; fi" ]

    final_message: "K3s worker node setup completed in airgap environment with autoinstall!"