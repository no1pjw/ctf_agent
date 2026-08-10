#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: ctf-pwn [옵션] 문제이름 [호스트:포트]
        ctf-pwn [옵션] 문제이름 [호스트 포트]

실행 모드:
  (기본값)      빠른 탐색 후 필요할 때만 Deep 모드로 자동 전환
  --fast-only   제한된 빠른 탐색까지만 수행
  --deep        처음부터 전체 P0~P6 절차 수행

옵션:
  --audit       입력 프롬프트, 역할 목록, TUI 로그 및 사용 내역 기록
  --rebuild     캐시 대신 문제 Docker 이미지 다시 빌드
  --keep-docker 풀이 종료 후 문제 컨테이너와 이미지를 보존
  --keep-workspace  풀이 완료 후에도 중복 입력과 실행 로그를 보존
  --dry-run     경로, 모드, 권한 및 생성 프롬프트만 표시
  --prepare-only  Codex 실행 없이 파일 복사 및 작업 디렉터리 준비

원격 대상:
  문제 이름 뒤에 공식 CTF 서비스 주소를 지정하면 완성된 work/solve.py를
  그 주소에만 제한 실행합니다. 로컬 런타임이 없으면 정적 교차 확인 후 바로 시도합니다.
  예: ctf-pwn cherry host3.dreamhack.games:12345

환경 변수:
  CTF_PWNABLE_SOURCE  문제 폴더 또는 ZIP이 있는 원본 디렉터리
  CTF_AGENT_ROOT      설치된 ctf-agent 루트
  CODEX_BIN           Codex CLI의 명시적 경로
  CTF_MIN_HOST_FREE_MB 실행 전 필요한 Windows 호스트 최소 여유 공간(MiB, 기본 4096)
  CTF_CODEX_MODEL     문제 풀이 모델(기본 gpt-5.6-sol)
  CTF_CODEX_REASONING_EFFORT  추론 강도(기본 Adaptive/Fast=high, Deep=ultra)
  CTF_CODEX_SERVICE_TIER  서비스 티어(기본 fast)
EOF
}

action=launch
solve_mode=adaptive
audit_enabled=false
rebuild=false
keep_docker=false
keep_workspace=false
challenge_name=
remote_host=
remote_port=
positionals=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit) audit_enabled=true ;;
    --rebuild) rebuild=true ;;
    --keep-docker) keep_docker=true ;;
    --keep-workspace) keep_workspace=true ;;
    --fast-only) solve_mode=fast-only ;;
    --deep) solve_mode=deep ;;
    --dry-run) action=dry-run ;;
    --prepare-only) action=prepare-only ;;
    -h|--help) usage; exit 0 ;;
    --) shift; positionals+=("$@"); break ;;
    -*) printf '알 수 없는 옵션: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    *) positionals+=("$1") ;;
  esac
  shift
done

case ${#positionals[@]} in
  1)
    challenge_name=${positionals[0]}
    ;;
  2)
    challenge_name=${positionals[0]}
    endpoint=${positionals[1]}
    if [[ "$endpoint" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
      remote_host=${BASH_REMATCH[1]}
      remote_port=${BASH_REMATCH[2]}
    elif [[ "$endpoint" =~ ^([^:/[:space:]]+):([0-9]+)$ ]]; then
      remote_host=${BASH_REMATCH[1]}
      remote_port=${BASH_REMATCH[2]}
    else
      echo '원격 주소는 호스트:포트 형식으로 지정하세요.' >&2
      exit 64
    fi
    ;;
  3)
    challenge_name=${positionals[0]}
    remote_host=${positionals[1]}
    remote_port=${positionals[2]}
    ;;
  *) usage >&2; exit 64 ;;
esac

