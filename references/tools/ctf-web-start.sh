#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0 2>/dev/null || true

usage() {
  cat <<'EOF'
사용법: ctf-web [옵션] 문제이름

실행 모드:
  (기본값)       짧은 Web Fast Probe 후 필요할 때만 Deep으로 전환
  --fast-only    기본적인 소스·라우트·상태 분석까지만 수행
  --deep         처음부터 전체 P0~P6 검증을 수행

옵션:
  --source DIR      문제 폴더 또는 ZIP이 들어 있는 원본 디렉터리
  --port PORT       Dockerfile에 EXPOSE가 없을 때 사용할 컨테이너 포트
  --keep-docker     종료 후 Web 컨테이너·Compose 프로젝트를 보존
  --keep-workspace  완료 후에도 중복 입력 파일을 보존
  --prepare-only    문제 파일만 준비하고 서비스와 Codex는 실행하지 않음
  --dry-run         경로·런타임 우선순위·Codex 프롬프트만 표시
  -h, --help        도움말

런타임 우선순위:
  1. compose.yaml / compose.yml / docker-compose.yml / docker-compose.yaml
  2. Dockerfile
  3. 둘 다 없으면 STATIC-ONLY 소스 분석

환경 변수:
  CTF_WEB_SOURCE       기본 Web 문제 원본 디렉터리
  CTF_AGENT_ROOT       설치된 ctf-agent 루트
  CTF_MIN_HOST_FREE_MB Windows 호스트 최소 여유 공간(MiB, 기본 4096)
  CODEX_BIN            Codex CLI 경로
  CTF_CODEX_MODEL      문제 풀이 모델(기본 gpt-5.6-sol)
  CTF_CODEX_REASONING_EFFORT 추론 강도(기본 Adaptive/Fast=high, Deep=ultra)
  CTF_CODEX_SERVICE_TIER 서비스 티어(기본 fast)
EOF
}

action=launch
solve_mode=adaptive
keep_docker=false
keep_workspace=false
source_root=${CTF_WEB_SOURCE:-$HOME/ctf-challenges/web}
container_port=
challenge_name=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo '--source 경로가 필요합니다.' >&2; exit 64; }
      source_root=$2
      shift 2
      continue
      ;;
    --port)
      [[ $# -ge 2 ]] || { echo '--port 값이 필요합니다.' >&2; exit 64; }
      container_port=$2
      shift 2
      continue
      ;;
    --fast-only) solve_mode=fast-only ;;
    --deep) solve_mode=deep ;;
    --keep-docker) keep_docker=true ;;
    --keep-workspace) keep_workspace=true ;;
    --prepare-only) action=prepare-only ;;
    --dry-run) action=dry-run ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 64 ;;
    *)
      [[ -z "$challenge_name" ]] || { echo '문제 이름은 하나만 지정할 수 있습니다.' >&2; exit 64; }
      challenge_name=$1
      ;;
  esac
  shift
done

[[ -n "$challenge_name" ]] || { usage >&2; exit 64; }
if [[ ! "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$challenge_name" == . || "$challenge_name" == .. ]]; then
  printf '잘못된 문제 이름입니다: %s\n' "$challenge_name" >&2
  exit 65
fi
if [[ -n "$container_port" ]]; then
  [[ "$container_port" =~ ^[0-9]+$ ]] && (( container_port >= 1 && container_port <= 65535 )) || {
    printf '포트는 1~65535 범위여야 합니다: %s\n' "$container_port" >&2
    exit 65
  }
fi

agent_root=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
source_dir="$source_root/$challenge_name"
source_zip="$source_root/$challenge_name.zip"
challenge_dir="$agent_root/challenges/$challenge_name"
input_dir="$challenge_dir/input"
work_dir="$challenge_dir/work"
scope_dir="$challenge_dir/scope"
evidence_dir="$challenge_dir/evidence/private"
tools_dir="$agent_root/references/tools"
runtime_tool="$tools_dir/web-runtime.sh"
runtime_state="$work_dir/web-runtime.env"
codex_bin=${CODEX_BIN:-}
codex_model=${CTF_CODEX_MODEL:-gpt-5.6-sol}
if [[ -n ${CTF_CODEX_REASONING_EFFORT:-} ]]; then
  codex_reasoning_effort=$CTF_CODEX_REASONING_EFFORT
elif [[ "$solve_mode" == deep ]]; then
  codex_reasoning_effort=ultra
else
  codex_reasoning_effort=high
