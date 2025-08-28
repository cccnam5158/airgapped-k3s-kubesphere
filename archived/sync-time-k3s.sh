#!/bin/bash
# sync-time-k3s-kst.sh
set -euo pipefail

# ===== 사용자 설정 =====
NODES=("192.168.6.10" "192.168.6.11" "192.168.6.12")
USER="ubuntu"
PASS="ubuntu"
SSH_KEY="${HOME}/.ssh/airgap_k3s"

# ===== 유틸: known_hosts 정리 및 최신 host key 등록 =====
ensure_known_host() {
  local host="$1"
  # 기존 key 제거 (경고 메시지에서 제안된 명령을 자동화)
  ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${host}" >/dev/null 2>&1 || true
  # 최신 host key 수집
  ssh-keyscan -H "${host}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
}

# ===== 0) WSL 호스트 시간 (참고 출력용) =====
HOST_TIME="$(date +"%Y-%m-%d %H:%M:%S %Z")"
echo ">>> WSL 호스트 시간: ${HOST_TIME}"

# ===== 1) 각 노드 처리 =====
for NODE in "${NODES[@]}"; do
  echo ">>> [${NODE}] known_hosts 갱신 중..."
  ensure_known_host "${NODE}"

  echo ">>> [${NODE}] KST 타임존 설정 및 시계 동기화 시작..."
  # 주의: heredoc은 로컬 변수 확장을 위해 쌍따옴표 EOF 사용
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=yes "${USER}@${NODE}" "bash -s" <<EOF
    set -e

    echo "[1/6] 타임존을 Asia/Seoul로 설정"
    echo "${PASS}" | sudo -S timedatectl set-timezone Asia/Seoul

    echo "[2/6] WSL 시간(로컬)로 시스템 시간 강제 동기화 (선택)"
    # 필요 시 주석 해제 (이미 NTP 사용 중이면 생략 가능)
    # echo "${PASS}" | sudo -S date -s "$(date +"%Y-%m-%d %H:%M:%S")"

    echo "[3/6] NTP 활성화 및 재시작 (systemd-timesyncd)"
    echo "${PASS}" | sudo -S timedatectl set-ntp true || true
    echo "${PASS}" | sudo -S systemctl restart systemd-timesyncd
    echo "${PASS}" | sudo -S systemctl enable systemd-timesyncd --now

    echo "[4/6] RTC(Local RTC 모드) 설정 (재부팅 후 유지 목적)"
    # 운영 표준은 RTC=UTC 권장이지만, Airgap/VM 꼬임 방지를 위해 로컬 TZ 사용을 원하시면 1로 설정
    # 로컬 TZ 사용:
    echo "${PASS}" | sudo -S timedatectl set-local-rtc 1

    echo "[5/6] HW clock을 현재 시스템 시간으로 저장"
    echo "${PASS}" | sudo -S hwclock --systohc

    echo "[6/6] 현재 상태 출력"
    timedatectl status | grep -E "Local time|Time zone|RTC in local TZ|System clock synchronized|NTP service"
    echo "date: \$(date)"
EOF

  echo ">>> [${NODE}] 완료 ✅"
  echo
done

echo "모든 노드에 KST 적용 및 시계 동기화가 완료되었습니다."
echo "필요 시: 각 노드에서 'sudo systemctl restart k3s' 후 'kubectl get nodes' 확인을 권장합니다."
