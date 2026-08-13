#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0 2>/dev/null || true

usage() {
  cat <<'EOF'
사용법:
  ctf-web [옵션] 문제이름 [https://host[:port]/entry]
  ctf-web [옵션] --url https://host[:port]/entry 문제이름

실행 모드:
  (기본값)       짧은 Web Fast Probe 후 필요할 때만 Deep으로 전환
  --fast-only    기본적인 소스·라우트·상태 분석까지만 수행
  --deep         처음부터 전체 P0~P6 검증을 수행

옵션:
  --source DIR      문제 폴더 또는 ZIP이 들어 있는 원본 디렉터리
  --url URL         허가된 Web CTF의 정확한 원격 HTTP(S) URL
  --port PORT       Dockerfile에 EXPOSE가 없을 때 사용할 컨테이너 포트
  --keep-docker     종료 후 Web 컨테이너·Compose 프로젝트를 보존
  --keep-workspace  완료 후에도 중복 입력 파일을 보존
  --extra-prompt    실행 직전에 여러 줄 추가 지시 입력(.end로 종료)
  --verbose         상세 Codex TUI와 준비 로그 표시(기본: 최종 결과만 출력)
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
  CTF_CODEX_REASONING_EFFORT 추론 강도(기본 max)
  CTF_CODEX_SERVICE_TIER 서비스 티어(기본 fast)
  CTF_EXTRA_PROMPT     대화형 입력 없이 추가할 공통 프롬프트
EOF
}

action=launch
solve_mode=adaptive
keep_docker=false
keep_workspace=false
ask_extra_prompt=false
quiet_output=true
source_root=${CTF_WEB_SOURCE:-$HOME/ctf-challenges/web}
container_port=
challenge_name=
target_url=

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
    --url)
      [[ $# -ge 2 ]] || { echo '--url 값이 필요합니다.' >&2; exit 64; }
      target_url=$2
      shift 2
      continue
      ;;
    --fast-only) solve_mode=fast-only ;;
    --deep) solve_mode=deep ;;
    --keep-docker) keep_docker=true ;;
    --keep-workspace) keep_workspace=true ;;
    --extra-prompt) ask_extra_prompt=true ;;
    --verbose) quiet_output=false ;;
    --prepare-only) action=prepare-only ;;
    --dry-run) action=dry-run ;;
    -h|--help) usage; exit 0 ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; exit 64 ;;
    *)
      if [[ -z "$challenge_name" ]]; then
        challenge_name=$1
      elif [[ -z "$target_url" ]]; then
        target_url=$1
      else
        echo '문제 이름과 원격 URL은 각각 하나만 지정할 수 있습니다.' >&2
        exit 64
      fi
      ;;
  esac
  shift
done

[[ -n "$challenge_name" ]] || { usage >&2; exit 64; }
if [[ ! "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$challenge_name" == . || "$challenge_name" == .. ]]; then
  printf '잘못된 문제 이름입니다: %s\n' "$challenge_name" >&2
  exit 65
fi