fi
codex_service_tier=${CTF_CODEX_SERVICE_TIER:-fast}
image_slug=$(printf '%s' "$challenge_name" | tr '[:upper:]_.' '[:lower:]--')
image_name="ctf-web-$image_slug:local"
project_name="ctf_web_${image_slug//-/_}"

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 없습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -x "$runtime_tool" ]] || { printf 'Web runtime 도구가 없습니다: %s\n' "$runtime_tool" >&2; exit 66; }
[[ -f "$tools_dir/web-solve-template.py" ]] || { echo 'Web solver 템플릿이 없습니다.' >&2; exit 66; }
[[ -d "$source_dir" || -f "$source_zip" ]] || {
  printf '문제를 찾을 수 없습니다:\n  %s\n  %s\n' "$source_dir" "$source_zip" >&2
  exit 67
}
[[ "$codex_reasoning_effort" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] || { echo '잘못된 추론 강도입니다.' >&2; exit 65; }
[[ "$codex_service_tier" =~ ^[A-Za-z0-9._-]+$ ]] || { echo '잘못된 서비스 티어입니다.' >&2; exit 65; }

detect_runtime_from_dir() {
  local root=$1 candidate=
  for candidate in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
    [[ ! -f "$root/$candidate" ]] || { printf 'compose:%s\n' "$candidate"; return 0; }
  done
  [[ ! -f "$root/Dockerfile" ]] || { printf 'dockerfile:Dockerfile\n'; return 0; }
  printf 'static-only:none\n'
}

if [[ -d "$source_dir" ]]; then
  runtime_detection=$(detect_runtime_from_dir "$source_dir")
else
  archive_entries=$(unzip -Z1 -- "$source_zip" 2>/dev/null || true)
  runtime_detection=static-only:none
  for candidate in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
    if grep -Eq "(^|/)$candidate$" <<< "$archive_entries"; then
      runtime_detection="compose:$candidate"
      break
    fi
  done
  if [[ "$runtime_detection" == static-only:none ]] && grep -Eq '(^|/)Dockerfile$' <<< "$archive_entries"; then
    runtime_detection=dockerfile:Dockerfile
  fi
fi
runtime_mode=${runtime_detection%%:*}
runtime_file=${runtime_detection#*:}

case "$solve_mode" in
  adaptive) mode_text='소스와 실행 환경을 먼저 보고 가장 싼 세 가설만 시험하라. 다중 역할·복잡한 상태·두 가설 실패·환경 불일치가 생길 때만 기존 결과를 유지한 채 Deep으로 전환하라.' ;;
  fast-only) mode_text='소스 중심 Fast Probe만 수행하라. 라우트·신뢰 경계·세션 상태를 좁게 매핑하고 미해결이면 다음 최저 비용 검증만 보고하라.' ;;
  deep) mode_text='P0~P6 전체 절차를 수행하되 이미 확인한 라우트와 가설을 반복하지 말고 clean-state 재현까지 완료하라.' ;;
esac

prompt=$(cat <<EOF
\$ctf-web

허가된 로컬 Web CTF 문제 '$challenge_name'을 즉시 풀어라.
- 입력: challenges/$challenge_name/input (수정 금지)
- 실행: mode=$solve_mode, runtime=$runtime_mode, file=$runtime_file
- 시작: 런처가 Compose를 Dockerfile보다 우선해 이미 빌드·실행했다. work/web-runtime.env를 가장 먼저 읽고 기록된 loopback origin만 사용하라.
- 분석: $mode_text 소스에서 라우트, 인증·인가, 세션, parser와 sink를 먼저 좁힌 후 baseline, 단일 mutation, negative control 순서로 검증하라.
- 결과: 준비된 work/solve.py를 최소 재현 코드로 수정하고 간결한 work/writeup.md만 남겨라. 실제 플래그를 재현하면 즉시 FLAG=<값>을 출력하고 work/.solved에 verified를 기록하라.
- 제한: 한국어로 진행하고 웹 검색·write-up 조회·외부 origin·광범위 스캔·무제한 brute force·DoS·플래그 자동 제출을 금지한다. HTTP 요청은 기록된 localhost origin에만 보낸다.
EOF
)

if [[ "$runtime_mode" == static-only ]]; then
  prompt+=$'\n- 런타임: Compose와 Dockerfile이 없으므로 호스트에서 서버를 실행하지 말고 소스 분석을 계속하라. 동적 검증이 꼭 필요하면 work/에 최소 Dockerfile을 만든 뒤 정확한 필요 조건을 보고하라.'
fi

if [[ "$action" == dry-run ]]; then
  printf '원본 폴더:       %s\n' "$source_dir"
  printf '원본 ZIP:        %s\n' "$source_zip"
  printf '작업 경로:       %s\n' "$challenge_dir"
  printf '풀이 모드:       %s\n' "$solve_mode"
  printf '런타임 우선 결과: %s (%s)\n' "$runtime_mode" "$runtime_file"
  printf 'Docker 이미지:   %s\n' "$image_name"
  printf 'Compose 프로젝트: %s\n' "$project_name"
  printf '컨테이너 포트:   %s\n' "${container_port:-Docker 설정에서 자동 감지}"
  printf 'Codex 모델:      %s\n' "$codex_model"
  printf '추론 강도:       %s\n' "$codex_reasoning_effort"
  printf '서비스 티어:     %s (fast mode)\n' "$codex_service_tier"
  printf '웹 검색:         비활성\n'
  printf '상태 감시 경고:  비활성\n'
  printf '\nCodex 프롬프트:\n%s\n' "$prompt"
  exit 0
