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

pwn 기본 조작법:
  ctf-bench-pwn <문제 이름> <서버 주소:포트>

같은 카테고리의 로컬 CTF 문제를 LUNA, TERRA, SOL 세 모델로 병렬 실행하고
먼저 검증된 플래그를 출력한 모델을 승자로 확정한 뒤 나머지를 종료합니다.

옵션:
  --source PATH       문제 원본 디렉터리 또는 ZIP 파일
  --timeout SECONDS   명시적 실행 제한 시간(기본 0: 자동 종료 없음)
  --remote HOST:PORT  pwn 전용 허가 원격 엔드포인트(정확히 이 주소만 허용)
  --exact-tokens      최종 usage 대기(기본값이며 이전 버전 호환 옵션)
  --no-exact-tokens   플래그 즉시 종료를 우선하고 미도착 토큰은 미집계
  --extra-prompt      시작 직전에 세 모델에 넣을 여러 줄 지시 입력(.end로 종료)
  --verbose           세 모델의 의미 있는 행동 로그 표시(기본값; CTF_BENCH_QUIET=true로 억제)
  --order ORDER       이전 버전 호환 옵션이며 병렬 모드에서는 무시
  --dry-run           실행 경로와 고정 설정만 확인
  -h, --help          도움말

고정된 공정성 설정:
  models              gpt-5.6-luna, gpt-5.6-terra, gpt-5.6-sol
  reasoning effort    max
  service tier        fast
  subagents           enabled (cooperative, flag-first)
  automatic skills    세 모델 모두 선택된 category Agent/skill 사용
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
  CTF_BENCH_MEMORY_HIGH_MB 실행별 memory pressure 기준(기본 1536)
  CTF_BENCH_MEMORY_MAX_MB  실행별 최대 메모리(기본 2048)
  CTF_BENCH_MIN_HOST_FREE_MB 시작에 필요한 Windows 여유 공간(기본 61440)
  CTF_BENCH_TRIM_INTERVAL_SECONDS 실행 중 fstrim 간격(기본 120, 0=비활성)
  CTF_EXTRA_PROMPT    대화형 입력 없이 두 변형에 공통으로 추가할 프롬프트
EOF
}

source_override=
timeout_seconds=${CTF_BENCH_TIMEOUT_SECONDS:-0}
run_order=plain-first
remote_endpoint=
dry_run=false
exact_tokens=true
ask_extra_prompt=false
quiet_output=${CTF_BENCH_QUIET:-false}
extra_prompt=${CTF_EXTRA_PROMPT:-}
usage_grace_seconds=${CTF_BENCH_USAGE_GRACE_SECONDS:-45}
memory_high_mb=${CTF_BENCH_MEMORY_HIGH_MB:-1536}
memory_max_mb=${CTF_BENCH_MEMORY_MAX_MB:-2048}
min_host_free_mb=${CTF_BENCH_MIN_HOST_FREE_MB:-61440}
trim_interval_seconds=${CTF_BENCH_TRIM_INTERVAL_SECONDS:-120}
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
    --no-exact-tokens) exact_tokens=false ;;
    --extra-prompt) ask_extra_prompt=true ;;
    --verbose) quiet_output=false ;;
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
[[ "$memory_high_mb" =~ ^[0-9]+$ && "$memory_max_mb" =~ ^[0-9]+$ ]] || { echo '벤치 메모리 값은 정수여야 합니다.' >&2; exit 65; }
(( memory_high_mb >= 512 && memory_max_mb >= memory_high_mb )) || { echo '메모리는 512MiB 이상이며 HIGH <= MAX여야 합니다.' >&2; exit 65; }
[[ "$min_host_free_mb" =~ ^[0-9]+$ && "$trim_interval_seconds" =~ ^[0-9]+$ ]] || { echo '벤치 저장공간 보호 값은 0 이상의 정수여야 합니다.' >&2; exit 65; }
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
  rev) source_root=${CTF_REV_SOURCE:-$HOME/ctf-challenges/rev} ;;
  web) source_root=${CTF_WEB_SOURCE:-$HOME/ctf-challenges/web} ;;
  crypto) source_root=${CTF_CRYPTO_SOURCE:-$HOME/ctf-challenges/crypto} ;;
  forensics) source_root=${CTF_FORENSICS_SOURCE:-$HOME/ctf-challenges/forensics} ;;
esac
bench_root=${CTF_BENCH_ROOT:-$agent_root/benchmarks}
metrics_py="$script_dir/ctf-bench-metrics.py"
extra_prompt_tool="$script_dir/ctf-extra-prompt.sh"
codex_bin=${CODEX_BIN:-}
source_codex_home=${CODEX_HOME:-$HOME/.codex}
model_luna=gpt-5.6-luna
model_terra=gpt-5.6-terra
model_sol=gpt-5.6-sol
reasoning_effort=max

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
[[ -x "$extra_prompt_tool" ]] || { printf '공통 추가 프롬프트 도구가 없습니다: %s\n' "$extra_prompt_tool" >&2; exit 66; }
if [[ "$category" == pwn ]]; then
  [[ -f "$agent_root/references/tools/pwntools-template.py" ]] || { echo 'pwntools solver 템플릿이 없습니다.' >&2; exit 66; }
elif [[ "$category" == rev ]]; then
  [[ -x "$agent_root/references/tools/rev-intake-check.sh" ]] || { echo 'rev intake 도구가 없습니다.' >&2; exit 66; }
  [[ -x "$agent_root/references/tools/rev-run.sh" ]] || { echo 'rev Docker runner가 없습니다.' >&2; exit 66; }
  [[ -f "$agent_root/references/tools/rev-recover-template.py" ]] || { echo 'rev 복원기 템플릿이 없습니다.' >&2; exit 66; }
fi

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin="$(command -v codex 2>/dev/null || true)"
fi

if [[ "$ask_extra_prompt" == true ]]; then
  extra_prompt=$("$extra_prompt_tool" --interactive)
fi

if [[ "$dry_run" == true ]]; then
  printf '문제:             %s\n' "$challenge_name"
  printf '카테고리:         %s\n' "$category"
  printf '원본:             %s\n' "$source_path"
  printf '결과 루트:        %s\n' "$bench_root"
  printf '실행 방식:        LUNA max + TERRA max + SOL max 병렬 경쟁\n'
  if [[ "$remote_enabled" == true ]]; then
    printf '원격 엔드포인트:  %s:%s (이 주소만 허용)\n' "$remote_host" "$remote_port"
    printf '성공 판정:        원격 하니스 플래그 포착 즉시 성공 및 종료\n'
  elif [[ "$category" == rev ]]; then
    printf '성공 판정:        독립 복원 또는 격리 검증 + .solved=verified\n'
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
  printf '모델:             %s / %s / %s\n' "$model_luna" "$model_terra" "$model_sol"
  printf '추론 강도:        %s\n' "$reasoning_effort"
  printf '서비스 등급:      fast (fast_mode)\n'
  printf '웹 탐색:          비활성화\n'
  printf '서브에이전트:     활성화(features.multi_agent=true)\n'
  printf '스킬 구성:        세 모델 모두 ctf-%s 오케스트레이터·스킬·피드백 사용\n' "$category"
  printf '플래그 경쟁:      첫 검증 플래그 즉시 로그 출력·나머지 모델 종료\n'
  printf '후보 협업:        run_root/collab/candidates 공유, 플래그 전 후보만 교환\n'
  printf 'Docker 구성:      이미지 1회 준비·공유, 모델별 독립 --rm 컨테이너\n'
  printf 'Docker 캐시:      문제별 공용 이미지 1개 유지, 이전 교체본과 실행 컨테이너 정리\n'
  printf '실행별 메모리:    high=%sMiB max=%sMiB\n' "$memory_high_mb" "$memory_max_mb"
  printf '저장공간 보호:    시작 여유 %sMiB, 실행 중 trim 간격 %s초\n' "$min_host_free_mb" "$trim_interval_seconds"
  printf '세션 저장:        비활성화(--ephemeral)\n'
  printf '토큰 집계:        플래그 우선 즉시 종료; 도착한 usage만 집계\n'
  printf '추가 프롬프트:    %s\n' "$([[ -n "$extra_prompt" ]] && printf '지정됨(세 모델 동일 적용)' || printf '없음')"
  exit 0
