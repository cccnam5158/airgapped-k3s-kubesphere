#!/bin/bash
set -euo pipefail

# VM과 WSL 간의 시간 차이 진단 및 수정 스크립트
# 한국 표준시(KST) 설정을 보장합니다.

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# 현재 시간 정보 출력
show_time_info() {
    log "=== 현재 시간 정보 ==="
    log "시스템 시간: $(date)"
    log "UTC 시간: $(date -u)"
    log "타임존: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'unknown')"
    log "하드웨어 클록: $(hwclock --show 2>/dev/null || echo 'unavailable')"
    log "RTC 로컬: $(timedatectl show --property=RTCInLocalTZ --value 2>/dev/null || echo 'unknown')"
}

# NTP 서비스 비활성화
disable_ntp() {
    log "NTP 서비스 비활성화 중..."
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-ntp false 2>/dev/null || true
    fi
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        systemctl stop systemd-timesyncd 2>/dev/null || true
        systemctl disable systemd-timesyncd 2>/dev/null || true
    fi
}

# 타임존을 KST로 설정
set_timezone_kst() {
    log "타임존을 Asia/Seoul로 설정 중..."
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone Asia/Seoul 2>/dev/null || {
            error "timedatectl로 타임존 설정 실패, 수동 설정 시도"
            echo "Asia/Seoul" > /etc/timezone 2>/dev/null || true
            ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime 2>/dev/null || true
        }
    else
        echo "Asia/Seoul" > /etc/timezone 2>/dev/null || true
        ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime 2>/dev/null || true
    fi
}

# 하드웨어 클록을 UTC로 설정
set_hwclock_utc() {
    log "하드웨어 클록을 UTC로 설정 중..."
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-local-rtc 0 2>/dev/null || true
    fi
}

# WSL에서 시간 가져오기 (WSL 호스트와 동기화)
sync_with_wsl_host() {
    log "WSL 호스트와 시간 동기화 시도 중..."
    
    # WSL 호스트의 시간을 가져오는 방법들
    local wsl_time=""
    
    # 방법 1: /proc/uptime을 통한 부팅 시간 계산
    if [[ -f /proc/uptime ]]; then
        local uptime_seconds
        uptime_seconds=$(awk '{print $1}' /proc/uptime 2>/dev/null | cut -d. -f1)
        if [[ -n "$uptime_seconds" && "$uptime_seconds" -gt 0 ]]; then
            local current_time
            current_time=$(date -u +%s)
            local boot_time=$((current_time - uptime_seconds))
            log "부팅 시간 기반 계산: $boot_time"
            wsl_time="$boot_time"
        fi
    fi
    
    # 방법 2: Windows 호스트 시간 (WSL2에서 사용 가능)
    if [[ -z "$wsl_time" && -f /mnt/c/Windows/System32/wbem/wmic.exe ]]; then
        local windows_time
        windows_time=$(/mnt/c/Windows/System32/wbem/wmic.exe os get localdatetime /value 2>/dev/null | grep "LocalDateTime" | cut -d= -f2)
        if [[ -n "$windows_time" ]]; then
            # Windows 시간 형식: YYYYMMDDHHMMSS.mmmmmm+xxx
            local year="${windows_time:0:4}"
            local month="${windows_time:4:2}"
            local day="${windows_time:6:2}"
            local hour="${windows_time:8:2}"
            local minute="${windows_time:10:2}"
            local second="${windows_time:12:2}"
            
            if [[ "$year" =~ ^[0-9]{4}$ && "$month" =~ ^[0-9]{2}$ ]]; then
                local epoch
                epoch=$(date -u -d "$year-$month-$day $hour:$minute:$second" +%s 2>/dev/null)
                if [[ -n "$epoch" ]]; then
                    log "Windows 호스트 시간 기반: $epoch"
                    wsl_time="$epoch"
                fi
            fi
        fi
    fi
    
    echo "$wsl_time"
}

