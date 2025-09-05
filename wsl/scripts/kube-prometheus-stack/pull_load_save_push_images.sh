#!/bin/bash
set -euo pipefail

INPUT_FILE=""
LOCAL_REG=""
OUT_DIR="./image-archive"
RETRIES=3
FORCE=0
NO_PUSH=0
PUSH_ONLY=0
PLATFORM="linux/amd64"
DEST_TLS_VERIFY=1   # 0이면 --dest-tls-verify=false 추가

usage() {
  cat <<EOF
Usage: $(basename "$0") -i images.txt -r <local-registry[:port]> [options]
  -i, --input       이미지 목록 파일
  -r, --registry    로컬 레지스트리 (예: gaiderunner.ai:5000)
  -o, --out-dir     tar 저장 디렉터리 (기본: ./image-archive)
      --platform    docker pull 플랫폼 (기본: linux/amd64)
      --retries     재시도 횟수 (기본: 3)
      --force       기존 산출물 있어도 다시 수행
      --no-push     push 생략
      --push-only   pull/save 생략, push만 수행
      --dest-tls-verify 0|1 (기본 1)
환경변수(선택): DEST_USER, DEST_PASS (skopeo용 자격증명 강제 지정)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input) INPUT_FILE="$2"; shift 2;;
    -r|--registry) LOCAL_REG="$2"; shift 2;;
    -o|--out-dir) OUT_DIR="$2"; shift 2;;
    --retries) RETRIES="${2:-3}"; shift 2;;
    --force) FORCE=1; shift;;
    --no-push) NO_PUSH=1; shift;;
    --push-only) PUSH_ONLY=1; shift;;
    --platform) PLATFORM="${2:-linux/amd64}"; shift 2;;
    --dest-tls-verify) DEST_TLS_VERIFY="${2:-1}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 1;;
  esac
done

[[ -z "${INPUT_FILE}" || -z "${LOCAL_REG}" ]] && { usage; exit 1; }
[[ -f "${INPUT_FILE}" ]] || { echo "입력 파일 없음: ${INPUT_FILE}"; exit 1; }
mkdir -p "${OUT_DIR}"

retry() { local n=0; local max=${RETRIES}; until "$@"; do n=$((n+1)); [[ $n -ge $max ]] && return 1; echo "  ↻ 재시도($n/$max)"; sleep $((2*n)); done; }
trim() { awk '{$1=$1;print}' <<< "$*"; }

digest_to_tag() {
  local img="$1"
  if [[ "$img" == *"@sha256:"* ]]; then
    local base="${img%@sha256:*}"
    local digest="${img#*@sha256:}"
    echo "${base}:d-${digest:0:12}"
  else
    echo "$img"
  fi
}

make_dst() {
  local src="$1"
  if [[ "$src" == "${LOCAL_REG}/"* ]]; then echo "$src"; else echo "${LOCAL_REG}/${src#docker.io/}"; fi
}
make_src() {
  local img="$1"
  if [[ "$img" == "${LOCAL_REG}/"* ]]; then echo "${img#${LOCAL_REG}/}"; else echo "$img"; fi
}
fname_of() { echo "$1" | sed 's|/|-|g; s|:|__|g; s|@|__|g'; }

# skopeo 옵션 빌드
skopeo_tls_flag=()
[[ "${DEST_TLS_VERIFY}" -eq 0 ]] && skopeo_tls_flag+=(--dest-tls-verify=false)
skopeo_auth_flag=()
if [[ -n "${DEST_USER:-}" && -n "${DEST_PASS:-}" ]]; then
  skopeo_auth_flag+=(--dest-creds "${DEST_USER}:${DEST_PASS}")
fi

total=0 pulled=0 saved=0 pushed=0 skipped=0 failed=0

while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="$(trim "$raw")"
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  total=$((total+1))

  norm="$(digest_to_tag "$line")"
  SRC="$(make_src "$norm")"
  DST="$(make_dst "$norm")"

  [[ "$SRC" != *:* && "$SRC" != *"@sha256:"* ]] && SRC="${SRC}:latest"
  [[ "$DST" != *:* && "$DST" != *"@sha256:"* ]] && DST="${DST}:latest"

  TAR="${OUT_DIR}/$(fname_of "$DST").tar"
  echo "=== [${total}] SRC='${SRC}' → DST='${DST}' (platform=${PLATFORM})"

  if [[ "${PUSH_ONLY}" -eq 0 ]]; then
    if [[ "${FORCE}" -eq 1 || ! $(docker image inspect "${SRC}" >/dev/null 2>&1; echo $?) -eq 0 ]]; then
      echo "  • pull (--platform=${PLATFORM})"
      retry docker pull --platform="${PLATFORM}" "${SRC}" || { echo "  ✗ pull 실패"; failed=$((failed+1)); continue; }
      pulled=$((pulled+1))
    else
      echo "  • pull 스킵(존재)"
      skipped=$((skipped+1))
    fi

    ID="$(docker image inspect --format '{{.Id}}' "${SRC}")" || { echo "  ✗ 이미지 ID 조회 실패"; failed=$((failed+1)); continue; }
    if [[ "${FORCE}" -eq 1 || ! $(docker image inspect "${DST}" >/dev/null 2>&1; echo $?) -eq 0 ]]; then
      echo "  • tag(ID→DST): ${ID} → ${DST}"
      docker tag "${ID}" "${DST}"
    else
      echo "  • tag 스킵(존재)"
    fi

    if [[ "${FORCE}" -eq 1 || ! -f "${TAR}" ]]; then
      echo "  • save → ${TAR}"
      docker save -o "${TAR}.tmp" "${DST}" && mv -f "${TAR}.tmp" "${TAR}"
      saved=$((saved+1))
    else
      echo "  • save 스킵(존재)"
      skipped=$((skipped+1))
    fi
  fi

  if [[ "${NO_PUSH}" -eq 1 ]]; then
    echo "  • push 스킵"
    continue
  fi

  echo "  • push(docker) → ${DST}"
  if retry docker push "${DST}"; then
    pushed=$((pushed+1))
    continue
  fi

  echo "  ! docker push 실패 → skopeo로 재시도"
  if command -v skopeo >/dev/null 2>&1; then
    if [[ -f "${TAR}" ]]; then
      retry skopeo copy "docker-archive:${TAR}" "docker://${DST}" \
        --override-os linux --override-arch amd64 \
        "${skopeo_tls_flag[@]}" "${skopeo_auth_flag[@]}" \
      && { pushed=$((pushed+1)); continue; }
    else
      retry skopeo copy "docker-daemon:${DST}" "docker://${DST}" \
        --override-os linux --override-arch amd64 \
        "${skopeo_tls_flag[@]}" "${skopeo_auth_flag[@]}" \
      && { pushed=$((pushed+1)); continue; }
    fi
  else
    echo "  ! skopeo 미설치"
  fi

  echo "  ✗ push 최종 실패: ${DST}"
  failed=$((failed+1))
done < "${INPUT_FILE}"

echo
echo "===== 요약 ====="
echo "총 항목        : ${total}"
echo "pull 성공      : ${pulled}"
echo "save(tar) 성공 : ${saved}"
echo "push 성공      : ${pushed}"
echo "스킵           : ${skipped}"
echo "실패           : ${failed}"
[[ ${failed} -gt 0 ]] && exit 1 || exit 0

