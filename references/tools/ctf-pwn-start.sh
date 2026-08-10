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
  CTF_CODEX_REASONING_EFFORT  추론 강도(기본 ultra)
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
runtime_output="$work_dir/runtime"
runtime_manifest="$runtime_output/runtime.env"
image_slug="$(printf '%s' "$challenge_name" | tr '[:upper:]_.' '[:lower:]--')"
image_name="ctf-$image_slug:local"
codex_bin=${CODEX_BIN:-}
codex_model=${CTF_CODEX_MODEL:-gpt-5.6-sol}
codex_reasoning_effort=${CTF_CODEX_REASONING_EFFORT:-ultra}
codex_service_tier=${CTF_CODEX_SERVICE_TIER:-fast}

if [[ ! "$codex_service_tier" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf '잘못된 Codex 서비스 티어입니다: %s\n' "$codex_service_tier" >&2
  exit 65
fi

if [[ -f "$source_dir/Dockerfile" || -f "$input_dir/Dockerfile" ]]; then
  runtime_mode=supplied-docker
  runtime_prompt="제공된 Dockerfile과 이미지 $image_name을 사용하라. 빌드는 pwn-build.sh, 실행은 pwn-run.sh로만 수행하라."
elif docker image inspect "$image_name" >/dev/null 2>&1; then
  runtime_mode=cached-docker
  runtime_prompt="Dockerfile은 없지만 캐시 이미지 $image_name이 있다. 재빌드를 시도하지 말고 pwn-run.sh로 캐시 이미지만 사용하라."
else
  runtime_mode=static-only
  runtime_prompt="Dockerfile과 캐시 이미지가 모두 없으므로 STATIC-ONLY로 즉시 계속하라. pwn-triage.sh, 소스 및 disassembly로 분석하고 Docker 빌드·pull·재시도나 임시 Dockerfile 생성을 하지 마라. 바이너리를 호스트에서 실행하지 말고 Dockerfile 부재만으로 Deep 모드로 전환하지 마라. 동적 실행이 실제로 필수일 때만 정적 결과와 필요한 정확한 런타임을 blocker로 보고하라."
fi

[[ -d "$agent_root" ]] || { printf 'CTF Agent 루트가 존재하지 않습니다: %s\n' "$agent_root" >&2; exit 66; }
[[ -f "$runtime_tool" ]] || { printf 'pwn runtime 준비 도구가 없습니다: %s\n' "$runtime_tool" >&2; exit 66; }
[[ -d "$source_dir" || -f "$source_zip" ]] || {
  printf '문제를 찾을 수 없습니다. 다음 중 하나가 필요합니다:\n  %s\n  %s\n' "$source_dir" "$source_zip" >&2
  exit 67
}

if [[ -z "$codex_bin" && -x "$HOME/.local/bin/codex" ]]; then
  codex_bin="$HOME/.local/bin/codex"
elif [[ -z "$codex_bin" ]]; then
  codex_bin="$(command -v codex 2>/dev/null || true)"
fi

case "$solve_mode" in
  adaptive)
    mode_prompt=$(cat <<'EOF'
실행 모드는 ADAPTIVE다. P0-Lite에서 허가 범위, 파일 목록, 대상/빌드/런타임 네트워크 구분을 확인하고 P1은 이미 pwn으로 분류된 것으로 처리하라. 빠른 탐색은 약 10분, 주요 도구 호출 8회, 가설 3개, 익스플로잇 실패 2회로 제한한다. pwn-triage.sh는 한 번만 실행하고 사용 가능한 런타임이 있을 때만 캐시된 Docker 이미지를 재사용하라. 저비용 검사 2회가 실패하기 전에는 GDB를 사용하지 말고 notes/todo/명령 로그를 계속 갱신하지 마라.

공식 원격 endpoint가 없고 동적 런타임이 있으면 재현 가능한 solve.py의 깨끗한 Docker 성공 2회와 음성 대조군 1회를 기존 P4 증거로 P5-Lite에 전달하라. 공식 원격 endpoint가 있으면 아래 Fast-to-Remote 규칙이 이 반복 검증보다 우선한다. 런타임이 없더라도 정적으로 exploit chain과 solver를 완성할 수 있으면 원격 첫 시도를 막지 말고, 그 외에는 아래 STATIC-ONLY 검증 규칙을 적용한다. 소스 부재, stripped 또는 강한 난독화, heap/race/확률적 동작, 런타임 외의 프로토콜 불확실성, 로컬과 공식 환경의 차이, 익스플로잇 2회 실패 또는 빠른 탐색 예산 소진이 발생하면 작업을 재시작하지 말고 전체 P0~P6으로 전환하라.
EOF
)
    ;;
  fast-only)
    mode_prompt=$(cat <<'EOF'
실행 모드는 FAST-ONLY다. P0-Lite를 완료하고 이미 pwn으로 분류됐으므로 P1 분류를 생략하라. 빠른 탐색은 약 10분, 주요 도구 호출 8회, 가설 3개, 익스플로잇 실패 2회로 제한한다. 저비용 검사 2회가 실패하기 전에는 GDB를 사용하지 말고 지속적인 진행 기록을 만들지 마라. 성공 조건을 충족하지 못하면 자동 전환하지 말고 정확한 방해 요소와 다음 Deep 단계만 한국어로 보고하라.
EOF
)
    ;;
  deep)
    mode_prompt=$(cat <<'EOF'
실행 모드는 DEEP이다. 전체 P0~P6 절차를 수행하되 결정적 triage/build/run 하니스와 기존 결과를 재사용하라. 모든 실행은 P4만 담당하고 P5는 기존 증거만 검증한다. 추가 검사가 필요하면 P5가 명령이나 네트워크 접근을 직접 만들지 말고 P4에 검사 요청을 반환하라.
EOF
)
    ;;