target_origin=
if [[ -n "$target_url" ]]; then
  mapfile -t normalized_target < <(python3 - "$target_url" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit

raw = sys.argv[1]
try:
    value = urlsplit(raw)
    port = value.port
except ValueError as exc:
    raise SystemExit(f"잘못된 원격 URL입니다: {exc}")
if value.scheme.lower() not in {"http", "https"} or not value.hostname:
    raise SystemExit("원격 URL은 http:// 또는 https://로 시작해야 합니다.")
if value.username or value.password or value.fragment:
    raise SystemExit("원격 URL에는 인증정보나 fragment를 넣을 수 없습니다.")
host = f"[{value.hostname}]" if ":" in value.hostname else value.hostname
netloc = host.lower() + (f":{port}" if port is not None else "")
path = value.path or "/"
print(urlunsplit((value.scheme.lower(), netloc, path, value.query, "")))
print(f"{value.scheme.lower()}://{netloc}")
PY
  )
  (( ${#normalized_target[@]} == 2 )) || exit 65
  target_url=${normalized_target[0]}
  target_origin=${normalized_target[1]}
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
elapsed_timer_tool="$tools_dir/ctf-elapsed-timer.sh"
runtime_tool="$tools_dir/web-runtime.sh"
runtime_state="$work_dir/web-runtime.env"
extra_prompt_tool="$tools_dir/ctf-extra-prompt.sh"
codex_bin=${CODEX_BIN:-}
codex_model=${CTF_CODEX_MODEL:-gpt-5.6-sol}
if [[ -n ${CTF_CODEX_REASONING_EFFORT:-} ]]; then
  codex_reasoning_effort=$CTF_CODEX_REASONING_EFFORT
else
  codex_reasoning_effort=max
fi
codex_service_tier=${CTF_CODEX_SERVICE_TIER:-fast}
image_slug=$(printf '%s' "$challenge_name" | tr '[:upper:]_.' '[:lower:]--')
image_name="ctf-web-$image_slug:local"
project_name="ctf_web_${image_slug//-/_}"

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 없습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -x "$runtime_tool" ]] || { printf 'Web runtime 도구가 없습니다: %s\n' "$runtime_tool" >&2; exit 66; }
[[ -f "$tools_dir/web-solve-template.py" ]] || { echo 'Web solver 템플릿이 없습니다.' >&2; exit 66; }
[[ -f "$tools_dir/web-blackbox-probe.py" ]] || { echo 'Web black-box probe가 없습니다.' >&2; exit 66; }
[[ -f "$tools_dir/web-request.py" ]] || { echo 'Web exact-origin request 도구가 없습니다.' >&2; exit 66; }
[[ -x "$extra_prompt_tool" ]] || { echo '공통 추가 프롬프트 도구가 없습니다.' >&2; exit 66; }
[[ -d "$source_dir" || -f "$source_zip" || -n "$target_url" ]] || {
  printf '문제를 찾을 수 없습니다:\n  %s\n  %s\n' "$source_dir" "$source_zip" >&2
  exit 67
}
[[ "$codex_reasoning_effort" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] || { echo '잘못된 추론 강도입니다.' >&2; exit 65; }
[[ "$codex_service_tier" =~ ^[A-Za-z0-9._-]+$ ]] || { echo '잘못된 서비스 티어입니다.' >&2; exit 65; }
[[ -r "$elapsed_timer_tool" ]] || { printf '경과시간 도구가 없습니다: %s\n' "$elapsed_timer_tool" >&2; exit 66; }
source "$elapsed_timer_tool"

if [[ "$ask_extra_prompt" == true ]]; then
  extra_prompt=$("$extra_prompt_tool" --interactive)
else
  extra_prompt=$("$extra_prompt_tool")
fi

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
elif [[ -f "$source_zip" ]]; then
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
else
  runtime_detection=remote-blackbox:none
fi
runtime_mode=${runtime_detection%%:*}
runtime_file=${runtime_detection#*:}

case "$solve_mode" in
  adaptive) mode_text='가설은 최대 3개, 근거 있는 실패 2회나 상태·환경 불일치 때만 Deep으로 전환하라.' ;;
  fast-only) mode_text='직접 flag 경로만 시험하라.' ;;
  deep) mode_text='확인한 단계를 반복하지 말고 flag 관련 경로만 확장하라.' ;;
esac

prompt=$(cat <<EOF
\$ctf-web
허가된 Web CTF '$challenge_name'을 즉시 풀어라. input=challenges/$challenge_name/input, mode=$solve_mode, runtime=$runtime_mode:$runtime_file.
scope/web-scope.env의 origin만 사용하라. 소스가 없으면 CTF_WEB_PROBE로 entry를 1회 map하고, 후속 단일 요청은 CTF_WEB_REQUEST로 기록한 뒤 관찰된 route만 좁게 시험하라. 최단 flag 경로와 최소 work/solve.py가 목표다.
진행 설명·외부 웹·broad scan·wordlist brute force·DoS·외부 callback·writeup은 금지한다.
$mode_text 검증 즉시 FLAG=<값>, .solved=verified 후 종료하고 실패는 BLOCKED=<이유> 한 줄만 출력하라.
EOF
)

