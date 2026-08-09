#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: ctf-bench [옵션] 문제이름 [HOST:PORT]

한 터미널에서 같은 로컬 CTF 문제를 plain Codex와 FAST_LOCAL로 병렬 실행하고
시간, 첫 플래그 후보, 토큰, 도구 호출 및 서브에이전트 이벤트를 비교합니다.

옵션:
  --source PATH       문제 원본 디렉터리 또는 ZIP 파일
  --timeout SECONDS   각 실행 제한 시간(기본 1800초)
  --remote HOST:PORT  허가된 원격 CTF 엔드포인트(정확히 이 주소만 허용)
  --order ORDER       이전 버전 호환 옵션이며 병렬 모드에서는 무시
  --dry-run           실행 경로와 고정 설정만 확인
  -h, --help          도움말

고정된 공정성 설정:
  model               gpt-5.6-sol
  reasoning effort    xhigh
  subagents           disabled
  Codex mode          exec --ephemeral --ignore-user-config

환경 변수:
  CTF_AGENT_ROOT      설치된 ctf-agent 루트
  CTF_PWNABLE_SOURCE  --source 생략 시 문제를 찾을 원본 루트
  CTF_BENCH_ROOT      결과 저장 루트(기본 <agent>/benchmarks)
  CODEX_BIN           Codex CLI 경로
EOF
}