if [[ -n "$remote_host" ]]; then
  if [[ "$remote_host" == *:* ]]; then
    host_valid=false
    [[ "$remote_host" =~ ^[0-9A-Fa-f:]+$ ]] && host_valid=true
  else
    host_valid=false
    [[ "$remote_host" =~ ^[A-Za-z0-9.-]+$ ]] && host_valid=true
  fi
  if [[ "$host_valid" != true ]] || [[ ! "$remote_port" =~ ^[0-9]+$ ]] || (( remote_port < 1 || remote_port > 65535 )); then
    echo '잘못된 원격 주소입니다. 호스트와 1~65535 포트를 확인하세요.' >&2
    exit 65
  fi
fi
if [[ ! "$challenge_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$challenge_name" == "." || "$challenge_name" == ".." ]]; then
  printf '잘못된 문제 이름입니다: %s\n' "$challenge_name" >&2
  exit 65
fi

source_root=${CTF_PWNABLE_SOURCE:-$HOME/ctf-challenges/pwnable}
agent_root=${CTF_AGENT_ROOT:-$HOME/workspace/CTF/ctf-agent}
sandbox_mode=danger-full-access
approval_policy=never
source_dir="$source_root/$challenge_name"
source_zip="$source_root/$challenge_name.zip"
challenge_dir="$agent_root/challenges/$challenge_name"
input_dir="$challenge_dir/input"
work_dir="$challenge_dir/work"
evidence_dir="$challenge_dir/evidence"
scope_dir="$challenge_dir/scope"
tools_dir="$agent_root/references/tools"
runtime_tool="$tools_dir/pwn-runtime-prepare.sh"
intake_tool="$tools_dir/pwn-intake-check.sh"
process_cleanup_tool="$tools_dir/pwn-process-cleanup.sh"
runtime_output="$work_dir/runtime"
runtime_manifest="$runtime_output/runtime.env"
image_slug="$(printf '%s' "$challenge_name" | tr '[:upper:]_.' '[:lower:]--')"
image_name="ctf-$image_slug:local"
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
codex_offline_args=(
  --disable browser_use
  --disable browser_use_external
  --disable browser_use_full_cdp_access
  --disable in_app_browser
  --disable standalone_web_search
)

if [[ ! "$codex_service_tier" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf '잘못된 Codex 서비스 티어입니다: %s\n' "$codex_service_tier" >&2
  exit 65
fi
[[ "$codex_reasoning_effort" =~ ^(low|medium|high|xhigh|max|ultra)$ ]] || {
  printf '잘못된 추론 강도입니다: %s\n' "$codex_reasoning_effort" >&2
  exit 65
}
if [[ -f "$source_dir/Dockerfile" || -f "$input_dir/Dockerfile" ]]; then
  runtime_mode=supplied-docker
elif docker image inspect "$image_name" >/dev/null 2>&1; then
  runtime_mode=cached-docker
else
  runtime_mode=static-only
fi

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 존재하지 않습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -f "$runtime_tool" ]] || { printf 'pwn runtime 준비 도구가 없습니다: %s\n' "$runtime_tool" >&2; exit 66; }
[[ -x "$intake_tool" ]] || { printf 'pwn intake 점검 도구가 없습니다: %s\n' "$intake_tool" >&2; exit 66; }
[[ -x "$process_cleanup_tool" ]] || { printf 'pwn process 정리 도구가 없습니다: %s\n' "$process_cleanup_tool" >&2; exit 66; }
[[ -d "$source_dir" || -f "$source_zip" ]] || {
  printf '문제를 찾을 수 없습니다. 다음 중 하나가 필요합니다:\n  %s\n  %s\n' "$source_dir" "$source_zip" >&2
  exit 67
}

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin="$(command -v codex 2>/dev/null || true)"
fi