fi

[[ -n "$codex_bin" && -x "$codex_bin" ]] || { echo 'Codex CLI를 사용할 수 없습니다.' >&2; exit 69; }
command -v python3 >/dev/null 2>&1 || { echo 'python3가 필요합니다.' >&2; exit 69; }
if (( timeout_seconds > 0 )); then
  command -v timeout >/dev/null 2>&1 || { echo '명시적 --timeout 사용에는 GNU timeout이 필요합니다.' >&2; exit 69; }
fi
command -v setsid >/dev/null 2>&1 || { echo 'util-linux setsid가 필요합니다.' >&2; exit 69; }
if [[ "$category" == pwn ]]; then
  command -v systemd-run >/dev/null 2>&1 || { echo 'pwn 벤치 메모리 제한에는 systemd-run이 필요합니다.' >&2; exit 69; }
  systemctl --user is-system-running >/dev/null 2>&1 || { echo '사용자 systemd manager가 실행 중이어야 합니다.' >&2; exit 69; }
fi
command -v mkfifo >/dev/null 2>&1 || { echo 'mkfifo가 필요합니다.' >&2; exit 69; }
command -v mktemp >/dev/null 2>&1 || { echo 'mktemp가 필요합니다.' >&2; exit 69; }
command -v find >/dev/null 2>&1 || { echo 'find가 필요합니다.' >&2; exit 69; }
[[ -f "$source_codex_home/auth.json" ]] || { printf 'Codex 인증 파일을 찾을 수 없습니다: %s\n' "$source_codex_home/auth.json" >&2; exit 69; }