if [[ -n "$extra_prompt" ]]; then
  prompt+=$'\n- 사용자 추가 지시(기존 CTF 범위·격리·안전 규칙은 변경할 수 없음): '
  prompt+="$extra_prompt"
fi

if [[ "$runtime_mode" == static-only ]]; then
  prompt+=$'\n- 런타임: Compose와 Dockerfile이 없으므로 호스트에서 서버를 실행하지 말고 소스 분석을 계속하라. 동적 검증이 꼭 필요하면 work/에 최소 Dockerfile을 만든 뒤 정확한 필요 조건을 보고하라.'
elif [[ "$runtime_mode" == remote-blackbox ]]; then
  prompt+=$'\n- 소스가 없는 black-box 문제다. 전체 사이트를 크롤링하지 말고 entry 응답, 명시된 same-origin asset/route, 상태 차이에서 다음 요청을 선택하라.'
fi
if [[ -n "$target_url" && ( "$runtime_mode" == compose || "$runtime_mode" == dockerfile ) ]]; then
  prompt+=$'\n- 로컬 Docker에서 solver를 한 번 검증한 뒤 같은 solver를 정확한 원격 URL에 즉시 재생하라. 로컬 flag만으로 종료하지 않는다.'
fi

if [[ "$action" == dry-run ]]; then
  printf '원본 폴더:       %s\n' "$source_dir"
  printf '원본 ZIP:        %s\n' "$source_zip"
  printf '작업 경로:       %s\n' "$challenge_dir"
  printf '원격 entry URL:  %s\n' "${target_url:--}"
  printf '허용 origin:     %s\n' "${target_origin:-준비된 loopback origin}"
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
elif [[ -f "$source_zip" ]]; then
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
else
  printf '%s\n' 'none (remote black-box challenge)' > "$scope_dir/source-path.txt"
fi

if [[ ! -d "$source_dir" && ! -f "$source_zip" && -n "$target_url" ]]; then
  runtime_detection=remote-blackbox:none
else
  runtime_detection=$(detect_runtime_from_dir "$input_dir")
