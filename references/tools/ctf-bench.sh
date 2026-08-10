#!/usr/bin/env bash
set -euo pipefail

invoked_as=$(basename -- "$0")
case "$invoked_as" in
  ctf-bench|ctf-bench.sh|ctf-bench-pwn) category=pwn ;;
  ctf-bench-rev) category=rev ;;
  ctf-bench-web) category=web ;;
  ctf-bench-crypto) category=crypto ;;
  ctf-bench-forensics) category=forensics ;;
  *) category=${CTF_BENCH_CATEGORY:-pwn} ;;
esac

usage() {
  cat <<'EOF'
사용법: ctf-bench-{pwn,rev,web,crypto,forensics} [옵션] 문제이름 [HOST:PORT]

같은 카테고리의 로컬 CTF 문제를 plain Codex와 FAST_LOCAL로 병렬 실행하고
시간, 첫 플래그 후보, 토큰, 도구 호출 및 서브에이전트 이벤트를 비교합니다.
`ctf-bench`는 이전 호환성을 위해 `ctf-bench-pwn`과 같습니다.

옵션:
  --source PATH       문제 원본 디렉터리 또는 ZIP 파일
  --timeout SECONDS   명시적 실행 제한 시간(기본 0: 자동 종료 없음)
  --remote HOST:PORT  pwn 전용 허가 원격 엔드포인트(정확히 이 주소만 허용)
  --exact-tokens      플래그 성공 시 최대 30초 동안 최종 usage만 기다려 정확한 토큰 집계
  --order ORDER       이전 버전 호환 옵션이며 병렬 모드에서는 무시
  --dry-run           실행 경로와 고정 설정만 확인
  -h, --help          도움말

고정된 공정성 설정:
  model               gpt-5.6-sol
  reasoning effort    high
  service tier        fast
  subagents           disabled
  automatic skills    disabled (FAST_LOCAL uses concise AGENTS.md)
  Codex mode          exec --ephemeral --ignore-user-config

환경 변수:
  CTF_AGENT_ROOT      설치된 ctf-agent 루트
  CTF_PWNABLE_SOURCE  pwn 기본 원본 루트
  CTF_REV_SOURCE      rev 기본 원본 루트
  CTF_WEB_SOURCE      web 기본 원본 루트
  CTF_CRYPTO_SOURCE   crypto 기본 원본 루트
  CTF_FORENSICS_SOURCE forensics 기본 원본 루트
  CTF_BENCH_ROOT      결과 저장 루트(기본 <agent>/benchmarks)
  CODEX_BIN           Codex CLI 경로
EOF
}

source_override=
timeout_seconds=${CTF_BENCH_TIMEOUT_SECONDS:-0}
run_order=plain-first
remote_endpoint=
dry_run=false
exact_tokens=false
usage_grace_seconds=${CTF_BENCH_USAGE_GRACE_SECONDS:-30}
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
    --exact-tokens) exact_tokens=true ;;
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
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] || { printf 'timeout은 0 이상의 정수여야 합니다: %s\n' "$timeout_seconds" >&2; exit 65; }
[[ "$usage_grace_seconds" =~ ^[1-9][0-9]*$ ]] || { printf 'CTF_BENCH_USAGE_GRACE_SECONDS는 1 이상의 정수여야 합니다: %s\n' "$usage_grace_seconds" >&2; exit 65; }
[[ "$run_order" == plain-first || "$run_order" == fast-first ]] || { printf '잘못된 실행 순서입니다: %s\n' "$run_order" >&2; exit 65; }

remote_enabled=false
remote_host=
remote_port=
if [[ -n "$remote_endpoint" ]]; then
  [[ "$category" == pwn ]] || { printf '%s 벤치는 --remote HOST:PORT를 지원하지 않습니다. 로컬 격리 문제로 실행하세요.\n' "$category" >&2; exit 64; }
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
case "$category" in
  pwn) source_root=${CTF_PWNABLE_SOURCE:-$HOME/ctf-challenges/pwnable} ;;
  rev) source_root=${CTF_REV_SOURCE:-$HOME/ctf-challenges/reversing} ;;
  web) source_root=${CTF_WEB_SOURCE:-$HOME/ctf-challenges/web} ;;
  crypto) source_root=${CTF_CRYPTO_SOURCE:-$HOME/ctf-challenges/crypto} ;;
  forensics) source_root=${CTF_FORENSICS_SOURCE:-$HOME/ctf-challenges/forensics} ;;