if [[ "$category" == pwn && -d /mnt/c ]]; then
  if [[ -x /usr/sbin/fstrim ]] && command -v sudo >/dev/null 2>&1; then
    sudo -n /usr/sbin/fstrim -av >/dev/null 2>&1 || true
  fi
  host_free_mb=$(df -Pm /mnt/c | awk 'NR == 2 {print $4}')
  if [[ "$host_free_mb" =~ ^[0-9]+$ ]] && (( host_free_mb < min_host_free_mb )); then
    printf '벤치마크 시작 거부: Windows 여유 공간이 %sMiB이며 최소 %sMiB가 필요합니다.\n' "$host_free_mb" "$min_host_free_mb" >&2
    printf 'CTF_BENCH_MIN_HOST_FREE_MB로 기준을 조정할 수 있지만 디스크 0GB 재발 위험이 있습니다.\n' >&2
    exit 78
  fi
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_root="$bench_root/runs/$category/$run_id"
luna_root="$run_root/luna"
terra_root="$run_root/terra"
sol_root="$run_root/sol"
luna_input="$luna_root/challenges/$challenge_name/input"
terra_challenge="$terra_root/challenges/$challenge_name"
terra_input="$terra_challenge/input"
terra_work="$terra_challenge/work"
sol_challenge="$sol_root/challenges/$challenge_name"
sol_input="$sol_challenge/input"
sol_work="$sol_challenge/work"
plain_root="$luna_root"
fast_root="$terra_root"
plain_input="$luna_input"
plain_work="$luna_root/challenges/$challenge_name/work"
plain_scope="$luna_root/challenges/$challenge_name/scope"
plain_evidence="$luna_root/challenges/$challenge_name/evidence/private"
fast_challenge="$terra_challenge"
fast_input="$terra_input"
fast_work="$terra_work"
common_tools="$run_root/tools"
common_remote_harness="$common_tools/pwn-remote-run.sh"
common_docker_runner="$common_tools/$category-run.sh"
common_collab_tool="$common_tools/ctf-bench-collab.sh"
collab_dir="$run_root/collab"
common_web_runtime="$common_tools/web-runtime.sh"
common_web_probe="$common_tools/web-blackbox-probe.py"
common_web_request="$common_tools/web-request.py"
common_web_template="$common_tools/web-solve-template.py"
web_runtime_state="$terra_work/web-runtime.env"
web_runtime_ready=false
web_runtime_endpoint=
plain_tools="$luna_root/tools"
plain_remote_harness="$plain_tools/pwn-remote-run.sh"
plain_docker_runner="$plain_tools/$category-run.sh"
sol_tools="$sol_root/tools"
sol_remote_harness="$sol_tools/pwn-remote-run.sh"
sol_docker_runner="$sol_tools/$category-run.sh"
image_slug=$(printf '%s' "$challenge_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')
shared_image="ctf-bench-cache-$category-$image_slug:local"
shared_image_ready=false
shared_image_id_before=
benchmark_codex_home_parent="${XDG_CACHE_HOME:-$HOME/.cache}/ctf-bench-codex-homes"
benchmark_codex_home_root="$benchmark_codex_home_parent/$run_id"
trim_watchdog_pid=

mkdir -p "$plain_input" "$plain_work" "$plain_scope" "$plain_evidence" "$plain_tools" \
  "$fast_input" "$fast_work" "$fast_challenge/evidence/private" \
  "$fast_challenge/scope" "$sol_input" "$sol_work" "$sol_challenge/evidence/private" \
  "$sol_challenge/scope" "$sol_tools" "$run_root/metrics" "$common_tools" "$collab_dir/candidates" \
  "$benchmark_codex_home_root/luna" "$benchmark_codex_home_root/terra" "$benchmark_codex_home_root/sol"
chmod 700 "$benchmark_codex_home_root" \
  "$benchmark_codex_home_root/luna" "$benchmark_codex_home_root/terra" "$benchmark_codex_home_root/sol"
cp -a -- "$agent_root/references/tools/ctf-bench-collab.sh" "$common_collab_tool"
chmod +x "$common_collab_tool"
ln -s -- "$source_codex_home/auth.json" "$benchmark_codex_home_root/luna/auth.json"
ln -s -- "$source_codex_home/auth.json" "$benchmark_codex_home_root/terra/auth.json"
ln -s -- "$source_codex_home/auth.json" "$benchmark_codex_home_root/sol/auth.json"

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

trim_wsl_free_blocks() {
  [[ "$category" == pwn || "$category" == rev ]] || return 0
  [[ ${CTF_BENCH_AUTO_TRIM:-true} == true ]] || return 0
  [[ -x /usr/sbin/fstrim ]] || return 0
  command -v sudo >/dev/null 2>&1 || return 0

  if sudo -n /usr/sbin/fstrim -av >/dev/null 2>&1; then
    [[ "$quiet_output" == true ]] || printf 'WSL 빈 블록 반환: 완료\n'
  else
    [[ "$quiet_output" == true ]] || printf 'WSL 빈 블록 반환: 건너뜀 (fstrim 권한 또는 파일시스템 상태 확인 필요)\n' >&2
  fi
}

start_trim_watchdog() {
  [[ "$category" == pwn || "$category" == rev ]] || return 0
  (( trim_interval_seconds > 0 )) || return 0
  [[ -x /usr/sbin/fstrim ]] || return 0
  command -v sudo >/dev/null 2>&1 || return 0
  sudo -n -l /usr/sbin/fstrim -av >/dev/null 2>&1 || return 0

  (
    trap - EXIT INT TERM HUP
    while sleep "$trim_interval_seconds"; do
      sudo -n /usr/sbin/fstrim -av >/dev/null 2>&1 || true
    done
  ) &
  trim_watchdog_pid=$!
}

stop_trim_watchdog() {
  [[ -n "$trim_watchdog_pid" ]] || return 0
  kill -TERM "$trim_watchdog_pid" 2>/dev/null || true
  wait "$trim_watchdog_pid" 2>/dev/null || true
  trim_watchdog_pid=
}

cleanup_plain_workspace() {
  # Competition workspaces live below the retained run directory so that all
  # three model transcripts and artifacts remain auditable. Docker/runtime
  # cleanup is handled separately; never delete a participant workspace here.
  return 0
}

docker_tracking=false
declare -A docker_container_baseline=()
declare -A docker_image_baseline=()

snapshot_benchmark_docker_resources() {
  local resource_id
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  docker_tracking=true
  shared_image_id_before=$(docker image inspect --format '{{.Id}}' "$shared_image" 2>/dev/null || true)
  while IFS= read -r resource_id; do
    [[ -z "$resource_id" ]] || docker_container_baseline["$resource_id"]=1
  done < <(docker ps -aq)
  while IFS= read -r resource_id; do
    [[ -z "$resource_id" ]] || docker_image_baseline["$resource_id"]=1
  done < <(docker image ls -aq --no-trunc)
}

cleanup_benchmark_docker_resources() {
  [[ "$docker_tracking" == true ]] || return 0
  docker info >/dev/null 2>&1 || return 0

  local resource_id current_shared_image_id removed_containers=0 removed_images=0
  local -a current_containers=() current_images=()
  mapfile -t current_containers < <(docker ps -aq)
  for resource_id in "${current_containers[@]}"; do
    [[ -n "$resource_id" && -z "${docker_container_baseline[$resource_id]+present}" ]] || continue
    if docker rm -f -- "$resource_id" >/dev/null 2>&1; then
      removed_containers=$((removed_containers + 1))
    fi
  done

  # Keep exactly one stable shared image for the next run. Docker images are
  # immutable, so both variants can safely create independent containers from
  # it. If this run replaced an older cache image, remove the now-dangling old
  # image rather than accumulating one full image per benchmark execution.
  current_shared_image_id=$(docker image inspect --format '{{.Id}}' "$shared_image" 2>/dev/null || true)
  if [[ -n "$shared_image_id_before" && "$shared_image_id_before" != "$current_shared_image_id" ]]; then
    if docker image rm -- "$shared_image_id_before" >/dev/null 2>&1; then
      removed_images=$((removed_images + 1))
    fi
  fi

  # Legacy Docker builds may leave untagged intermediate images. Remove only
  # IDs absent from the pre-run snapshot; never prune pre-existing resources.
  mapfile -t current_images < <(docker image ls -aq --no-trunc | sort -u)
  for resource_id in "${current_images[@]}"; do
    [[ -z "$current_shared_image_id" || "$resource_id" != "$current_shared_image_id" ]] || continue
    [[ -n "$resource_id" && -z "${docker_image_baseline[$resource_id]+present}" ]] || continue
    if docker image inspect "$resource_id" >/dev/null 2>&1 &&
       docker image rm -f -- "$resource_id" >/dev/null 2>&1; then
      removed_images=$((removed_images + 1))
    fi
  done

  if (( removed_containers > 0 || removed_images > 0 )); then
    [[ "$quiet_output" == true ]] || printf 'benchmark Docker 정리: containers=%d images=%d\n' "$removed_containers" "$removed_images"
  fi
  if [[ -n "$current_shared_image_id" ]]; then
    [[ "$quiet_output" == true ]] || printf 'benchmark Docker 캐시 유지: %s\n' "$shared_image"
  fi
}

cleanup_benchmark_run() {
  local status=$?
  trap - EXIT
  if [[ "$web_runtime_ready" == true && -f "$web_runtime_state" ]]; then
    "$common_web_runtime" down --state "$web_runtime_state" >/dev/null 2>&1 || true
  fi
  stop_trim_watchdog || true
  cleanup_benchmark_docker_resources || true
  cleanup_benchmark_codex_homes || true
  cleanup_plain_workspace || true
  trim_wsl_free_blocks || true
  exit "$status"
}

snapshot_benchmark_docker_resources
trap cleanup_benchmark_run EXIT
start_trim_watchdog

copy_source() {
  local destination=$1
  if [[ -d "$source_path" ]]; then
    cp -a -- "$source_path"/. "$destination"/
  elif [[ "$source_path" == *.zip ]]; then
    command -v unzip >/dev/null 2>&1 || { echo 'ZIP 문제에는 unzip이 필요합니다.' >&2; return 69; }
    unzip -q -o -- "$source_path" -d "$destination"
  else
    cp -a -- "$source_path" "$destination"/
  fi
}
copy_source "$plain_input"
copy_source "$fast_input"
copy_source "$sol_input"

printf '%s\n' "$source_path" > "$plain_scope/source-path.txt"
printf '%s\n' "$source_path" > "$fast_challenge/scope/source-path.txt"
printf '%s\n' "$source_path" > "$sol_challenge/scope/source-path.txt"
printf '%s\n' "$category" > "$fast_challenge/.ctf-category"
printf '%s\n' "$category" > "$sol_challenge/.ctf-category"

prepare_shared_image() {
  local input_dir=$1
  local log_file=$2
  local build_status

  [[ -f "$input_dir/Dockerfile" ]] || return 0
  [[ "$quiet_output" == true ]] || printf '공용 Docker 이미지 준비 중: %s\n' "$shared_image"
  set +e
  # Re-evaluate the current Docker context on every run while allowing Docker
  # to reuse unchanged layers from the stable shared tag.
  "$agent_root/references/tools/pwn-build.sh" --rebuild "$input_dir" "$shared_image" > "$log_file" 2>&1
  build_status=$?
  set -e
  if [[ $build_status -eq 0 ]] && docker image inspect "$shared_image" >/dev/null 2>&1; then
    shared_image_ready=true
    [[ "$quiet_output" == true ]] || printf '공용 Docker 이미지 준비 완료: LUNA/TERRA/SOL이 %s를 공유합니다.\n' "$shared_image"
  else
    shared_image_ready=false
    printf '공용 Docker 이미지 준비 실패: 정적 분석은 계속합니다. 로그=%s\n' "$log_file" >&2
  fi
  {
    printf 'image_ref=%q\n' "$shared_image"
    printf 'build_status=%s\n' "$build_status"
    printf 'ready=%s\n' "$shared_image_ready"
    printf 'container_policy=independent-disposable-per-model\n'
  } > "$run_root/metrics/docker-shared.env"
  return "$build_status"
}

prepare_pwn_runtime() {
  local input_dir=$1
  local work_dir=$2
  local image_ref=$3
  local image_ready=$4
  local log_file=$5
  local -a runtime_args=(--input "$input_dir" --output "$work_dir/runtime")

  if [[ "$image_ready" == true ]] && docker image inspect "$image_ref" >/dev/null 2>&1; then
    runtime_args+=(--image "$image_ref")
  fi
  set +e
  "$agent_root/references/tools/pwn-runtime-prepare.sh" "${runtime_args[@]}" > "$log_file" 2>&1
  set -e
}

if [[ "$category" == pwn ]]; then
  mkdir -p "$fast_work/runtime"
  cp -a -- "$agent_root/references/tools/pwn-run.sh" "$common_docker_runner"
  cp -a -- "$agent_root/references/tools/pwn-run.sh" "$plain_docker_runner"
  cp -a -- "$agent_root/references/tools/pwn-run.sh" "$sol_docker_runner"
  chmod +x "$common_docker_runner" "$plain_docker_runner" "$sol_docker_runner"
  if [[ -f "$fast_input/Dockerfile" ]]; then
    command -v docker >/dev/null 2>&1 || { echo 'Dockerfile이 있는 pwn 벤치에는 Docker CLI가 필요합니다.' >&2; exit 69; }
    prepare_shared_image "$fast_input" "$run_root/metrics/shared-image.log" || true
  fi
  # Match ctf-pwn intake/checkpoint preparation for every competitor while
  # keeping each generated work directory independent.
  intake_log="$run_root/metrics/pwn-intake-exec.txt"
  "$agent_root/references/tools/pwn-intake-check.sh" "$fast_input" > "$intake_log" 2>/dev/null || true
  for work_dir in "$plain_work" "$fast_work" "$sol_work"; do
    cp -f -- "$intake_log" "$work_dir/intake-exec.txt"
  done
  prepare_pwn_runtime "$fast_input" "$fast_work" "$shared_image" "$shared_image_ready" "$run_root/metrics/terra.runtime.log"
  if [[ -d "$fast_work/runtime" ]]; then
    rm -rf -- "$plain_work/runtime" "$sol_work/runtime"
    cp -a -- "$fast_work/runtime" "$plain_work/runtime"
    cp -a -- "$fast_work/runtime" "$sol_work/runtime"
  fi
  for participant_root in "$luna_root" "$terra_root" "$sol_root"; do
    CTF_AGENT_ROOT="$participant_root" "$agent_root/references/tools/pwn-checkpoint.sh" \
      "$challenge_name" setup active 'mode=adaptive benchmark=ctf-pwn' >/dev/null 2>&1 || true
  done
elif [[ "$category" == rev ]]; then
  # Build the supplied image once. All three models receive the same image,
  # but each dynamic probe runs in its own disposable, network-disabled container.
  cp -a -- "$agent_root/references/tools/rev-run.sh" "$common_docker_runner"
  cp -a -- "$agent_root/references/tools/rev-run.sh" "$plain_docker_runner"
  cp -a -- "$agent_root/references/tools/rev-run.sh" "$sol_docker_runner"
  cp -a -- "$agent_root/references/tools/rev-fast-probe.sh" "$run_root/tools/rev-fast-probe.sh"
  chmod +x "$common_docker_runner" "$plain_docker_runner" "$sol_docker_runner" "$run_root/tools/rev-fast-probe.sh"
  if [[ -f "$fast_input/Dockerfile" ]]; then
    command -v docker >/dev/null 2>&1 || { echo 'Dockerfile이 있는 rev 벤치에는 Docker CLI가 필요합니다.' >&2; exit 69; }
    prepare_shared_image "$fast_input" "$run_root/metrics/shared-image.log" || true
  fi
  intake_log="$run_root/metrics/rev-intake-exec.txt"
  "$agent_root/references/tools/rev-intake-check.sh" "$fast_input" > "$intake_log"
  for root in "$luna_root" "$terra_root" "$sol_root"; do
    work_dir="$root/challenges/$challenge_name/work"
    cp -f -- "$intake_log" "$work_dir/intake-exec.txt"
    cp -a -- "$agent_root/references/tools/rev-recover-template.py" "$work_dir/recover.py"
    ln -sfn "challenges/$challenge_name/input" "$root/input"
    ln -sfn "challenges/$challenge_name/work" "$root/work"
  done
  cp -a -- "$agent_root/references/tools/rev-flag-success.sh" "$common_tools/rev-flag-success.sh"
  chmod +x "$common_tools/rev-flag-success.sh"
elif [[ "$category" == web ]]; then
  cp -a -- "$agent_root/references/tools/web-runtime.sh" "$common_web_runtime"
  cp -a -- "$agent_root/references/tools/web-blackbox-probe.py" "$common_web_probe"
  cp -a -- "$agent_root/references/tools/web-request.py" "$common_web_request"
  cp -a -- "$agent_root/references/tools/web-solve-template.py" "$common_web_template"
  chmod +x "$common_web_runtime"
  web_runtime_input=false
  for runtime_file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml Dockerfile; do
    [[ -f "$terra_input/$runtime_file" ]] && web_runtime_input=true
  done
  if [[ "$web_runtime_input" == true ]]; then
    command -v docker >/dev/null 2>&1 || { echo 'Web runtime에는 Docker CLI가 필요합니다.' >&2; exit 69; }
    web_project="ctf_bench_${image_slug//[^a-zA-Z0-9]/_}"
    set +e
    "$common_web_runtime" up --input "$terra_input" --work "$terra_work" \
      --project "$web_project" --image "$shared_image" > "$run_root/metrics/web-runtime.log" 2>&1
    web_runtime_status=$?
    set -e
    if [[ $web_runtime_status -eq 0 && -f "$web_runtime_state" ]]; then
      # shellcheck disable=SC1090
      source "$web_runtime_state"
      web_runtime_endpoint=${endpoint:-}
      if [[ -n "$web_runtime_endpoint" ]]; then
        web_runtime_ready=true
        for work_dir in "$plain_work" "$terra_work" "$sol_work"; do
          cp -f -- "$web_runtime_state" "$work_dir/web-runtime.env"
        done
      fi
    else
      printf 'Web runtime 준비 실패: STATIC-ONLY로 계속합니다. 로그=%s\n' "$run_root/metrics/web-runtime.log" >&2
    fi
  fi
else
  # Build once from the identical supplied context. All models receive the
  # same immutable image and create independent disposable containers from it.
  if [[ -f "$plain_input/Dockerfile" ]]; then
    command -v docker >/dev/null 2>&1 || { echo 'Dockerfile이 있는 벤치에는 Docker CLI가 필요합니다.' >&2; exit 69; }
    prepare_shared_image "$plain_input" "$run_root/metrics/shared-image.log" || true
  fi
fi
benchmark_docker_image=
if [[ "$shared_image_ready" == true ]]; then
  benchmark_docker_image=$shared_image
fi
if [[ "$category" == pwn ]]; then
  if [[ "$shared_image_ready" == true ]]; then
    docker_benchmark_rule="- 로컬 실행은 공용 읽기 전용 이미지 $shared_image와 \"\$CTF_BENCH_DOCKER_RUNNER\"를 사용하라. plain과 FAST_LOCAL은 같은 이미지를 쓰지만 매 호출마다 서로 독립된 --rm 컨테이너를 생성한다. 이미지를 다시 빌드·태그·삭제하거나 상대 variant의 컨테이너를 재사용하지 마라. bare IMAGE 호출은 금지한다. 검사는 종료되는 명시적 COMMAND를 사용하고, 이미지 기본 QEMU/service CMD가 필요할 때만 solver 내부에서 --service로 실행해 I/O와 종료를 직접 소유하라."
  else
    docker_benchmark_rule='- 준비된 공용 Docker 이미지가 없다. Docker를 재시도하거나 문제 바이너리를 호스트에서 실행하지 말고 STATIC-ONLY 분석을 계속하라.'
  fi
elif [[ "$category" == rev ]]; then
  if [[ "$shared_image_ready" == true ]]; then
    docker_benchmark_rule="- 동적 검증은 공용 읽기 전용 이미지 $shared_image와 \"\$CTF_BENCH_DOCKER_RUNNER\"를 사용하라. 두 변형은 같은 이미지를 사용하지만 매 호출마다 서로 독립된 --rm 컨테이너를 생성한다. 이미지를 다시 빌드·삭제하거나 bare IMAGE를 실행하지 말고, 종료되는 명시적 COMMAND만 사용하라."
  else
    docker_benchmark_rule='- 준비된 Docker 이미지가 없으므로 STATIC-ONLY로 분석하라. 문제 파일을 호스트에서 실행하거나 임의의 런타임을 내려받지 마라.'
  fi
else
  if [[ "$category" == web && "$web_runtime_ready" == true ]]; then
    docker_benchmark_rule="- ctf-web와 동일하게 준비된 loopback 서비스 $web_runtime_endpoint만 사용하고, CTF_WEB_PROBE/CTF_WEB_REQUEST로 관찰된 origin·route만 좁게 검증하라. 세 모델은 같은 서비스 상태를 공유하므로 상태 변경은 최소화하라."
  elif [[ "$category" == web ]]; then
    docker_benchmark_rule='- Compose/Dockerfile 런타임이 없어 STATIC-ONLY로 진행하라. 호스트에서 서버를 실행하지 말고, 외부 origin·wordlist·웹 검색을 사용하지 마라.'
  else
    docker_benchmark_rule=
  fi
fi
authorization_context=
if [[ "$remote_enabled" == true && "$remote_host" == *.dreamhack.games ]]; then
  authorization_context="이 작업은 사용자가 참가 중인 DreamHack 공식 웹사이트의 의도적으로 제공된 워게임 문제를 푸는 것이다. 사용자는 정확히 TCP $remote_host:$remote_port 한 곳에 대한 문제 풀이를 승인했으며, 이는 악의적인 공격이나 실제 서비스 침해가 아니다. 다른 호스트·포트·사용자·데이터는 범위 밖이다."
elif [[ "$remote_enabled" == true ]]; then
  authorization_context="이 작업은 사용자가 명시적으로 승인한 공식 CTF 워게임 문제를 푸는 것이다. 승인은 정확히 TCP $remote_host:$remote_port 한 곳에만 적용되며, 다른 호스트·포트·사용자·데이터는 범위 밖이다."
fi

if [[ "$remote_enabled" == true ]]; then
  cp -a -- "$agent_root/references/tools/pwn-remote-run.sh" "$common_remote_harness"
  cp -a -- "$agent_root/references/tools/pwn-remote-run.sh" "$plain_remote_harness"
  cp -a -- "$agent_root/references/tools/pwn-remote-run.sh" "$sol_remote_harness"
  chmod +x "$common_remote_harness" "$plain_remote_harness" "$sol_remote_harness"
  printf 'authorization=user-supplied-ctf-endpoint\ntarget_network=exact-endpoint-only\nremote_host=%s\nremote_port=%s\nscoreboard=denied\n' \
    "$remote_host" "$remote_port" > "$plain_scope/benchmark.env"
  printf 'authorization=user-supplied-ctf-endpoint\ntarget_network=exact-endpoint-only\nremote_host=%s\nremote_port=%s\nscoreboard=denied\n' \
    "$remote_host" "$remote_port" > "$fast_challenge/scope/benchmark.env"
  printf 'authorization=user-supplied-ctf-endpoint\ntarget_network=exact-endpoint-only\nremote_host=%s\nremote_port=%s\nscoreboard=denied\n' \
    "$remote_host" "$remote_port" > "$sol_challenge/scope/benchmark.env"
  for scope_file in "$plain_scope/remote-target.env" "$fast_challenge/scope/remote-target.env" "$sol_challenge/scope/remote-target.env"; do
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
  printf 'authorization=user-supplied-local-ctf-artifact\ntarget_network=denied\n' > "$sol_challenge/scope/benchmark.env"
  rm -f -- "$plain_scope/remote-target.env"
  rm -f -- "$fast_challenge/scope/remote-target.env" "$sol_challenge/scope/remote-target.env"
fi

install_agent_context() {
  local root=$1
  local key=$2
  ln -s "$agent_root/rules" "$root/rules" 2>/dev/null || true
  ln -s "$agent_root/references" "$root/references" 2>/dev/null || true
  ln -s "$agent_root/.agents" "$root/.agents" 2>/dev/null || true
  cp -a -- "$agent_root/state" "$root/state"
  case "$category" in
    pwn)
      ln -s "$agent_root/pwn-agent" "$root/pwn-agent" 2>/dev/null || true
      ln -s "$agent_root/shimes" "$root/shimes" 2>/dev/null || true
      ln -s "$agent_root/shimes/AGENTS.md" "$root/AGENTS.md" 2>/dev/null || true
      ln -s "$agent_root/shimes/CLAUDE.md" "$root/CLAUDE.md" 2>/dev/null || true
      mkdir -p "$benchmark_codex_home_root/$key/skills"
      ln -s "$agent_root/pwn-agent/skills" "$benchmark_codex_home_root/$key/skills/ctf-pwn" 2>/dev/null || true
      cp -a -- "$agent_root/references/tools/pwntools-template.py" "$root/challenges/$challenge_name/work/solve.py"
      ;;
    rev)
      ln -s "$agent_root/rev-agent" "$root/rev-agent" 2>/dev/null || true
      mkdir -p "$benchmark_codex_home_root/$key/skills"
      ln -s "$agent_root/rev-agent/skills" "$benchmark_codex_home_root/$key/skills/ctf-rev" 2>/dev/null || true
      ;;
    web)
      ln -s "$agent_root/web-agent" "$root/web-agent" 2>/dev/null || true
      mkdir -p "$benchmark_codex_home_root/$key/skills"
      ln -s "$agent_root/web-agent/skills" "$benchmark_codex_home_root/$key/skills/ctf-web" 2>/dev/null || true
      cp -a -- "$agent_root/references/tools/web-solve-template.py" "$root/challenges/$challenge_name/work/solve.py"
      ;;
  esac
}