# 시간 설정
set_system_time() {
    local target_epoch="$1"
    local source="$2"
    
    if [[ -z "$target_epoch" ]]; then
        error "유효한 시간 소스가 없습니다"
        return 1
    fi
    
    log "시간을 ${source}에서 설정 중: $target_epoch"
    
    # UTC로 시간 설정
    export TZ=UTC
    
    # 시스템 시간 설정
    if date -u -s "@${target_epoch}" >/dev/null 2>&1; then
        log "시스템 시간 설정 성공"
    elif hwclock --set --date="$(date -u -d "@${target_epoch}" '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1; then
        log "하드웨어 클록으로 시간 설정"
        hwclock --hctosys
    else
        error "시간 설정 실패"
        return 1
    fi
    
    # 하드웨어 클록 동기화
    hwclock --systohc 2>/dev/null || true
    
    # 타임존 다시 설정
    set_timezone_kst
    
    # 검증
    local now_epoch
    now_epoch=$(date -u +%s)
    if [[ -z "$now_epoch" || "$now_epoch" -lt $((target_epoch-120)) || "$now_epoch" -gt $((target_epoch+120)) ]]; then
        error "시간 검증 실패: now=$now_epoch, expected~=$target_epoch"
        return 1
    fi
    
    log "시간 설정 완료: UTC=$(date -u), KST=$(date)"
    return 0
}

# 메인 실행
main() {
    log "=== VM/WSL 시간 동기화 진단 시작 ==="
    
    show_time_info
    
    # NTP 비활성화
    disable_ntp
    
    # 타임존 설정
    set_timezone_kst
    
    # 하드웨어 클록 UTC 설정
    set_hwclock_utc
    
    # 시간 소스 결정
    local target_epoch=""
    local source=""
    
    # 1. WSL 호스트 시간 시도
    local wsl_epoch
    wsl_epoch=$(sync_with_wsl_host)
    if [[ -n "$wsl_epoch" ]]; then
        target_epoch="$wsl_epoch"
        source="WSL 호스트"
    fi
    
    # 2. 기존 sync-time.sh 스크립트의 소스들 시도
    if [[ -z "$target_epoch" ]]; then
        log "기존 시간 동기화 소스 확인 중..."
        
        # HTTP Date 헤더 시도
        local registry_host="${REGISTRY_HOST_IP:-192.168.6.1}"
        local registry_port="${REGISTRY_PORT:-5000}"
        local url="https://${registry_host}:${registry_port}/v2/"
        
        for i in 1 2 3; do
            local date_hdr
            date_hdr=$(curl -k -sI --connect-timeout 2 "$url" 2>/dev/null | awk -F': ' '/^[Dd]ate:/ {sub(/^[Dd]ate: /,""); print; exit}') || true
            
            if [[ -n "${date_hdr:-}" ]]; then
                local epoch
                epoch=$(date -u -d "$date_hdr" +%s 2>/dev/null)
                if [[ -n "$epoch" ]]; then
                    target_epoch="$epoch"
                    source="HTTP Date 헤더"
                    break
                fi
            fi
            sleep 2
        done
        
        # Seed 파일 시도
        if [[ -z "$target_epoch" ]]; then
            local seed_files=(
                "/usr/local/seed/build-timestamp"
                "/cdrom/files/build-timestamp"
                "/cdrom/build-timestamp"
                "/mnt/cdrom/files/build-timestamp"
                "/mnt/cdrom/build-timestamp"
            )
            
            for seed_file in "${seed_files[@]}"; do
                if [[ -f "$seed_file" ]]; then
                    local epoch
                    epoch=$(awk -F'=' '/^EPOCH_SECONDS=/{print $2}' "$seed_file" | head -n1 | tr -d '\r' | tr -cd '0-9')
                    if [[ -n "$epoch" ]]; then
                        target_epoch="$epoch"
                        source="Seed 파일 ($seed_file)"
                        break
                    fi
                fi
            done
        fi
    fi
    
    # 시간 설정
    if set_system_time "$target_epoch" "$source"; then
        log "=== 시간 동기화 완료 ==="
        show_time_info
        exit 0
    else
        error "시간 동기화 실패"
        log "=== 현재 시간 정보 (동기화 실패) ==="
        show_time_info
        exit 1
    fi
}

# 스크립트 실행
main "$@"