esac
bench_root=${CTF_BENCH_ROOT:-$agent_root/benchmarks}
metrics_py="$script_dir/ctf-bench-metrics.py"
codex_bin=${CODEX_BIN:-}
source_codex_home=${CODEX_HOME:-$HOME/.codex}
model=gpt-5.6-sol
reasoning_effort=high

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
if [[ "$category" == pwn ]]; then
  [[ -f "$agent_root/references/tools/pwntools-template.py" ]] || { echo 'pwntools solver 템플릿이 없습니다.' >&2; exit 66; }
fi

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin="$(command -v codex 2>/dev/null || true)"
fi

if [[ "$dry_run" == true ]]; then
  printf '문제:             %s\n' "$challenge_name"
  printf '카테고리:         %s\n' "$category"
  printf '원본:             %s\n' "$source_path"
  printf '결과 루트:        %s\n' "$bench_root"
  printf '실행 방식:        plain Codex + FAST_LOCAL 병렬\n'
  if [[ "$remote_enabled" == true ]]; then
    printf '원격 엔드포인트:  %s:%s (이 주소만 허용)\n' "$remote_host" "$remote_port"
    printf '성공 판정:        원격 하니스 플래그 포착 즉시 성공 및 종료\n'
  else
    printf '성공 판정:        로컬 clean replay + .solved=verified\n'
  fi
  [[ "$run_order" == plain-first ]] || printf '참고:              --order=%s는 병렬 모드에서 무시\n' "$run_order"
  if (( timeout_seconds > 0 )); then
    printf '실행별 제한:      %s초 (사용자가 명시한 경우만 자동 종료)\n' "$timeout_seconds"
  else
    printf '실행별 제한:      없음 (풀이 중 자동 종료 금지)\n'
  fi
  printf 'Codex:            %s\n' "${codex_bin:-찾을 수 없음}"
  printf '모델:             %s\n' "$model"
  printf '추론 강도:        %s\n' "$reasoning_effort"
  printf '서비스 등급:      fast (fast_mode)\n'
  printf '웹 탐색:          비활성화\n'
  printf '서브에이전트:     비활성화(features.multi_agent=false)\n'
  printf '자동 스킬 검색:   비활성화(features.skill_search=false)\n'
  printf '세션 저장:        비활성화(--ephemeral)\n'
  printf '토큰 집계:        %s\n' "$([[ "$exact_tokens" == true ]] && printf '최종 usage 대기(최대 %s초)' "$usage_grace_seconds" || printf '즉시 종료; usage 미도착 시 미집계')"
  exit 0
fi

[[ -n "$codex_bin" && -x "$codex_bin" ]] || { echo 'Codex CLI를 사용할 수 없습니다.' >&2; exit 69; }
command -v python3 >/dev/null 2>&1 || { echo 'python3가 필요합니다.' >&2; exit 69; }
if (( timeout_seconds > 0 )); then
  command -v timeout >/dev/null 2>&1 || { echo '명시적 --timeout 사용에는 GNU timeout이 필요합니다.' >&2; exit 69; }