# Keep the launcher prompt thin. Shared workflow, safety, escalation, input-framing,
# verification, and feedback rules live in AGENTS.md, ruleset.md, and the pwn skill.
case "$runtime_mode" in
  supplied-docker)
    compact_runtime="제공된 Dockerfile을 하니스로 빌드·실행하고 이미지 $image_name을 사용하라."
    ;;
  cached-docker)
    compact_runtime="Dockerfile은 없으므로 재빌드하지 말고 캐시 이미지 $image_name만 하니스로 사용하라."
    ;;
  static-only)
    if [[ -n "$remote_host" ]]; then
      compact_runtime="Dockerfile과 캐시 이미지가 없으므로 STATIC-ONLY로 분석하되, 정적 exploit과 solver가 완성되면 로컬 실행 없이 정확한 공식 endpoint에 bounded remote client를 즉시 실행하라. challenge 바이너리의 호스트 실행은 금지한다."
    else
      compact_runtime="Dockerfile과 캐시 이미지가 없으므로 즉시 STATIC-ONLY로 계속하라. Docker 재시도·임시 환경 생성·호스트 실행은 금지하며, 동적 검증이 꼭 필요할 때만 정확한 blocker를 남겨라."
    fi
    ;;
esac

prompt=$(cat <<EOF
\$ctf-pwn

허가된 pwn 문제 '$challenge_name'을 즉시 풀어라.
- 입력: challenges/$challenge_name/input
- 실행: mode=$solve_mode, runtime=$runtime_mode, 파일 변경·경과 시간 감시 경고와 자동 종료는 모두 비활성이다.
- 정책: AGENTS.md와 \$ctf-pwn 스킬을 따르되 반복 설명하지 말고 state.json, runtime.env, intake-exec.txt, feedback index를 확인한 뒤 가장 싼 분석 명령부터 실행하라.
- 런타임: $compact_runtime runtime.env의 libc/ld 출처를 지키고 host 런타임이나 미검증 혼합 쌍을 사용하지 마라.
- 제한: 한국어로 진행하고 웹 검색·호스트 바이너리 실행·플래그 자동 제출을 금지한다.
- 결과: work/solve.py와 간결한 work/writeup.md만 만들고, 실제 검증된 플래그만 즉시 출력한 뒤 work/.solved에 verified를 기록하라.
EOF
)

if [[ "$keep_docker" == true ]]; then
  prompt+=$'\n- 정리 예외: 사용자가 --keep-docker를 지정했으므로 문제 컨테이너와 이미지를 보존하라.'
fi

if [[ -n "$remote_host" ]]; then
  prompt+=$(cat <<EOF

- 공식 원격: TCP $remote_host:$remote_port만 허용한다. 고정 시도 횟수 제한은 두지 않는다. solver가 로컬에서 새로 성공할 때마다 같은 버전을 references/tools/pwn-remote-run.sh로 즉시 원격 실행해 차이를 확인하라. 로컬 실행이 불가능하면 정적 교차 확인을 통과한 첫 버전과 이후 실질적으로 수정된 버전을 원격 실행하라. 변경 없는 exploit 자동 반복·무차별 대입·병렬 flood는 금지한다.
- 성공: solve.py가 검증된 FLAG=<원문>을 출력하면 즉시 연결을 닫고, 하니스의 플래그와 획득 시간을 바로 보여 준 뒤 종료하라.
EOF
)
else
  prompt+=$'\n- 원격 범위: 미지정이므로 모든 대상 네트워크 접속 금지'
fi

if [[ "$rebuild" == true ]]; then
  if [[ "$runtime_mode" == supplied-docker ]]; then
    prompt+=$'\n- 추가: Docker 이미지를 재빌드하라.'
  else
    prompt+=$'\n- 추가: Dockerfile이 없어 재빌드할 수 없으므로 현재 런타임 모드로 계속하라.'
  fi
fi
if [[ "$audit_enabled" == true ]]; then
  prompt+=$'\n- 추가: Audit 내역을 evidence/audit/latest/agent-usage-summary.md에 기록하라.'
fi