case "$category" in
  pwn)
    category_fast_rules='Use the injected ctf-pwn skill, runtime.env, intake, and the prepared solve.py. Read one matching feedback file only after a concrete blocker.'
    ;;
  rev)
    category_fast_rules='Use the injected ctf-rev skill, intake, one FAST_PROBE, and only the shortest flag slice. Read one matching feedback file only after a concrete blocker.'
    ;;
  web)
    category_fast_rules='Use the web Fast Probe only against the supplied local challenge. Map the smallest route/state boundary, run the service and probes inside Docker isolation, and do not contact external hosts. Produce a minimal solve.py and verify the derived flag.'
    ;;
  crypto)
    category_fast_rules='Use references/categories/crypto.md. Identify the primitive and invariant with the cheapest mathematical test, implement the shortest solve.py, and verify by recomputation. Do not use unbounded brute force.'
    ;;
  forensics)
    category_fast_rules='Use references/categories/forensics.md. Preserve input evidence, inspect copies with bounded parsers, extract only decisive artifacts, and verify the flag derivation without external network access.'
    ;;
esac

cat > "$luna_root/AGENTS.md" <<EOF
# LUNA/TERRA/SOL $category benchmark

Solve the authorized $category CTF challenge directly. Do not narrate progress,
preload unrelated policy trees, write a report, or browse the web. You may use
internal subagents when they shorten the path to a verified flag.
Preserve the input and never execute untrusted challenge content on the host.