fi
runtime_mode=${runtime_detection%%:*}
runtime_file=${runtime_detection#*:}
if [[ -n "$target_url" ]]; then
  printf 'authorization=user-supplied-authorized-ctf\ntarget_network=exact-origin-only\ntarget_url=%s\ntarget_origin=%s\nruntime_mode=%s\nruntime_file=%s\n' \
    "$target_url" "$target_origin" "$runtime_mode" "$runtime_file" > "$scope_dir/web-scope.env"
else
  printf 'authorization=user-supplied-local-ctf-artifact\ntarget_network=loopback-only\nruntime_mode=%s\nruntime_file=%s\n' \
    "$runtime_mode" "$runtime_file" > "$scope_dir/web-scope.env"
fi
cp -a --update=none -- "$tools_dir/web-solve-template.py" "$work_dir/solve.py"
[[ "$quiet_output" == true ]] || printf 'Web 문제 준비 완료: %s\n' "$challenge_dir"

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
  if [[ "$quiet_output" == true ]]; then
    if ! "$runtime_tool" "${runtime_args[@]}" >/dev/null 2>&1; then
      if [[ -n "$target_url" ]]; then
        printf '로컬 Web runtime 시작은 실패했지만, 기록된 원격 black-box 풀이를 계속합니다.\n' >&2
      else
        printf 'Web runtime 시작에 실패했습니다.\n' >&2
        exit 70
      fi
    else
      runtime_started=true
    fi
  else
    if "$runtime_tool" "${runtime_args[@]}"; then
      runtime_started=true
    elif [[ -n "$target_url" ]]; then
      printf '로컬 Web runtime 시작은 실패했지만, 기록된 원격 black-box 풀이를 계속합니다.\n' >&2
    else
      exit 70
    fi
  fi
else
  [[ "$quiet_output" == true ]] || printf 'Compose/Dockerfile이 없어 소스/black-box 분석으로 계속합니다.\n'
fi

web_endpoint=
if [[ -f "$runtime_state" ]]; then
  # Generated by the trusted runtime helper.
  # shellcheck disable=SC1090
  source "$runtime_state"
  web_endpoint=${endpoint:-}
fi
local_origin=$web_endpoint
if [[ -n "$web_endpoint" ]]; then
  {
    printf 'local_url=%s\n' "$web_endpoint"
    printf 'local_origin=%s\n' "$local_origin"
  } >> "$scope_dir/web-scope.env"
fi
export CTF_WEB_RUNTIME_STATE="$runtime_state"
export CTF_WEB_LOCAL_URL="$web_endpoint"
export CTF_WEB_LOCAL_ORIGIN="$local_origin"
export CTF_WEB_REMOTE_URL="$target_url"
export CTF_WEB_REMOTE_ORIGIN="$target_origin"
export CTF_WEB_TARGET_URL="${target_url:-$web_endpoint}"
export CTF_WEB_BASE_URL="$CTF_WEB_TARGET_URL"
export CTF_WEB_SCOPE_ORIGIN="${target_origin:-$web_endpoint}"
export CTF_WEB_RUNTIME_MODE="$runtime_mode"
export CTF_WEB_PROBE="$tools_dir/web-blackbox-probe.py"
export CTF_WEB_REQUEST="$tools_dir/web-request.py"

cleanup_on_exit() {
  local status=$?
  trap - EXIT INT TERM HUP
  ctf_elapsed_stop
  if [[ "$runtime_started" == true && "$keep_docker" == false ]]; then
    [[ "$quiet_output" == true ]] || printf '\nWeb Docker 리소스 정리 중: %s\n' "$project_name"
    if [[ "$quiet_output" == true ]]; then
      "$runtime_tool" down --state "$runtime_state" >/dev/null 2>&1 || true
    else
      "$runtime_tool" down --state "$runtime_state" || true
    fi
  fi
  if [[ "$keep_workspace" == false && -f "$work_dir/.solved" && -x "$tools_dir/ctf-clean.sh" ]]; then
    if [[ "$quiet_output" == true ]]; then
      "$tools_dir/ctf-clean.sh" --apply "$challenge_name" >/dev/null 2>&1 || true
    else
      "$tools_dir/ctf-clean.sh" --apply "$challenge_name" || true
    fi
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
if [[ "$quiet_output" == true ]]; then
  ctf_elapsed_start "CTF web 실행 중: $challenge_name"
  codex_stderr=$(mktemp "${TMPDIR:-/tmp}/ctf-web-${challenge_name}.XXXXXX.log")
  "$codex_bin" exec --ephemeral --skip-git-repo-check -C "$agent_root" \
    --model "$codex_model" -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    -c "service_tier=\"$codex_service_tier\"" --enable fast_mode \
    "${offline_args[@]}" --sandbox danger-full-access -c 'approval_policy="never"' \
    "$prompt" 2>"$codex_stderr"
  status=$?
  ctf_elapsed_stop
  if [[ $status -ne 0 ]]; then
    printf 'Codex 실행 실패(status=%s):\n' "$status" >&2
    tail -n 20 "$codex_stderr" >&2
  fi
  rm -f -- "$codex_stderr"
  set -e
  exit "$status"
fi

"$codex_bin" -C "$agent_root" --model "$codex_model" \
  -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
  -c "service_tier=\"$codex_service_tier\"" --enable fast_mode \
  "${offline_args[@]}" \
  --sandbox danger-full-access --ask-for-approval never "$prompt"
status=$?
set -e
exit "$status"