esac

if [[ "$runtime_mode" == static-only ]]; then
  mode_prompt+=$'\nSTATIC-ONLY에서는 Docker 성공 2회 조건을 적용하지 않는다. 대신 source/disassembly에서 primitive와 계산을 독립적으로 교차 확인하고, 실행 없이 증명 가능한 범위까지 solver를 작성하라. 동적 검증이 없어 확정할 수 없는 부분만 명확히 표시하라.'
  if [[ -n "$remote_host" ]]; then
    mode_prompt+=$'\n공식 원격 endpoint가 있으므로 Dockerfile·캐시 이미지·로컬 플래그를 선행조건으로 삼지 마라. 정적으로 exploit chain과 I/O framing을 교차 확인하고 solver 문법 검사를 마치면 challenge 바이너리를 호스트에서 실행하지 않은 채 remote client branch만 bounded harness로 즉시 실행하라.'
  fi
  input_prompt="잘못된 scanf/printf 계열 가변 인자 호출은 변환 지정자 수와 전달된 포인터 수를 정적으로 비교하고 필요한 delimiter/EOF/half-close 프레이밍을 solver에 명시하라. 컨테이너가 없다는 이유로 기다리거나 임의 환경에서 동작을 일반화하지 마라."
else
  input_prompt="잘못된 scanf/printf 계열 가변 인자 호출은 변환 지정자 수와 전달된 포인터 수를 비교하고, 광범위한 libc 분석 전에 공식 컨테이너에서 제한된 구분자/EOF/half-close 조합을 검사하라. 제공된 Docker 환경을 기준으로 삼고 무관한 libc 버전까지 호환성을 증명하려 하지 마라."
fi

prompt=$(cat <<EOF
\$ctf-pwn

허가된 로컬 pwnable 문제 '$challenge_name' 풀이를 시작하라.
입력 파일은 challenges/$challenge_name/input에 있다. Deep 또는 Audit 모드에서 추가 자료가 꼭 필요한 경우가 아니면 work 아래에 최종 solver와 간결한 write-up만 작성하라.

사용자에게 보이는 모든 진행 상황, 판단 근거, 오류, 질문 및 최종 답변은 한국어로 작성하라. 명령어, 코드, 파일명, 심볼 및 원문 오류 메시지만 정확성을 위해 원래 표기를 유지할 수 있다.

$mode_prompt

$runtime_prompt Docker를 사용하는 경우 빌드 네트워크는 대상 트래픽과 별개이며, 문제 실행에는 반드시 --network none을 사용하라. 원격 대상은 허가되지 않았다. 문제 바이너리를 호스트에서 실행하거나 플래그를 자동 제출하지 마라.

$input_prompt
EOF
)

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