$category_fast_rules

When a flag is verified, print FLAG=<value>, write the exact word verified to
challenges/$challenge_name/work/.solved, make no more tool calls, and finish.
EOF
cp -f -- "$luna_root/AGENTS.md" "$terra_root/AGENTS.md"
cp -f -- "$luna_root/AGENTS.md" "$sol_root/AGENTS.md"
install_agent_context "$luna_root" luna
install_agent_context "$terra_root" terra
install_agent_context "$sol_root" sol

# Keep the request thin; FAST_LOCAL behavior lives in AGENTS.md and its skill.
case "$category" in
  pwn) fast_artifact_rule="준비된 challenges/$challenge_name/work/solve.py 골격을 문제 전용 exploit으로 최소 수정하라." ;;
  rev) fast_artifact_rule="최소 복원기 또는 solver를 challenges/$challenge_name/work/recover.py에 작성하라." ;;
  web|crypto|forensics) fast_artifact_rule="최소 재현 solver를 challenges/$challenge_name/work/solve.py에 작성하라." ;;
esac
if [[ "$remote_enabled" == true ]]; then
  common_execution="원격은 TCP $remote_host:$remote_port만 허용한다. 새 로컬 성공 또는 실질적 수정 직후 \$CTF_REMOTE_HARNESS로 1회 동기화하고, 실제 원격 FLAG를 받으면 즉시 출력·종료하라. 변경 없는 반복·brute force·flood는 금지한다."