fi

min_host_free_mb=${CTF_MIN_HOST_FREE_MB:-4096}
[[ "$min_host_free_mb" =~ ^[0-9]+$ ]] || { echo 'CTF_MIN_HOST_FREE_MB는 0 이상의 정수여야 합니다.' >&2; exit 65; }
if [[ -d /mnt/c && "$min_host_free_mb" -gt 0 ]]; then
  host_free_kb=$(df -Pk /mnt/c | awk 'NR==2 {print $4}')
  if [[ "$host_free_kb" =~ ^[0-9]+$ ]] && (( host_free_kb < min_host_free_mb * 1024 )); then
    printf 'Windows 여유 공간이 %s MiB 미만이어서 중단합니다.\n' "$min_host_free_mb" >&2
    exit 72
  fi
fi

mkdir -p "$input_dir" "$work_dir" "$scope_dir" "$evidence_dir"
printf 'web\n' > "$challenge_dir/.ctf-category"
if [[ -d "$source_dir" ]]; then
  printf '%s\n' "$source_dir" > "$scope_dir/source-path.txt"
  cp -a --update=none -- "$source_dir"/. "$input_dir"/
else
  command -v unzip >/dev/null 2>&1 || { echo 'ZIP 문제 준비에는 unzip이 필요합니다.' >&2; exit 69; }
  printf '%s\n' "$source_zip" > "$scope_dir/source-path.txt"
  python3 - "$source_zip" "$input_dir" <<'PY'
import os, stat, sys, zipfile

archive, destination = sys.argv[1:]
root = os.path.realpath(destination)
with zipfile.ZipFile(archive) as bundle:
    for item in bundle.infolist():
        name = item.filename.replace("\\", "/")
        target = os.path.realpath(os.path.join(root, name))
        mode = (item.external_attr >> 16) & 0xFFFF
        if name.startswith("/") or os.path.commonpath([root, target]) != root or stat.S_ISLNK(mode):
            raise SystemExit(f"unsafe ZIP entry: {name}")
    bundle.extractall(root)
PY
fi

runtime_detection=$(detect_runtime_from_dir "$input_dir")
runtime_mode=${runtime_detection%%:*}
runtime_file=${runtime_detection#*:}
printf 'authorization=user-supplied-local-ctf-artifact\ntarget_network=loopback-only\nruntime_mode=%s\nruntime_file=%s\n' \
  "$runtime_mode" "$runtime_file" > "$scope_dir/web-scope.env"
cp -a --update=none -- "$tools_dir/web-solve-template.py" "$work_dir/solve.py"
printf 'Web 문제 준비 완료: %s\n' "$challenge_dir"

[[ "$action" != prepare-only ]] || exit 0

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin=$(command -v codex 2>/dev/null || true)
fi
[[ -n "$codex_bin" && -x "$codex_bin" ]] || { echo 'Codex CLI를 찾을 수 없습니다.' >&2; exit 69; }

runtime_started=false
if [[ "$runtime_mode" == compose || "$runtime_mode" == dockerfile ]]; then
  runtime_args=(up --input "$input_dir" --work "$work_dir" --project "$project_name" --image "$image_name")
  [[ -z "$container_port" ]] || runtime_args+=(--port "$container_port")
  "$runtime_tool" "${runtime_args[@]}"
  runtime_started=true
else
  printf 'Compose/Dockerfile이 없어 STATIC-ONLY 소스 분석으로 계속합니다.\n'
fi

web_endpoint=
if [[ -f "$runtime_state" ]]; then
  # Generated by the trusted runtime helper.
  # shellcheck disable=SC1090
  source "$runtime_state"
  web_endpoint=${endpoint:-}
fi
export CTF_WEB_RUNTIME_STATE="$runtime_state"
export CTF_WEB_BASE_URL="$web_endpoint"
export CTF_WEB_RUNTIME_MODE="$runtime_mode"

cleanup_on_exit() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ "$runtime_started" == true && "$keep_docker" == false ]]; then
    printf '\nWeb Docker 리소스 정리 중: %s\n' "$project_name"
    "$runtime_tool" down --state "$runtime_state" || true
  fi
  if [[ "$keep_workspace" == false && -f "$work_dir/.solved" && -x "$tools_dir/ctf-clean.sh" ]]; then
    "$tools_dir/ctf-clean.sh" --apply "$challenge_name" || true
  fi
  exit "$status"
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

offline_args=(
  --disable browser_use
  --disable browser_use_external
  --disable browser_use_full_cdp_access
  --disable in_app_browser
  --disable standalone_web_search
)

set +e
"$codex_bin" -C "$agent_root" --model "$codex_model" \
  -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
  -c "service_tier=\"$codex_service_tier\"" --enable fast_mode \
  "${offline_args[@]}" \
  --sandbox danger-full-access --ask-for-approval never "$prompt"
status=$?
set -e
exit "$status"