if [[ "$action" == dry-run ]]; then
  printf '원본 디렉터리:    %s\n' "$source_dir"
  printf '원본 ZIP:         %s\n' "$source_zip"
  printf '문제 작업 경로:   %s\n' "$challenge_dir"
  printf 'Docker 이미지:    %s\n' "$image_name"
  printf '런타임 모드:      %s\n' "$runtime_mode"
  printf 'libc/ld 준비:     제공 파일 우선, 부족하면 정확한 Docker 이미지에서 둘을 함께 추출\n'
  printf '풀이 모드:        %s\n' "$solve_mode"
  printf '재빌드:           %s\n' "$rebuild"
  if [[ "$runtime_mode" == supplied-docker && "$keep_docker" == false ]]; then
    printf 'Docker 종료 정리: 자동\n'
  else
    printf 'Docker 종료 정리: 보존\n'
  fi
  printf '감사 로그:        %s\n' "$audit_enabled"
  printf 'Codex 샌드박스:   %s\n' "$sandbox_mode"
  printf '승인 정책:        %s\n' "$approval_policy"
  printf 'Codex 모델:       %s\n' "$codex_model"
  printf '추론 강도:        %s\n' "$codex_reasoning_effort"
  printf '서비스 티어:      %s (Fast mode 활성)\n' "$codex_service_tier"
  printf '상태 감시 경고:   비활성 (파일 변경·경과 시간 경고 없음)\n'
  printf '웹 탐색:          비활성 (브라우저·웹 검색·write-up 조회 금지)\n'
  printf '완료 후 작업공간 정리: %s\n' "$([[ "$keep_workspace" == true ]] && printf '보존' || printf '자동')"
  if [[ -n "$remote_host" ]]; then
    printf '공식 원격 대상:   %s:%s\n' "$remote_host" "$remote_port"
  else
    printf '공식 원격 대상:   지정 안 됨\n'
  fi
  printf '\nCodex에 전달할 프롬프트:\n%s\n' "$prompt"
  exit 0
fi

min_host_free_mb=${CTF_MIN_HOST_FREE_MB:-4096}
if [[ ! "$min_host_free_mb" =~ ^[0-9]+$ ]]; then
  printf 'CTF_MIN_HOST_FREE_MB는 0 이상의 정수여야 합니다: %s\n' "$min_host_free_mb" >&2
  exit 65
fi
if [[ -d /mnt/c && "$min_host_free_mb" -gt 0 ]]; then
  host_free_kb=$(df -Pk /mnt/c | awk 'NR==2 {print $4}')
  if [[ "$host_free_kb" =~ ^[0-9]+$ ]] && (( host_free_kb < min_host_free_mb * 1024 )); then
    printf 'Windows 호스트 여유 공간이 부족하여 새 문제 복사를 중단합니다: %s MiB 미만\n' "$min_host_free_mb" >&2
    printf '먼저 ctf-clean --caches --apply를 실행하거나 CTF_MIN_HOST_FREE_MB를 명시적으로 조정하세요.\n' >&2
    exit 72
  fi
fi

mkdir -p "$input_dir" "$work_dir" "$evidence_dir" "$scope_dir"
printf 'pwn\n' > "$challenge_dir/.ctf-category"
if [[ -n "$remote_host" ]]; then
  {
    printf 'authorization=user-declared-official-ctf-endpoint\n'
    printf 'protocol=tcp\n'
    printf 'host=%s\nport=%s\n' "$remote_host" "$remote_port"
    printf 'attempt_policy=each-new-local-success-or-material-correction\n'
    printf 'attempt_limit=none\n'
    printf 'scoreboard_submission=denied\n'
  } > "$scope_dir/remote-target.env"
else
  rm -f -- "$scope_dir/remote-target.env"
fi
if [[ -d "$source_dir" ]]; then
  printf '%s\n' "$source_dir" > "$scope_dir/source-path.txt"
  cp -a --update=none -- "$source_dir"/. "$input_dir"/
else
  printf '%s\n' "$source_zip" > "$scope_dir/source-path.txt"
  cp -a --update=none -- "$source_zip" "$input_dir"/
fi
printf '문제 준비 완료: %s\n' "$challenge_dir"