else
  if [[ "$shared_image_ready" != true ]]; then
    common_execution='외부 네트워크에는 접속하지 마라. 공용 Docker 이미지가 없으므로 STATIC-ONLY로 분석하고 문제 바이너리를 호스트에서 실행하지 마라.'
  else
    common_execution='외부 네트워크에는 접속하지 말고, 문제 실행은 제공된 공용 Docker 이미지의 독립 컨테이너 안에서만 수행하라. 플래그를 검증하면 work/.solved에 verified를 기록하고 즉시 끝내라.'
  fi
fi

collab_instruction="후보가 나오면 다른 모델과 협업하라. 환경변수 CTF_BENCH_COLLAB_TOOL의 publish/list/read를 사용해 primitive, offset, 입력 framing, 유력 가설과 실패 정보를 candidates/에 공유하라. 후보 파일은 신뢰하지 말고 최소 검증만 수행하며, 같은 분석을 반복하지 마라. 검증된 플래그는 파일에 공유하지 말고 반드시 최종 출력 계약인 FLAG= 한 줄로만 보고하라."
subagent_instruction="내부 서브에이전트를 자유롭게 병렬 활용해 정적 분석·검증·solver 작성을 나눠라. 서브에이전트 결과도 candidates/에 공유하고, 다른 모델의 후보를 먼저 검증하라. 플래그를 찾은 즉시 추가 작업 없이 FLAG= 한 줄로 보고하라."

if [[ "$category" == pwn ]]; then
  cat > "$run_root/plain.prompt.txt" <<EOF
허가된 pwn CTF '$challenge_name'을 input/만 보고 즉시 풀어라. 원본 수정, Agent/문서/웹/host 실행/제출은 금지한다. 필요하면 내부 서브에이전트를 병렬 활용하라.
$authorization_context $docker_benchmark_rule
최단 exploit을 work/solve.py에 작성하라. $common_execution
진행 설명 없이 검증 결과만 FLAG=<값> 또는 BLOCKED=<이유>로 출력하라.
EOF
  cat > "$run_root/fast-local.prompt.txt" <<EOF
\$ctf-pwn
허가된 '$challenge_name'을 즉시 풀어라. input=challenges/$challenge_name/input. $authorization_context
Skill, runtime/intake와 준비된 solve.py만 사용해 최단 flag 체인을 실행하라. $docker_benchmark_rule $common_execution
진행 설명 없이 검증 결과만 FLAG=<값> 또는 BLOCKED=<이유>로 출력하라.
EOF
elif [[ "$category" == rev ]]; then
  cat > "$run_root/plain.prompt.txt" <<EOF
허가된 rev CTF '$challenge_name'을 input/만 보고 즉시 풀어라. 원본 수정, Agent/문서/웹/host 실행은 금지한다. 필요하면 내부 서브에이전트를 병렬 활용하라.
최단 복원을 work/recover.py에 작성하라. $docker_benchmark_rule $common_execution
진행 설명 없이 FLAG=<값>과 .solved=verified 또는 BLOCKED=<이유>만 남기고 종료하라.
EOF
  cat > "$run_root/fast-local.prompt.txt" <<EOF
\$ctf-rev
허가된 '$challenge_name'을 즉시 풀어라. input=challenges/$challenge_name/input.
Skill, intake와 FAST_PROBE 한 번으로 최단 flag slice만 복원하라. $docker_benchmark_rule $common_execution
진행 설명 없이 FLAG=<값>과 .solved=verified 또는 BLOCKED=<이유>만 남기고 종료하라.
EOF
else
  cat > "$run_root/plain.prompt.txt" <<EOF
허가된 $category CTF '$challenge_name'을 input/만 보고 즉시 풀어라. 원본 수정, 웹, host 실행, 진행 설명은 금지한다. 필요하면 내부 서브에이전트를 병렬 활용하라.
최소 solver를 work/에 작성하라. $common_execution 결과만 FLAG=<값> 또는 BLOCKED=<이유>로 출력하라.
EOF
  cat > "$run_root/fast-local.prompt.txt" <<EOF
허가된 $category CTF '$challenge_name'을 즉시 풀어라. input=challenges/$challenge_name/input.
AGENTS.md의 Fast path와 $fast_artifact_rule $common_execution 진행 설명 없이 FLAG=<값> 또는 BLOCKED=<이유>만 출력하라.
EOF
fi

# Competition prompts are intentionally identical except for the model name;
# every participant uses the same Agent context and bounded flag contract.
prompt_body=""
if [[ "$category" == pwn ]]; then
  prompt_body="\$ctf-pwn\n허가된 pwn CTF '$challenge_name'을 가장 짧은 플래그 경로로 풀어라. input=challenges/$challenge_name/input. runtime.env와 준비된 solve.py를 먼저 확인하라. $authorization_context $docker_benchmark_rule $common_execution $collab_instruction"