fi
command -v setsid >/dev/null 2>&1 || { echo 'util-linux setsid가 필요합니다.' >&2; exit 69; }
command -v mkfifo >/dev/null 2>&1 || { echo 'mkfifo가 필요합니다.' >&2; exit 69; }
command -v mktemp >/dev/null 2>&1 || { echo 'mktemp가 필요합니다.' >&2; exit 69; }
command -v find >/dev/null 2>&1 || { echo 'find가 필요합니다.' >&2; exit 69; }
[[ -f "$source_codex_home/auth.json" ]] || { printf 'Codex 인증 파일을 찾을 수 없습니다: %s\n' "$source_codex_home/auth.json" >&2; exit 69; }

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_root="$bench_root/runs/$category/$run_id"
plain_root="$run_root/plain"
fast_root="$run_root/fast-local"
plain_input="$plain_root/input"
plain_work="$plain_root/work"
plain_scope="$plain_root/scope"
plain_evidence="$plain_root/evidence/private"
fast_challenge="$fast_root/challenges/$challenge_name"
fast_input="$fast_challenge/input"
fast_work="$fast_challenge/work"
common_tools="$run_root/tools"
common_remote_harness="$common_tools/pwn-remote-run.sh"
image_prefix="ctf-bench-$category-${run_id,,}"
plain_image="${image_prefix}-plain:local"
fast_image="${image_prefix}-fast-local:local"
benchmark_codex_home_parent="${XDG_CACHE_HOME:-$HOME/.cache}/ctf-bench-codex-homes"
benchmark_codex_home_root="$benchmark_codex_home_parent/$run_id"

mkdir -p "$plain_input" "$plain_work" "$plain_scope" "$plain_evidence" \
  "$fast_input" "$fast_work" "$fast_challenge/evidence/private" \
  "$fast_challenge/scope" "$run_root/metrics" "$common_tools" \
  "$benchmark_codex_home_root/plain" "$benchmark_codex_home_root/fast_local"
chmod 700 "$benchmark_codex_home_root" \
  "$benchmark_codex_home_root/plain" "$benchmark_codex_home_root/fast_local"
ln -s -- "$source_codex_home/auth.json" "$benchmark_codex_home_root/plain/auth.json"
ln -s -- "$source_codex_home/auth.json" "$benchmark_codex_home_root/fast_local/auth.json"