if ! "$intake_tool" "$input_dir" > "$work_dir/intake-exec.txt"; then
  printf 'Docker/service 실행 파일명 자동 대조에 실패했습니다. 정적 분석은 계속할 수 있습니다.\n' >&2
else
  cat -- "$work_dir/intake-exec.txt"
fi

set +e
runtime_prepare_args=(--input "$input_dir" --output "$runtime_output")
if [[ "$runtime_mode" == static-only ]]; then
  runtime_prepare_args+=(--preserve-ready)
fi
"$runtime_tool" "${runtime_prepare_args[@]}"
runtime_prepare_status=$?
set -e
if [[ $runtime_prepare_status -ne 0 ]]; then
  printf '제공 파일만으로 완전한 libc/ld 쌍을 준비하지 못했습니다. 정확한 Docker 이미지가 준비되면 누락 파일을 보완합니다.\n'
fi
if [[ ! -f "$work_dir/state.json" && -x "$tools_dir/pwn-checkpoint.sh" ]]; then
  CTF_AGENT_ROOT="$agent_root" "$tools_dir/pwn-checkpoint.sh" "$challenge_name" setup active "mode=$solve_mode runtime=$runtime_mode" >/dev/null
fi

audit_dir=
if [[ "$audit_enabled" == true ]]; then
  [[ -n "$codex_bin" ]] || { echo 'Codex CLI를 사용할 수 없습니다.' >&2; exit 69; }
  run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  audit_root="$evidence_dir/audit"
  audit_dir="$audit_root/$run_id"
  mkdir -p "$audit_dir/tui"
  ln -sfn "$run_id" "$audit_root/latest"
  printf '%s\n' "$prompt" > "$audit_dir/prompt.txt"
  {
    printf 'run_id=%s\nstarted_utc=%s\nchallenge=%s\n' "$run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$challenge_name"
    printf 'solve_mode=%s\nrebuild=%s\nruntime_mode=%s\nsandbox=%s\napproval=%s\n' "$solve_mode" "$rebuild" "$runtime_mode" "$sandbox_mode" "$approval_policy"
    if [[ -n "$remote_host" ]]; then
      printf 'target_network=exact-endpoint-only\ntarget_host=%s\ntarget_port=%s\n' "$remote_host" "$remote_port"
    else
      printf 'target_network=denied\n'
    fi
    printf 'build_network=controlled-by-pwn-build\nruntime_network=none\nstatus=starting\n'
    if [[ -f "$runtime_manifest" ]]; then
      printf 'runtime_manifest=%s\n' "$runtime_manifest"
      sed -n '/^runtime_status=/p;/^runtime_source=/p;/^pair_status=/p' "$runtime_manifest"
    fi
  } > "$audit_dir/run-info.txt"
  find "$agent_root/.agents" "$agent_root/pwn-agent" "$agent_root/rules" "$agent_root/shimes" -type f -print | sort > "$audit_dir/available-role-files.txt"
  if "$codex_bin" -C "$agent_root" debug prompt-input "$prompt" > "$audit_dir/prompt-input.json" 2> "$audit_dir/prompt-input.stderr.log"; then
    echo 'prompt_input_capture=ok' >> "$audit_dir/run-info.txt"
  else
    echo 'prompt_input_capture=failed' >> "$audit_dir/run-info.txt"
  fi
  printf '감사 로그 디렉터리: %s\n' "$audit_dir"
fi

cleanup_enabled=false
process_run_id=
if [[ "$runtime_mode" == supplied-docker && "$keep_docker" == false ]]; then
  cleanup_enabled=true
fi