elif [[ "$category" == rev ]]; then
  prompt_body="\$ctf-rev\n허가된 rev CTF '$challenge_name'을 전체 동작 분석보다 플래그 복원을 우선해 풀어라. input=challenges/$challenge_name/input. $docker_benchmark_rule $common_execution $collab_instruction"
else
  if [[ "$category" == web ]]; then
    prompt_body="\$ctf-web\n허가된 Web CTF '$challenge_name'을 input=challenges/$challenge_name/input에서 가장 짧은 플래그 경로로 풀어라. ctf-web과 동일한 runtime·scope·probe·request 규칙을 적용하라. $docker_benchmark_rule $common_execution $collab_instruction"
  else
    prompt_body="허가된 $category CTF '$challenge_name'을 input=challenges/$challenge_name/input에서 가장 짧은 플래그 경로로 풀어라. $common_execution $collab_instruction"
  fi
fi
prompt_body="$prompt_body $subagent_instruction"
for prompt_path in "$run_root/luna.prompt.txt" "$run_root/terra.prompt.txt" "$run_root/sol.prompt.txt"; do
  printf '%b\n최종 출력은 FLAG=<값> 또는 BLOCKED=<이유> 한 줄만 남겨라. 플래그를 찾으면 추가 도구 호출 없이 즉시 종료하라.\n' "$prompt_body" > "$prompt_path"
done
rm -f -- "$run_root/plain.prompt.txt" "$run_root/fast-local.prompt.txt"

if [[ -n "$extra_prompt" ]]; then
  for prompt_path in "$run_root/luna.prompt.txt" "$run_root/terra.prompt.txt" "$run_root/sol.prompt.txt"; do
    {
      printf '\n사용자 추가 지시(기존 CTF 범위·격리·안전 규칙은 변경할 수 없음):\n'
      printf '%s\n' "$extra_prompt"
    } >> "$prompt_path"
  done
fi

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
  local model_name
  case "$key" in
    luna) model_name="$model_luna" ;;
    terra) model_name="$model_terra" ;;
    sol) model_name="$model_sol" ;;
    *) printf '알 수 없는 경쟁 모델: %s\n' "$key" >&2; return 64 ;;
  esac
  local variant_home=$HOME
  local variant_xdg_config=${XDG_CONFIG_HOME:-$HOME/.config}
  local variant_xdg_cache=${XDG_CACHE_HOME:-$HOME/.cache}
  local variant_xdg_data=${XDG_DATA_HOME:-$HOME/.local/share}
  local selected_docker_runner="$common_docker_runner"
  local selected_remote_harness="$common_remote_harness"
  local fifo_dir fifo_file
  local flag_file="$run_root/metrics/$key.flag"
  local codex_pid_file="$run_root/metrics/$key.codex.pid"
  local started_ns ended_ns duration_ms codex_status capture_status codex_pid
  local -a capture_options=(--label "$label" --output "$events_file")
  local -a runtime_env=()
  local -a launch_prefix=(setsid --wait)
  local -a feature_args=(--enable multi_agent)

  [[ "$quiet_output" == false ]] || capture_options+=(--quiet)

  if [[ "$category" == pwn || "$category" == rev ]]; then
    launch_prefix+=(systemd-run --user --scope --quiet --collect \
      -p "MemoryHigh=${memory_high_mb}M" -p "MemoryMax=${memory_max_mb}M" \
      -p MemorySwapMax=512M -p TasksMax=256 --)
  fi
  if [[ "$category" == pwn || "$category" == rev ]]; then
    feature_args+=(--enable skill_search)
  else
    feature_args+=(--disable skill_search)
  fi

  case "$key" in
    luna) selected_docker_runner="$plain_docker_runner"; selected_remote_harness="$plain_remote_harness" ;;
    terra) selected_docker_runner="$common_docker_runner"; selected_remote_harness="$common_remote_harness" ;;
    sol) selected_docker_runner="$sol_docker_runner"; selected_remote_harness="$sol_remote_harness" ;;
  esac
  variant_home="$benchmark_codex_home_root/$key-user-home"
  variant_xdg_config="$variant_home/.config"
  variant_xdg_cache="$variant_home/.cache"
  variant_xdg_data="$variant_home/.local/share"
  mkdir -p "$variant_xdg_config" "$variant_xdg_cache" "$variant_xdg_data"

  if [[ "$category" == pwn ]]; then
    runtime_env+=("CTF_PWN_RUNNER=$selected_docker_runner")
    [[ -z "$docker_image" ]] || runtime_env+=("CTF_PWN_IMAGE=$docker_image")
  elif [[ "$category" == rev ]]; then
    local rev_input_dir="$workspace/input"
    rev_input_dir="$workspace/challenges/$challenge_name/input"
    runtime_env+=("CTF_REV_RUNNER=$selected_docker_runner" "CTF_REV_INPUT_DIR=$rev_input_dir" "CTF_REV_WORK_DIR=$work_dir" "CTF_REV_RUNTIME_MODE=$([[ -n "$docker_image" ]] && printf supplied-docker || printf static-only)" "CTF_REV_FLAG_SUCCESS=$common_tools/rev-flag-success.sh")
    runtime_env+=("CTF_REV_FAST_PROBE=$run_root/tools/rev-fast-probe.sh")
    [[ -z "$docker_image" ]] || runtime_env+=("CTF_REV_IMAGE=$docker_image")
  elif [[ "$category" == web ]]; then
    runtime_env+=("CTF_WEB_PROBE=$common_web_probe" "CTF_WEB_REQUEST=$common_web_request" "CTF_WEB_RUNTIME_STATE=$work_dir/web-runtime.env" "CTF_WEB_RUNTIME_MODE=$([[ "$web_runtime_ready" == true ]] && printf local || printf static-only)")
    if [[ -n "$web_runtime_endpoint" ]]; then
      runtime_env+=("CTF_WEB_LOCAL_URL=$web_runtime_endpoint" "CTF_WEB_TARGET_URL=$web_runtime_endpoint" "CTF_WEB_SCOPE_ORIGIN=$web_runtime_endpoint")
    fi
  fi

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
    # Competition mode prioritizes the first verified flag over telemetry
    # drain; usage can be unavailable for participants stopped at the marker.
  fi
  capture_options+=(--race --flag-file "$flag_file")

  while [[ ! -e "$start_gate" ]]; do
    sleep 0.01
  done
  started_ns=$(date +%s%N)
  fifo_dir=$(mktemp -d "${TMPDIR:-/tmp}/ctf-bench-${run_id}-${key}.XXXXXX")
  fifo_file="$fifo_dir/events.fifo"
  mkfifo -- "$fifo_file"
  set +e
  "${launch_prefix[@]}" \
    env HOME="$variant_home" CODEX_HOME="$isolated_codex_home" \
      XDG_CONFIG_HOME="$variant_xdg_config" XDG_CACHE_HOME="$variant_xdg_cache" \
      XDG_DATA_HOME="$variant_xdg_data" \
      MALLOC_ARENA_MAX=2 NODE_OPTIONS="--max-old-space-size=$((memory_max_mb - 256))" \
      CTF_AGENT_ROOT="$workspace" CTF_BENCH_WORK_DIR="$work_dir" \
      CTF_BENCH_CATEGORY="$category" \
      CTF_PWN_BENCHMARK="$([[ "$category" == pwn ]] && printf true || printf false)" \
      CTF_REV_BENCHMARK="$([[ "$category" == rev ]] && printf true || printf false)" \
      CTF_BENCH_DOCKER_IMAGE="$docker_image" CTF_BENCH_REMOTE="$remote_enabled" \
      CTF_BENCH_DOCKER_RUNNER="$selected_docker_runner" \
      CTF_BENCH_RUN_ID="$run_id" CTF_BENCH_VARIANT="$key" \
      CTF_BENCH_COLLAB_DIR="$collab_dir" CTF_BENCH_CANDIDATE_DIR="$collab_dir/candidates" \
      CTF_BENCH_COLLAB_TOOL="$common_collab_tool" CTF_BENCH_COLLAB_KEY="$key" \
      CTF_REMOTE_HOST="$remote_host" CTF_REMOTE_PORT="$remote_port" \
      CTF_REMOTE_HARNESS="$selected_remote_harness" \
      CTF_REMOTE_TRANSCRIPT="$work_dir/remote-transcript.txt" \
      "${runtime_env[@]}" \
    "$codex_bin" exec --ephemeral --ignore-user-config --skip-git-repo-check \
      -C "$workspace" --model "$model_name" \
      -c "model_reasoning_effort=\"$reasoning_effort\"" \
      -c 'service_tier="fast"' --enable fast_mode \
      -c 'approval_policy="never"' \
      "${feature_args[@]}" \
      --disable browser_use --disable browser_use_external \
      --disable browser_use_full_cdp_access --disable in_app_browser \
      --disable standalone_web_search \
      --sandbox danger-full-access --json - \
      < "$prompt_file" > "$fifo_file" 2> "$stderr_file" &
  codex_pid=$!
  printf '%s\n' "$codex_pid" > "$codex_pid_file"
  python3 "$metrics_py" capture "${capture_options[@]}" < "$fifo_file"
  capture_status=$?
  # Publish the winner before waiting for Codex shutdown or summary parsing so
  # the parent can terminate the other model groups at the first marker.
  if [[ -s "$flag_file" ]]; then
    winner_tmp="$run_root/winner.env.$key"
    {
      printf 'key=%s\n' "$key"
      printf 'label=%s\n' "$label"
      printf 'model=%s\n' "$model_name"
      printf 'flag=%s\n' "$(<"$flag_file")"
    } > "$winner_tmp"
    if (set -o noclobber; : > "$run_root/winner.lock") 2>/dev/null; then
      if [[ ! -e "$run_root/winner.env" ]]; then
        mv -- "$winner_tmp" "$run_root/winner.env"
      else
        rm -f -- "$winner_tmp"
      fi
      rm -f -- "$run_root/winner.lock"
    else
      rm -f -- "$winner_tmp"
    fi
  fi
  if [[ "$capture_status" -ne 0 ]]; then
    stop_process_group "$codex_pid" INT
  fi
  wait "$codex_pid"
  codex_status=$?
  set -e
  rm -f -- "$codex_pid_file"
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
    if [[ -s "$flag_file" ]]; then
      printf 'race_flag=%s\n' "$(<"$flag_file")"
    fi
  } > "$status_file"

  python3 "$metrics_py" summarize \
    --key "$key" --label "$label" --events "$events_file" --status "$status_file" \
    --work-dir "$work_dir" --flag-file "$flag_file" --collab-dir "$collab_dir" \
    --output "$run_root/metrics/$key.summary.json"

  if [[ -s "$flag_file" ]]; then
    winner_tmp="$run_root/winner.env.$key"
    {
      printf 'key=%s\n' "$key"
      printf 'label=%s\n' "$label"
      printf 'model=%s\n' "$model_name"
      printf 'flag=%s\n' "$(<"$flag_file")"
    } > "$winner_tmp"
    if (set -o noclobber; : > "$run_root/winner.lock") 2>/dev/null; then
      if [[ ! -e "$run_root/winner.env" ]]; then
        mv -- "$winner_tmp" "$run_root/winner.env"
      else
        rm -f -- "$winner_tmp"
      fi
      rm -f -- "$run_root/winner.lock"
    else
      rm -f -- "$winner_tmp"
    fi
  fi

}