허가된 로컬 문제 '$challenge_name' 풀이를 시작하라.
- 입력: challenges/$challenge_name/input
- 설정: mode=$solve_mode, runtime=$runtime_mode
- 기준: AGENTS.md, rules/ruleset.md, pwn-agent/skills/SKILL.md, pwn-agent/docs/playbook.md
- 런타임: $compact_runtime
- libc/ld 선행: work/runtime/runtime.env를 가장 먼저 읽어라. libc_path가 있으면 원격 심볼·오프셋 계산에 우선 사용하고, runtime_status=ready일 때만 canonical libc.so.6+ld.so를 pwn-run.sh --runtime-dir ... --binary ...로 함께 로컬 적용하라. host libc나 검증되지 않은 혼합 쌍은 금지하며 partial/incompatible은 STATIC-ONLY와 허가된 원격 첫 시도를 막지 않는다.
- 가젯 탐색: 필요한 의미를 먼저 정한 뒤 references/tools/pwn-gadget-index.sh <binary> work/cache를 메인 ELF에 한 번만 실행하고 Build-ID 캐시를 재사용하라. pivot이 확인됐는데 필수 pop 가젯이 없으면 gadget-scarcity=confirmed로 확정하고 반복 검색 대신 PLT/GOT·간접 호출·leak/base·ret2dlresolve 설계로 즉시 전환하라. libc 가젯은 구체적인 libc base 확보 전략이 생긴 뒤에만 좁게 검색하라.
- 범위: 호스트 바이너리 실행과 플래그 자동 제출 금지
- 정리: Dockerfile 기반 문제의 컨테이너와 $image_name 이미지는 Codex 종료 후 런처가 자동 정리함
- 결과: 한국어로 진행하며 work/solve.py와 간결한 work/writeup.md만 기본 생성
- 완료 표식: 로컬 또는 공식 원격에서 플래그를 실제 검증한 뒤에만 work/.solved에 verified 한 줄을 기록
- 기억: 시작 시 work/state.json과 pwn-agent/feedback/index.md를 먼저 읽고, 복합 exploit은 pwn-checkpoint.sh로 결정적 단계만 기록하여 마지막 실패 단계부터 재개
- 로그: 로컬 런타임이 있으면 첫 원격 시도 전 1MiB 이하의 로컬 성공 transcript와 runtime 출처를 남기고, 없으면 간결한 정적 교차 확인만 남겨라. 원격 로그는 기본 1MiB 상한을 지켜라
EOF
)

if [[ "$keep_docker" == true ]]; then
  prompt+=$'\n- 정리 예외: 사용자가 --keep-docker를 지정했으므로 문제 컨테이너와 이미지를 보존하라.'
fi

if [[ -n "$remote_host" ]]; then
  prompt+=$(cat <<EOF

- 공식 원격 범위: TCP $remote_host:$remote_port 한 곳만 사용 허가됨
- Fast-to-Remote: 정확한 로컬 런타임이 있으면 로컬 플래그 1회 후, 없으면 정적 primitive·offset·주소·I/O framing 교차 확인과 solver 문법 검사 후 즉시 references/tools/pwn-remote-run.sh로 첫 원격 exploit을 실행하라. Dockerfile·캐시 이미지·로컬 플래그는 런타임 부재 시 선행조건이 아니다. 두 번째 로컬 성공, 음성 대조군, P5 및 write-up을 기다리지 마라.
- 원격 절차: work/solve.py를 pwntools 표준 인자 REMOTE HOST=$remote_host PORT=$remote_port와 호환되게 하고 첫 원격 시도를 즉시 수행하라. challenge 바이너리는 호스트에서 실행하지 않되 생성한 remote client는 이 endpoint에 한해 실행할 수 있다. 실패한 경우에만 환경 차이를 분석하고 수정된 exploit으로 두 번째 시도를 허용한다.
- 플래그 출력: solve.py는 challenge의 flag format으로 검증한 플래그를 얻었을 때만 FLAG=<원문> 한 줄을 stdout에 출력하고 즉시 연결을 닫고 종료하라. 하니스가 출력하는 '획득한 플래그: <원문>'과 '원격 플래그 획득 시간: N.NNN초'를 즉시 사용자에게 보여 주고 최종 답변에도 둘 다 포함하라. 파일 경로만 알려 주거나 출력을 P5까지 미루지 마라.
- 원격 증거: 결정적 transcript와 플래그 후보를 evidence/private에 저장하고 공개용 writeup에는 플래그 원문을 넣지 마라. 실패하면 무차별 대입·포트 탐색·다른 호스트 접속 없이 차이와 blocker만 보고하라.
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
    printf 'allowed_attempts=2\n'
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
if [[ "$runtime_mode" == supplied-docker && "$keep_docker" == false ]]; then
  cleanup_enabled=true
fi

cleanup_on_exit() {
  local status=$?
  trap - EXIT INT TERM HUP
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
if [[ "$audit_enabled" == true ]]; then
  log_config="log_dir=\"$audit_dir/tui\""
  set +e
  "$codex_bin" -C "$agent_root" --model "$codex_model" \
    -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    -c "service_tier=\"$codex_service_tier\"" --enable fast_mode \
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
  --sandbox "$sandbox_mode" --ask-for-approval "$approval_policy" "$prompt"
codex_status=$?
set -e
exit "$codex_status"