cleanup_on_exit() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$process_run_id" ]]; then
    "$process_cleanup_tool" "$process_run_id" || true
  fi
  if [[ "$cleanup_enabled" == true ]]; then
    printf '\n문제 Docker 리소스 정리 중: %s\n' "$image_name"
    if ! "$tools_dir/pwn-cleanup.sh" "$image_name"; then
      printf 'Docker 자동 정리에 실패했습니다. 풀이 결과와 종료 상태는 유지합니다.\n' >&2
    fi
  fi
  if [[ "$keep_workspace" == false && -f "$work_dir/.solved" && -x "$tools_dir/ctf-clean.sh" ]]; then
    printf '\n검증 완료 문제의 중복 작업 파일 정리 중: %s\n' "$challenge_name"
    if ! "$tools_dir/ctf-clean.sh" --apply "$challenge_name"; then
      printf '작업공간 자동 정리에 실패했습니다. 풀이 및 학습 기록은 그대로 보존됩니다.\n' >&2
    fi
  fi
  exit "$status"
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

build_status=0
if [[ -f "$input_dir/Dockerfile" ]]; then
  build_args=()
  [[ "$rebuild" == false ]] || build_args+=(--rebuild)
  set +e
  if [[ "$audit_enabled" == true ]]; then
    "$tools_dir/pwn-build.sh" "${build_args[@]}" "$input_dir" "$image_name" 2>&1 | tee "$audit_dir/docker-build.log"
    build_status=${PIPESTATUS[0]}
  else
    "$tools_dir/pwn-build.sh" "${build_args[@]}" "$input_dir" "$image_name"
    build_status=$?
  fi
  set -e
[[ $build_status -eq 0 ]] || printf 'Docker 빌드를 사용할 수 없습니다. 정적 분석만 계속하고 정확한 방해 요소를 보고합니다.\n' >&2
fi

runtime_scalar() {
  local key=$1
  [[ -f "$runtime_manifest" ]] || return 0
  awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$runtime_manifest" 2>/dev/null || true
}

runtime_status=$(runtime_scalar runtime_status)
if [[ "$runtime_status" != ready && $build_status -eq 0 ]] && docker image inspect "$image_name" >/dev/null 2>&1; then
  set +e
  if [[ "$audit_enabled" == true ]]; then
    "$runtime_tool" --input "$input_dir" --output "$runtime_output" --image "$image_name" 2>&1 | tee "$audit_dir/runtime-prepare.log"
    runtime_prepare_status=${PIPESTATUS[0]}
  else
    "$runtime_tool" --input "$input_dir" --output "$runtime_output" --image "$image_name"
    runtime_prepare_status=$?
  fi
  set -e
  [[ $runtime_prepare_status -eq 0 ]] || printf '정확한 libc/ld 자동 쌍을 완성하지 못했습니다. manifest의 출처·불일치를 유지하고 임의의 host 런타임은 사용하지 않습니다.\n' >&2
fi

runtime_status=$(runtime_scalar runtime_status)
runtime_source=$(runtime_scalar runtime_source)
printf 'libc/ld runtime: status=%s source=%s manifest=%s\n' "${runtime_status:-unavailable}" "${runtime_source:-none}" "$runtime_manifest"
export CTF_PWN_RUNTIME_DIR="$runtime_output"
export CTF_PWN_RUNTIME_MANIFEST="$runtime_manifest"
export CTF_PWN_RUNTIME_STATUS="${runtime_status:-unavailable}"
export CTF_PWN_IMAGE="$image_name"
export CTF_PWN_RUNNER="$tools_dir/pwn-run.sh"
manifest_value() {
  local key=$1
  [[ -f "$runtime_manifest" ]] || return 0
  bash -c 'set -eu; source "$1"; printf "%s" "${!2-}"' bash "$runtime_manifest" "$key"
}
runtime_libc_path=$(manifest_value libc_path)
runtime_ld_path=$(manifest_value ld_path)
runtime_local_libc_path=$(manifest_value local_libc_path)
runtime_local_ld_path=$(manifest_value local_ld_path)
runtime_target_path=$(manifest_value target_path)
if [[ -n "$runtime_libc_path" && -f "$runtime_libc_path" ]]; then
  export CTF_PWN_LIBC_PATH="$runtime_libc_path"
else
  unset CTF_PWN_LIBC_PATH 2>/dev/null || true