cleanup_benchmark_codex_homes() {
  case "$benchmark_codex_home_root" in
    "$benchmark_codex_home_parent"/*) ;;
    *) printf '격리 Codex 홈 정리 거부: %s\n' "$benchmark_codex_home_root" >&2; return 1 ;;
  esac
  if [[ -d "$benchmark_codex_home_root" ]]; then
    find "$benchmark_codex_home_root" -depth -mindepth 1 -delete
    rmdir -- "$benchmark_codex_home_root" 2>/dev/null || true
  fi
  rmdir -- "$benchmark_codex_home_parent" 2>/dev/null || true
}
trap cleanup_benchmark_codex_homes EXIT

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

printf '%s\n' "$source_path" > "$plain_scope/source-path.txt"
printf '%s\n' "$source_path" > "$fast_challenge/scope/source-path.txt"
printf '%s\n' "$category" > "$fast_challenge/.ctf-category"

prepare_pwn_runtime() {
  local input_dir=$1
  local work_dir=$2
  local image_ref=$3
  local log_file=$4
  local build_status=0
  local -a runtime_args=(--input "$input_dir" --output "$work_dir/runtime")

  if [[ -f "$input_dir/Dockerfile" ]]; then
    set +e
    "$agent_root/references/tools/pwn-build.sh" "$input_dir" "$image_ref" > "$log_file" 2>&1
    build_status=$?
    set -e
  fi
  if [[ $build_status -eq 0 ]] && docker image inspect "$image_ref" >/dev/null 2>&1; then
    runtime_args+=(--image "$image_ref")
  fi
  set +e
  "$agent_root/references/tools/pwn-runtime-prepare.sh" "${runtime_args[@]}" >> "$log_file" 2>&1
  set -e
}

prepare_category_image() {
  local input_dir=$1
  local image_ref=$2
  local log_file=$3
  [[ -f "$input_dir/Dockerfile" ]] || return 0
  set +e
  "$agent_root/references/tools/pwn-build.sh" "$input_dir" "$image_ref" > "$log_file" 2>&1
  local build_status=$?
  set -e
  return "$build_status"
}

if [[ "$category" == pwn ]]; then
  command -v docker >/dev/null 2>&1 || { echo 'pwn 벤치에는 Docker CLI가 필요합니다.' >&2; exit 69; }
  mkdir -p "$plain_work/runtime" "$fast_work/runtime"
  prepare_pwn_runtime "$plain_input" "$plain_work" "$plain_image" "$run_root/metrics/plain.runtime.log"
  prepare_pwn_runtime "$fast_input" "$fast_work" "$fast_image" "$run_root/metrics/fast_local.runtime.log"
else
  # A provided Dockerfile is prepared identically for both variants. Failure is
  # non-fatal: static analysis can continue and the exact blocker stays in logs.
  if [[ -f "$plain_input/Dockerfile" ]]; then
    command -v docker >/dev/null 2>&1 || { echo 'Dockerfile이 있는 벤치에는 Docker CLI가 필요합니다.' >&2; exit 69; }
    prepare_category_image "$plain_input" "$plain_image" "$run_root/metrics/plain.image.log" || true
    prepare_category_image "$fast_input" "$fast_image" "$run_root/metrics/fast_local.image.log" || true
  fi
fi
if [[ "$remote_enabled" == true ]]; then
  cp -a -- "$agent_root/references/tools/pwn-remote-run.sh" "$common_remote_harness"
  chmod +x "$common_remote_harness"
  printf 'authorization=user-supplied-ctf-endpoint\ntarget_network=exact-endpoint-only\nremote_host=%s\nremote_port=%s\nscoreboard=denied\n' \
    "$remote_host" "$remote_port" > "$plain_scope/benchmark.env"
  printf 'authorization=user-supplied-ctf-endpoint\ntarget_network=exact-endpoint-only\nremote_host=%s\nremote_port=%s\nscoreboard=denied\n' \
    "$remote_host" "$remote_port" > "$fast_challenge/scope/benchmark.env"
  for scope_file in "$plain_scope/remote-target.env" "$fast_challenge/scope/remote-target.env"; do
    {
    printf 'authorization=user-declared-official-ctf-endpoint\n'
    printf 'protocol=tcp\n'
    printf 'host=%s\nport=%s\n' "$remote_host" "$remote_port"
    printf 'attempt_policy=each-new-local-success-or-material-correction\n'
    printf 'attempt_limit=none\n'
    printf 'scoreboard_submission=denied\n'
    } > "$scope_file"
  done
else
  printf 'authorization=user-supplied-local-ctf-artifact\ntarget_network=denied\n' > "$plain_scope/benchmark.env"
  printf 'authorization=user-supplied-local-ctf-artifact\ntarget_network=denied\n' > "$fast_challenge/scope/benchmark.env"
  rm -f -- "$plain_scope/remote-target.env"
  rm -f -- "$fast_challenge/scope/remote-target.env"
fi

# FAST_LOCAL receives only the selected category knowledge and a concise policy.
ln -s "$agent_root/rules" "$fast_root/rules"
ln -s "$agent_root/references" "$fast_root/references"
ln -s "$agent_root/.agents" "$fast_root/.agents"
cp -a -- "$agent_root/state" "$fast_root/state"

case "$category" in
  pwn)
    ln -s "$agent_root/pwn-agent" "$fast_root/pwn-agent"
    cp -a -- "$agent_root/references/tools/pwntools-template.py" "$fast_work/solve.py"
    category_fast_rules=$(cat <<'EOF'
Read work/runtime/runtime.env first. Use supplied libc for remote offsets and an
exact ready pair for local execution. For incompatible manifests, use the image
libc/loader pair only for local structural validation and never mix the pairs.
Use the prepared pwntools template, one narrow source/checksec/symbol probe, and
one gadget index at most. Every newly local-successful solver version must run
immediately against the exact recorded endpoint. There is no global attempt
count, but never replay an unchanged exploit automatically, brute-force, or flood.
Only after a concrete blocker appears, read the one matching pwn-agent feedback
entry; do not preload the whole feedback history.
EOF
)
    ;;
  rev)
    ln -s "$agent_root/rev-agent" "$fast_root/rev-agent"
    category_fast_rules='Use the reversing Fast Probe: static map first, one ranked hypothesis at a time, and isolated Docker execution only when needed. Produce the smallest recover.py or solver and verify the derived flag.'
    ;;
  web)
    ln -s "$agent_root/web-agent" "$fast_root/web-agent"
    category_fast_rules='Use the web Fast Probe only against the supplied local challenge. Map the smallest route/state boundary, run the service and probes inside Docker isolation, and do not contact external hosts. Produce a minimal solve.py and verify the derived flag.'
    ;;
  crypto)
    category_fast_rules='Use references/categories/crypto.md. Identify the primitive and invariant with the cheapest mathematical test, implement the shortest solve.py, and verify by recomputation. Do not use unbounded brute force.'
    ;;
  forensics)
    category_fast_rules='Use references/categories/forensics.md. Preserve input evidence, inspect copies with bounded parsers, extract only decisive artifacts, and verify the flag derivation without external network access.'
    ;;
esac

cat > "$fast_root/AGENTS.md" <<EOF
# FAST_LOCAL $category benchmark

Solve the authorized $category CTF challenge directly. Do not narrate progress,
preload unrelated policy trees, write a report, browse the web, or use subagents.
Preserve the input and never execute untrusted challenge content on the host.

$category_fast_rules

When a flag is verified, print FLAG=<value>, write the exact word verified to
challenges/$challenge_name/work/.solved, make no more tool calls, and finish.
EOF

if [[ "$remote_enabled" == true ]]; then
  task_title="허가된 CTF pwn 문제 '$challenge_name'을 풀어 '$remote_host:$remote_port'에서 플래그를 구하라."
  remote_rule=$(cat <<EOF
- 원격은 정확히 TCP $remote_host:$remote_port 한 곳만 허용한다. 스캔, 다른 주소, scoreboard 접속은 금지한다.
- 정확한 로컬 런타임이 있으면 새 solver가 로컬에서 성공할 때마다 같은 버전을 즉시 원격 실행하라. 고정된 전체 시도 횟수 제한은 없다.
- 로컬 실행이 불가능하면 정적 교차 확인을 통과한 첫 버전과 이후 실질적으로 수정된 버전을 원격 실행하라. 변경 없는 exploit 자동 반복·무차별 대입·병렬 flood는 금지한다.
- 문제 바이너리는 호스트에서 실행하지 마라. 직접 작성한 원격 client는 정확한 허가 endpoint에 한해 호스트에서 실행해도 된다.
- 각 로컬 성공 또는 실질적 수정 직후 문법 검사와 해당 원격 실행을 한 shell command로 결합하라. 하니스가 REMOTE/HOST/PORT 인자를 자동으로 덧붙인다.
  python3 -m py_compile <solver.py> && "\$CTF_REMOTE_HARNESS" --host "\$CTF_REMOTE_HOST" --port "\$CTF_REMOTE_PORT" --timeout 30 --attempts 1 --output "\$CTF_REMOTE_TRANSCRIPT" -- python3 <solver.py> [필요한 정적 BIN 인자]
- solver는 실제 원격 응답에서 플래그를 얻었을 때만 \`FLAG=<원문>\` 한 줄을 출력하고 즉시 종료해야 한다.
- 플래그를 받으면 하니스 출력 직후 모든 검증, writeup, \`.solved\` 작업과 추가 설명을 중단하고 한 줄로 종료하라. 실패하면 원인만 짧게 보고하라.
EOF
)
  plain_execution_rule=$remote_rule
  fast_execution_rule=$remote_rule
else
  task_title="허가된 로컬 CTF $category 문제 '$challenge_name'을 풀어 플래그를 구하라."
  plain_execution_rule='- 대상 네트워크 접속은 금지한다. challenge 실행은 Docker 격리 안에서만 수행하라.
- exploit로 플래그를 재현한 경우 work/.solved에 verified 한 줄을 기록하라.'
  fast_execution_rule="- 대상 네트워크 접속은 금지한다. challenge 실행은 Docker 격리 안에서만 수행하라.
- exploit로 플래그를 재현한 경우 challenges/$challenge_name/work/.solved에 verified 한 줄을 기록하라."
fi

case "$category" in
  pwn) fast_artifact_rule="- 준비된 pwntools 골격 challenges/$challenge_name/work/solve.py를 가장 짧은 문제 전용 exploit으로 수정하라." ;;
  rev) fast_artifact_rule="- 최소 복원기 또는 solver를 challenges/$challenge_name/work/recover.py에 작성하라." ;;
  web|crypto|forensics) fast_artifact_rule="- 최소 재현 solver를 challenges/$challenge_name/work/solve.py에 작성하라." ;;
esac

cat > "$run_root/plain.prompt.txt" <<EOF
$task_title

- 입력은 input/이다. 원본은 수정하지 마라.
- 그냥 바로 풀어라. 중간 설명 없이 필요한 명령을 실행하고, CTF 스킬·에이전트·정책 문서를 읽거나 진행 기록과 writeup을 만들지 마라.
- 필요한 exploit은 work/solve.py에 작성하라. 서브에이전트는 사용하지 마라.
$plain_execution_rule
EOF

cat > "$run_root/fast-local.prompt.txt" <<EOF
$task_title

- 입력은 challenges/$challenge_name/input이다. 원본은 수정하지 마라.
- 그냥 바로 풀어라. 중간 설명 없이 AGENTS.md의 단일 조사 fast path를 따르고, 막힌 증상과 정확히 맞는 피드백 하나만 필요할 때 확인하라.
$fast_artifact_rule 서브에이전트는 사용하지 마라.
$fast_execution_rule
EOF

# Keep the actual benchmark request deliberately short. Category behavior is
# supplied by FAST_LOCAL's AGENTS.md; the plain baseline receives only the same
# authorization, isolation and success contract.
case "$category" in
  pwn) fast_artifact_rule="준비된 challenges/$challenge_name/work/solve.py 골격을 문제 전용 exploit으로 최소 수정하라." ;;
  rev) fast_artifact_rule="최소 복원기 또는 solver를 challenges/$challenge_name/work/recover.py에 작성하라." ;;
  web|crypto|forensics) fast_artifact_rule="최소 재현 solver를 challenges/$challenge_name/work/solve.py에 작성하라." ;;
esac
if [[ "$remote_enabled" == true ]]; then
  common_execution=$(cat <<EOF
허용된 원격은 TCP $remote_host:$remote_port 하나뿐이다. 다른 주소와 scoreboard에는 접속하지 마라.
로컬에서 새 exploit 버전이 성공할 때마다 같은 버전을 즉시 원격에 동기화하라. 고정된 총 시도 제한은 없지만 변경 없는 자동 재시도, 무차별 대입, flood는 금지한다.
각 동기화는 다음 하니스로 1회 실행하라. 실제 원격 응답에서 플래그를 받으면 FLAG=<값>을 출력하고 추가 검증이나 도구 호출 없이 즉시 끝내라.
python3 -m py_compile <solver.py> && "\$CTF_REMOTE_HARNESS" --host "\$CTF_REMOTE_HOST" --port "\$CTF_REMOTE_PORT" --timeout 30 --attempts 1 --output "\$CTF_REMOTE_TRANSCRIPT" -- python3 <solver.py>
EOF
)
else
  common_execution='외부 네트워크에는 접속하지 말고, 문제 실행은 제공된 Docker 이미지 안에서만 수행하라. 플래그를 검증하면 work/.solved에 verified를 기록하고 즉시 끝내라.'
fi

cat > "$run_root/plain.prompt.txt" <<EOF
허가된 $category CTF 문제 '$challenge_name'을 그냥 바로 풀어라.
입력은 input/이며 원본을 수정하지 마라. 웹 검색, writeup 작성, 서브에이전트, 장황한 진행 설명은 사용하지 마라.
필요한 solver는 work/에 작성하고, 호스트에서 신뢰할 수 없는 문제 파일을 실행하지 마라.
$common_execution
EOF

cat > "$run_root/fast-local.prompt.txt" <<EOF
허가된 $category CTF 문제 '$challenge_name'을 그냥 바로 풀어라.
입력은 challenges/$challenge_name/input이며 원본을 수정하지 마라. AGENTS.md의 짧은 fast path만 따르고 웹 검색, writeup 작성, 서브에이전트, 장황한 진행 설명은 사용하지 마라.
$fast_artifact_rule
$common_execution
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
  # Background function subshells must not run the parent's shared cleanup
  # while the other benchmark variant is still using its isolated home.
  trap - EXIT
  local key=$1
  local label=$2
  local workspace=$3
  local work_dir=$4
  local prompt_file=$5
  local docker_image=$6
  local events_file="$run_root/metrics/$key.events.jsonl"
  local stderr_file="$run_root/metrics/$key.stderr.log"
  local status_file="$run_root/metrics/$key.status"
  local isolated_codex_home="$benchmark_codex_home_root/$key"
  local fifo_dir fifo_file
  local started_ns ended_ns duration_ms codex_status capture_status codex_pid
  local -a capture_options=(--label "$label" --output "$events_file" --quiet)
  local -a runtime_env=()
  local -a launch_prefix=(setsid --wait)

  if [[ "$category" == pwn && -f "$work_dir/runtime/runtime.env" ]]; then
    local runtime_status=unavailable libc_path= ld_path= local_libc_path= local_ld_path= target_path=
    # This file is generated by our own runtime helper using shell-safe quoting.
    # It selects supplied libc for remote calculations and an exact image pair
    # for local structural replay when the two runtimes differ.
    # shellcheck disable=SC1090
    source "$work_dir/runtime/runtime.env"
    runtime_env+=(
      "CTF_PWN_RUNTIME_DIR=$work_dir/runtime"
      "CTF_PWN_RUNTIME_STATUS=$runtime_status"
      "CTF_PWN_RUNTIME_MANIFEST=$work_dir/runtime/runtime.env"
      "CTF_PWN_IMAGE=$docker_image"
      "CTF_PWN_RUNNER=$agent_root/references/tools/pwn-run.sh"
    )
    [[ -z "$target_path" ]] || runtime_env+=("CTF_PWN_BINARY_PATH=$target_path")
    [[ -z "$libc_path" ]] || runtime_env+=("CTF_PWN_LIBC_PATH=$libc_path")
    [[ -z "$ld_path" ]] || runtime_env+=("CTF_PWN_LD_PATH=$ld_path")
    [[ -z "$local_libc_path" ]] || runtime_env+=("CTF_PWN_LOCAL_LIBC_PATH=$local_libc_path")
    [[ -z "$local_ld_path" ]] || runtime_env+=("CTF_PWN_LOCAL_LD_PATH=$local_ld_path")
  fi

  if (( timeout_seconds > 0 )); then
    launch_prefix+=(timeout --foreground --signal=INT --kill-after=30s "${timeout_seconds}s")
  fi

  if [[ "$remote_enabled" == true ]]; then
    capture_options+=(--stop-on-flag)
    if [[ "$exact_tokens" == true ]]; then
      capture_options+=(--usage-grace "$usage_grace_seconds")
    fi
  fi

  while [[ ! -e "$start_gate" ]]; do
    sleep 0.01
  done
  started_ns=$(date +%s%N)
  fifo_dir=$(mktemp -d "${TMPDIR:-/tmp}/ctf-bench-${run_id}-${key}.XXXXXX")
  fifo_file="$fifo_dir/events.fifo"
  mkfifo -- "$fifo_file"
  set +e
  "${launch_prefix[@]}" \
    env CODEX_HOME="$isolated_codex_home" \
      CTF_AGENT_ROOT="$workspace" CTF_BENCH_WORK_DIR="$work_dir" \
      CTF_BENCH_CATEGORY="$category" \
      CTF_BENCH_DOCKER_IMAGE="$docker_image" CTF_BENCH_REMOTE="$remote_enabled" \
      CTF_REMOTE_HOST="$remote_host" CTF_REMOTE_PORT="$remote_port" \
      CTF_REMOTE_HARNESS="$common_remote_harness" \
      CTF_REMOTE_TRANSCRIPT="$work_dir/remote-transcript.txt" \
      "${runtime_env[@]}" \
    "$codex_bin" exec --ephemeral --ignore-user-config --skip-git-repo-check \
      -C "$workspace" --model "$model" \
      -c "model_reasoning_effort=\"$reasoning_effort\"" \
      -c 'service_tier="fast"' --enable fast_mode \
      -c 'approval_policy="never"' \
      --disable multi_agent --disable skill_search \
      --disable browser_use --disable browser_use_external \
      --disable browser_use_full_cdp_access --disable in_app_browser \
      --disable standalone_web_search \
      --sandbox danger-full-access --json - \
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