start_gate="$run_root/.parallel-start"
luna_pid=
terra_pid=
sol_pid=
race_won=false

terminate_variants() {
  trap - INT TERM HUP
  for pid in "$luna_pid" "$terra_pid" "$sol_pid"; do
    [[ -z "$pid" ]] || kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in "$luna_pid" "$terra_pid" "$sol_pid"; do
    [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
  done
  exit 130
}
trap terminate_variants INT TERM HUP

run_variant luna 'LUNA max' "$luna_root" "$plain_work" \
  "$run_root/luna.prompt.txt" "$benchmark_docker_image" &
luna_pid=$!
run_variant terra 'TERRA max' "$fast_root" "$terra_work" \
  "$run_root/terra.prompt.txt" "$benchmark_docker_image" &
terra_pid=$!
run_variant sol 'SOL max' "$sol_root" "$sol_work" \
  "$run_root/sol.prompt.txt" "$benchmark_docker_image" &
sol_pid=$!

printf 'LUNA max, TERRA max, SOL max를 병렬 경쟁으로 시작합니다.\n'
: > "$start_gate"

set +e
while :; do
  if [[ -s "$run_root/winner.env" ]]; then
    race_won=true
    winner_key=$(awk -F= '$1 == "key" {print $2; exit}' "$run_root/winner.env")
    winner_label=$(awk -F= '$1 == "label" {print $2; exit}' "$run_root/winner.env")
    winner_model=$(awk -F= '$1 == "model" {print $2; exit}' "$run_root/winner.env")
    winner_flag=$(awk -F= '$1 == "flag" {print $2; exit}' "$run_root/winner.env")
    printf '[%s] FLAG=%s 포착 (%s), 나머지 모델을 종료합니다.\n' "$winner_label" "$winner_flag" "$winner_model"
    for pair in "luna:$luna_pid" "terra:$terra_pid" "sol:$sol_pid"; do
      key=${pair%%:*}; pid=${pair#*:}
      [[ "$key" == "$winner_key" ]] && continue
      codex_pid_file="$run_root/metrics/$key.codex.pid"
      if [[ -s "$codex_pid_file" ]]; then
        stop_process_group "$(<"$codex_pid_file")" INT
      fi
    done
    break
  fi
  alive=false
  for pid in "$luna_pid" "$terra_pid" "$sol_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then alive=true; fi
  done
  [[ "$alive" == true ]] || break
  sleep 0.1
done
wait "$luna_pid"; luna_runner_status=$?
wait "$terra_pid"; terra_runner_status=$?
wait "$sol_pid"; sol_runner_status=$?
set -e
trap - INT TERM HUP
rm -f -- "$start_gate"

if [[ "$race_won" != true && ( $luna_runner_status -ne 0 || $terra_runner_status -ne 0 || $sol_runner_status -ne 0 ) ]]; then
  printf '벤치마크 실행기 오류: luna=%s terra=%s sol=%s\n' "$luna_runner_status" "$terra_runner_status" "$sol_runner_status" >&2
  exit 74
fi

python3 "$metrics_py" report \
  --summary "luna=$run_root/metrics/luna.summary.json" \
  --summary "terra=$run_root/metrics/terra.summary.json" \
  --summary "sol=$run_root/metrics/sol.summary.json" \
  --output "$run_root/report.md"

printf '\n전체 결과: %s\n' "$run_root"
printf '비교 보고서: %s\n' "$run_root/report.md"