fi
if [[ "$runtime_status" == ready && -n "$runtime_ld_path" && -f "$runtime_ld_path" ]]; then
  export CTF_PWN_LD_PATH="$runtime_ld_path"
else
  unset CTF_PWN_LD_PATH 2>/dev/null || true
fi
if [[ -n "$runtime_local_libc_path" && -f "$runtime_local_libc_path" ]]; then
  export CTF_PWN_LOCAL_LIBC_PATH="$runtime_local_libc_path"
else
  unset CTF_PWN_LOCAL_LIBC_PATH 2>/dev/null || true
fi
if [[ -n "$runtime_local_ld_path" && -f "$runtime_local_ld_path" ]]; then
  export CTF_PWN_LOCAL_LD_PATH="$runtime_local_ld_path"
else
  unset CTF_PWN_LOCAL_LD_PATH 2>/dev/null || true
fi
if [[ -n "$runtime_target_path" && -f "$runtime_target_path" ]]; then
  export CTF_PWN_BINARY_PATH="$runtime_target_path"
else
  unset CTF_PWN_BINARY_PATH 2>/dev/null || true
fi
if [[ "$audit_enabled" == true ]]; then
  {
    printf 'runtime_final_status=%s\n' "${runtime_status:-unavailable}"
    printf 'runtime_final_source=%s\n' "${runtime_source:-none}"
  } >> "$audit_dir/run-info.txt"
fi

if [[ "$action" == prepare-only ]]; then
  [[ "$audit_enabled" == false ]] || printf 'status=prepared-only\n' >> "$audit_dir/run-info.txt"
  exit 0
fi

set +e
if [[ $build_status -eq 0 ]] && docker image inspect "$image_name" >/dev/null 2>&1; then
  if [[ "$audit_enabled" == true ]]; then
    "$tools_dir/pwn-env-preflight.sh" --image "$image_name" 2>&1 | tee "$audit_dir/preflight.log"
    preflight_status=${PIPESTATUS[0]}
  else
    "$tools_dir/pwn-env-preflight.sh" --image "$image_name"
    preflight_status=$?
  fi
elif [[ ! -f "$input_dir/Dockerfile" ]]; then
  printf 'Dockerfile과 캐시 이미지가 없어 STATIC-ONLY로 계속합니다.\n'
  preflight_status=0
else
  "$tools_dir/pwn-env-preflight.sh"
  preflight_status=$?
fi
set -e
[[ $preflight_status -eq 0 ]] || printf '사전 점검에서 방해 요소가 발견됐습니다. Codex는 정적 분석만 계속할 수 있으며 대상 파일을 호스트에서 실행하면 안 됩니다.\n' >&2

[[ -n "$codex_bin" ]] || { echo 'Codex CLI를 사용할 수 없습니다.' >&2; exit 69; }
process_run_id="ctf-$challenge_name-$(date -u +%Y%m%dT%H%M%SZ)-$$"
export CTF_PWN_RUN_ID="$process_run_id"
if [[ "$audit_enabled" == true ]]; then
  log_config="log_dir=\"$audit_dir/tui\""
  set +e
  "$codex_bin" -C "$agent_root" --model "$codex_model" \
    -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    -c "service_tier=\"$codex_service_tier\"" --enable fast_mode \
    "${codex_offline_args[@]}" \
    --sandbox "$sandbox_mode" --ask-for-approval "$approval_policy" -c "$log_config" "$prompt"
  codex_status=$?
  set -e
  printf 'finished_utc=%s\ncodex_exit_status=%s\nstatus=finished\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$codex_status" >> "$audit_dir/run-info.txt"
  exit "$codex_status"
fi

set +e
"$codex_bin" -C "$agent_root" --model "$codex_model" \
  -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
  -c "service_tier=\"$codex_service_tier\"" --enable fast_mode \
  "${codex_offline_args[@]}" \
  --sandbox "$sandbox_mode" --ask-for-approval "$approval_policy" "$prompt"
codex_status=$?
set -e
exit "$codex_status"