source_override=
timeout_seconds=${CTF_BENCH_TIMEOUT_SECONDS:-1800}
run_order=plain-first
remote_endpoint=
dry_run=false
positionals=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo '--source에는 경로가 필요합니다.' >&2; exit 64; }
      source_override=$2
      shift
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { echo '--timeout에는 초 단위 정수가 필요합니다.' >&2; exit 64; }
      timeout_seconds=$2
      shift
      ;;
    --remote)
      [[ $# -ge 2 ]] || { echo '--remote에는 HOST:PORT가 필요합니다.' >&2; exit 64; }
      remote_endpoint=$2
      shift
      ;;
    --order)
      [[ $# -ge 2 ]] || { echo '--order에는 plain-first 또는 fast-first가 필요합니다.' >&2; exit 64; }
      run_order=$2
      shift
      ;;
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    --) shift; positionals+=("$@"); break ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    *) positionals+=("$1") ;;
  esac
  shift
done

[[ ${#positionals[@]} -ge 1 && ${#positionals[@]} -le 2 ]] || { usage >&2; exit 64; }
challenge_name=${positionals[0]}
if [[ ${#positionals[@]} -eq 2 ]]; then
  [[ -z "$remote_endpoint" ]] || { echo '--remote와 위치 인수 HOST:PORT를 동시에 지정할 수 없습니다.' >&2; exit 64; }
  remote_endpoint=${positionals[1]}
fi
if [[ ! "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$challenge_name" == "." || "$challenge_name" == ".." ]]; then
  printf '잘못된 문제 이름입니다: %s\n' "$challenge_name" >&2
  exit 65
fi
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || { printf 'timeout은 1 이상의 정수여야 합니다: %s\n' "$timeout_seconds" >&2; exit 65; }
[[ "$run_order" == plain-first || "$run_order" == fast-first ]] || { printf '잘못된 실행 순서입니다: %s\n' "$run_order" >&2; exit 65; }

remote_enabled=false
remote_host=
remote_port=
if [[ -n "$remote_endpoint" ]]; then
  if [[ "$remote_endpoint" =~ ^\[([^][]+)\]:([0-9]+)$ ]]; then
    remote_host=${BASH_REMATCH[1]}
    remote_port=${BASH_REMATCH[2]}
    if ! python3 -c 'import ipaddress, sys; ipaddress.IPv6Address(sys.argv[1])' "$remote_host" 2>/dev/null; then
      printf '잘못된 IPv6 원격 주소입니다: %s\n' "$remote_host" >&2
      exit 65
    fi
  elif [[ "$remote_endpoint" =~ ^([A-Za-z0-9.-]+):([0-9]+)$ ]]; then
    remote_host=${BASH_REMATCH[1]}
    remote_port=${BASH_REMATCH[2]}
  else
    printf '잘못된 원격 주소입니다(HOST:PORT 또는 [IPv6]:PORT): %s\n' "$remote_endpoint" >&2
    exit 65
  fi
  [[ ${#remote_port} -le 5 ]] || { printf '원격 포트는 1~65535 범위여야 합니다: %s\n' "$remote_port" >&2; exit 65; }
  remote_port=$((10#$remote_port))
  if (( remote_port < 1 || remote_port > 65535 )); then
    printf '원격 포트는 1~65535 범위여야 합니다: %s\n' "$remote_port" >&2
    exit 65
  fi
  remote_enabled=true
fi

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"
default_agent_root="$(cd -- "$script_dir/../.." && pwd)"
agent_root=${CTF_AGENT_ROOT:-$default_agent_root}
source_root=${CTF_PWNABLE_SOURCE:-$HOME/ctf-challenges/pwnable}
bench_root=${CTF_BENCH_ROOT:-$agent_root/benchmarks}
metrics_py="$script_dir/ctf-bench-metrics.py"
codex_bin=${CODEX_BIN:-}
model=gpt-5.6-sol
reasoning_effort=xhigh

if [[ -n "$source_override" ]]; then
  source_path=$source_override
elif [[ -d "$source_root/$challenge_name" ]]; then
  source_path="$source_root/$challenge_name"
else
  source_path="$source_root/$challenge_name.zip"
fi

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 없습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -e "$source_path" ]] || { printf '문제 원본을 찾을 수 없습니다: %s\n' "$source_path" >&2; exit 67; }
[[ -f "$metrics_py" ]] || { printf '벤치마크 집계기가 없습니다: %s\n' "$metrics_py" >&2; exit 66; }

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin="$(command -v codex 2>/dev/null || true)"
fi

if [[ "$dry_run" == true ]]; then
  printf '문제:             %s\n' "$challenge_name"
  printf '원본:             %s\n' "$source_path"
  printf '결과 루트:        %s\n' "$bench_root"
  printf '실행 방식:        plain Codex + FAST_LOCAL 병렬\n'
  if [[ "$remote_enabled" == true ]]; then
    printf '원격 엔드포인트:  %s:%s (이 주소만 허용)\n' "$remote_host" "$remote_port"
    printf '성공 판정:        원격 REMOTE_FLAG= 포착 즉시 성공 및 종료\n'
  else
    printf '성공 판정:        로컬 clean replay + .solved=verified\n'
  fi
  [[ "$run_order" == plain-first ]] || printf '참고:              --order=%s는 병렬 모드에서 무시\n' "$run_order"
  printf '실행별 제한:      %s초\n' "$timeout_seconds"
  printf 'Codex:            %s\n' "${codex_bin:-찾을 수 없음}"
  printf '모델:             %s\n' "$model"
  printf '추론 강도:        %s\n' "$reasoning_effort"
  printf '서브에이전트:     비활성화(features.multi_agent=false)\n'
  printf '세션 저장:        비활성화(--ephemeral)\n'
  exit 0
fi

[[ -n "$codex_bin" && -x "$codex_bin" ]] || { echo 'Codex CLI를 사용할 수 없습니다.' >&2; exit 69; }
command -v python3 >/dev/null 2>&1 || { echo 'python3가 필요합니다.' >&2; exit 69; }
command -v timeout >/dev/null 2>&1 || { echo 'GNU timeout이 필요합니다.' >&2; exit 69; }
command -v setsid >/dev/null 2>&1 || { echo 'util-linux setsid가 필요합니다.' >&2; exit 69; }
command -v mkfifo >/dev/null 2>&1 || { echo 'mkfifo가 필요합니다.' >&2; exit 69; }
command -v mktemp >/dev/null 2>&1 || { echo 'mktemp가 필요합니다.' >&2; exit 69; }

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_root="$bench_root/runs/$run_id"
plain_root="$run_root/plain"
fast_root="$run_root/fast-local"
plain_input="$plain_root/input"
plain_work="$plain_root/work"
fast_challenge="$fast_root/challenges/$challenge_name"
fast_input="$fast_challenge/input"
fast_work="$fast_challenge/work"
image_prefix="ctf-bench-${run_id,,}"
plain_image="${image_prefix}-plain:local"
fast_image="${image_prefix}-fast-local:local"

mkdir -p "$plain_input" "$plain_work" "$fast_input" "$fast_work" \
  "$fast_challenge/evidence/private" "$fast_challenge/scope" "$run_root/metrics"

copy_source() {
  local destination=$1
  if [[ -d "$source_path" ]]; then
    cp -a -- "$source_path"/. "$destination"/
  else
    cp -a -- "$source_path" "$destination"/
  fi
}
copy_source "$plain_input"
copy_source "$fast_input"

printf '%s\n' "$source_path" > "$fast_challenge/scope/source-path.txt"
printf 'pwn\n' > "$fast_challenge/.ctf-category"
if [[ "$remote_enabled" == true ]]; then
  printf 'authorization=user-supplied-ctf-endpoint\ntarget_network=exact-endpoint-only\nremote_host=%s\nremote_port=%s\nscoreboard=denied\n' \
    "$remote_host" "$remote_port" > "$fast_challenge/scope/benchmark.env"
  {
    printf 'authorization=user-declared-official-ctf-endpoint\n'
    printf 'protocol=tcp\n'
    printf 'host=%s\nport=%s\n' "$remote_host" "$remote_port"
    printf 'allowed_attempts=2\n'
    printf 'scoreboard_submission=denied\n'
  } > "$fast_challenge/scope/remote-target.env"
else
  printf 'authorization=user-supplied-local-ctf-artifact\ntarget_network=denied\n' > "$fast_challenge/scope/benchmark.env"
  rm -f -- "$fast_challenge/scope/remote-target.env"
fi

# FAST_LOCAL gets the project policy, skill, feedback and deterministic tools.
# The plain workspace intentionally has none of these links.
ln -s "$agent_root/shimes/AGENTS.md" "$fast_root/AGENTS.md"
ln -s "$agent_root/rules" "$fast_root/rules"
ln -s "$agent_root/pwn-agent" "$fast_root/pwn-agent"
ln -s "$agent_root/references" "$fast_root/references"
cp -a -- "$agent_root/state" "$fast_root/state"

if [[ "$remote_enabled" == true ]]; then
  network_rule=$(printf '%s\n' \
    "- 원격 접속은 사용자가 허가한 정확한 TCP 엔드포인트 '$remote_host:$remote_port'에만 허용한다." \
    '- 다른 호스트·포트 탐색, 스캔, 인접 서비스 접속 및 대회 플랫폼/scoreboard 접속은 금지한다.' \
    '- 문제 바이너리는 호스트에서 실행하지 말고 Docker 격리 안에서만 실행하라.')
  plain_completion_rule=$(printf '%s\n' \
    '- 정확한 원격 엔드포인트의 실제 응답에서 형식이 유효한 플래그를 받는 즉시 `REMOTE_FLAG=<받은 플래그>` 한 줄만 출력하고 바로 종료하라.' \
    '- 원격 플래그를 받은 뒤에는 재검증, clean replay, writeup 보완, `.solved` 작성 등 모든 후속 작업을 생략하라.' \
    '- 로컬 플래그, 추측값, 예시 문자열에는 절대로 `REMOTE_FLAG=` 표식을 사용하지 마라.')
  fast_completion_rule=$plain_completion_rule
  final_answer_rule='- 원격 플래그를 얻지 못한 채 종료할 때만 현재 상태와 정확한 차단 원인을 간단히 보고하라.'
else
  network_rule='- 대상 네트워크 접속, 호스트에서 문제 바이너리 실행, 플래그 자동 제출은 금지한다.'
  plain_completion_rule='- exploit 경로로 플래그를 clean replay에서 재현한 경우에만 work/.solved에 verified 한 줄을 기록하라.'
  fast_completion_rule="- exploit 경로로 플래그를 clean replay에서 재현한 경우에만 challenges/$challenge_name/work/.solved에 verified 한 줄을 기록하라."
  final_answer_rule='- 최종 답변에는 성공 여부, 검증 근거와 플래그 후보를 포함하라.'
fi

cat > "$run_root/plain.prompt.txt" <<EOF
허가된 로컬 CTF pwn 문제 '$challenge_name'을 해결하라.

- 입력은 input/에 있으며 원본은 수정하지 마라.
- 결과는 work/solve.py와 work/writeup.md에 작성하라.
- 문제 파일은 신뢰할 수 없으므로 정적으로 먼저 확인하고, 실행은 Docker 격리 안에서만 수행하라.
- Docker 이미지가 필요하면 정확히 '$plain_image' 태그만 사용하고 다른 벤치마크 이미지나 컨테이너를 재사용하지 마라.
$network_rule
- 서브에이전트나 다른 에이전트를 호출하지 말고 현재 에이전트가 직접 수행하라.
$plain_completion_rule
$final_answer_rule
EOF

cat > "$run_root/fast-local.prompt.txt" <<EOF
허가된 로컬 CTF pwn 문제 '$challenge_name'을 FAST_LOCAL 방식으로 해결하라.

- 시작 전에 AGENTS.md, rules/ruleset.md, pwn-agent/skills/SKILL.md, pwn-agent/docs/HARD_RULES.md, pwn-agent/docs/role.md, pwn-agent/docs/playbook.md를 읽고 적용하라.
- 입력은 challenges/$challenge_name/input에 있으며 원본은 수정하지 마라.
- 결과는 challenges/$challenge_name/work/solve.py와 challenges/$challenge_name/work/writeup.md에 작성하라.
$network_rule
- Docker 이미지가 필요하면 references/tools/pwn-build.sh로 정확히 '$fast_image'를 만들고 이 이미지에만 pwn-run.sh를 사용하라.
- 멀티에이전트 기능은 비활성화되어 있다. 서브에이전트를 호출하거나 활성화를 요청하지 말고 현재 에이전트가 모든 단계를 직접 수행하라.
$fast_completion_rule
- 프로젝트 정책, 피드백과 references/tools의 하니스를 사용하되 이 지식·정책·도구 파일 자체는 수정하지 마라.
$final_answer_rule
EOF

stop_process_group() {
  local process_id=$1
  local signal=${2:-INT}

  kill -"$signal" -- "-$process_id" 2>/dev/null || true
  sleep 0.1
  kill -TERM -- "-$process_id" 2>/dev/null || true
  sleep 0.1
  kill -KILL -- "-$process_id" 2>/dev/null || true
}

run_variant() {
  local key=$1
  local label=$2
  local workspace=$3
  local work_dir=$4
  local prompt_file=$5
  local docker_image=$6
  local events_file="$run_root/metrics/$key.events.jsonl"
  local stderr_file="$run_root/metrics/$key.stderr.log"
  local status_file="$run_root/metrics/$key.status"
  local fifo_dir fifo_file
  local started_ns ended_ns duration_ms codex_status capture_status codex_pid
  local -a capture_options=(--label "$label" --output "$events_file" --quiet)

  if [[ "$remote_enabled" == true ]]; then
    capture_options+=(--stop-on-flag)
  fi

  while [[ ! -e "$start_gate" ]]; do
    sleep 0.01
  done
  started_ns=$(date +%s%N)
  fifo_dir=$(mktemp -d "${TMPDIR:-/tmp}/ctf-bench-${run_id}-${key}.XXXXXX")
  fifo_file="$fifo_dir/events.fifo"
  mkfifo -- "$fifo_file"
  set +e
  setsid --wait timeout --foreground --signal=INT --kill-after=30s "${timeout_seconds}s" \
    env CTF_AGENT_ROOT="$workspace" CTF_BENCH_WORK_DIR="$work_dir" \
      CTF_BENCH_DOCKER_IMAGE="$docker_image" CTF_BENCH_REMOTE="$remote_enabled" \
      CTF_REMOTE_HOST="$remote_host" CTF_REMOTE_PORT="$remote_port" \
    "$codex_bin" exec --ephemeral --ignore-user-config --skip-git-repo-check \
      -C "$workspace" --model "$model" \
      -c "model_reasoning_effort=\"$reasoning_effort\"" \
      -c 'approval_policy="never"' \
      --disable multi_agent --sandbox danger-full-access --json - \
      < "$prompt_file" > "$fifo_file" 2> "$stderr_file" &
  codex_pid=$!
  python3 "$metrics_py" capture "${capture_options[@]}" < "$fifo_file"
  capture_status=$?
  if [[ "$capture_status" -ne 0 ]]; then
    stop_process_group "$codex_pid" INT
  fi
  wait "$codex_pid"
  codex_status=$?
  set -e
  rm -f -- "$fifo_file"
  rmdir -- "$fifo_dir" 2>/dev/null || true
  ended_ns=$(date +%s%N)
  duration_ms=$(( (ended_ns - started_ns) / 1000000 ))

  {
    printf 'exit_status=%s\n' "$codex_status"
    printf 'capture_status=%s\n' "$capture_status"
    printf 'duration_ms=%s\n' "$duration_ms"
    printf 'timed_out=%s\n' "$([[ "$codex_status" -eq 124 ]] && printf true || printf false)"
    printf 'remote_mode=%s\n' "$remote_enabled"
    printf 'flag_short_circuit=%s\n' "$([[ "$capture_status" -eq 10 ]] && printf true || printf false)"
  } > "$status_file"

  python3 "$metrics_py" summarize \
    --key "$key" --label "$label" --events "$events_file" --status "$status_file" \
    --work-dir "$work_dir" --output "$run_root/metrics/$key.summary.json"

  if [[ -x "$agent_root/references/tools/pwn-cleanup.sh" ]]; then
    "$agent_root/references/tools/pwn-cleanup.sh" "$docker_image" >/dev/null 2>&1 || true
  fi
}

start_gate="$run_root/.parallel-start"
plain_pid=
fast_pid=

terminate_variants() {
  trap - INT TERM HUP
  [[ -z "$plain_pid" ]] || kill -TERM "$plain_pid" 2>/dev/null || true
  [[ -z "$fast_pid" ]] || kill -TERM "$fast_pid" 2>/dev/null || true
  [[ -z "$plain_pid" ]] || wait "$plain_pid" 2>/dev/null || true
  [[ -z "$fast_pid" ]] || wait "$fast_pid" 2>/dev/null || true
  exit 130
}
trap terminate_variants INT TERM HUP

run_variant plain 'plain Codex' "$plain_root" "$plain_work" \
  "$run_root/plain.prompt.txt" "$plain_image" &
plain_pid=$!
run_variant fast_local 'FAST_LOCAL' "$fast_root" "$fast_work" \
  "$run_root/fast-local.prompt.txt" "$fast_image" &
fast_pid=$!

printf 'plain Codex와 FAST_LOCAL을 병렬로 시작합니다.\n'
: > "$start_gate"

set +e
wait "$plain_pid"
plain_runner_status=$?
wait "$fast_pid"
fast_runner_status=$?
set -e
trap - INT TERM HUP
rm -f -- "$start_gate"

if [[ $plain_runner_status -ne 0 || $fast_runner_status -ne 0 ]]; then
  printf '벤치마크 실행기 오류: plain=%s fast=%s\n' "$plain_runner_status" "$fast_runner_status" >&2
  exit 74
fi

python3 "$metrics_py" report \
  --plain "$run_root/metrics/plain.summary.json" \
  --fast "$run_root/metrics/fast_local.summary.json" \
  --output "$run_root/report.md"

printf '\n전체 결과: %s\n' "$run_root"
printf '비교 보고서: %s\n' "$run_root/report.md"
