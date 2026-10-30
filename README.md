# ctf-agent

Codex CLI에서 로컬 CTF 문제를 분야별 에이전트와 재현 가능한 절차로 분석하기 위한 작업 공간입니다.

## 주요 기능

- `ctf-pwn`: pwn 문제 복사, Adaptive Fast→Deep 풀이, Docker 또는 STATIC-ONLY 실행
- pwn 문제의 제공 `libc`·`ld`를 우선 적용하고, 부족할 때만 정확한 Docker 이미지에서 검증된 한 쌍 추출
- `ctf-rev`: 리버싱 문제 복사, 전체 동작 분석보다 최단 플래그 추출을 우선하는 Adaptive Fast→Deep 분석, 격리 실행 강제
- rev Fast Probe는 `rev-fast-probe.sh`로 인테이크 경로와 최초 출력량을 고정하며, 큰 blob 전체가 아닌 참조된 offset 주변만 분석
- `ctf-learn`: 완료된 풀이에서 검증된 재사용 교훈만 분야별 피드백에 축적
- `ctf-writeup`: 검증 완료된 solver와 보존 자료를 공개용·플래그 비공개 Markdown write-up으로 정리
- `ctf-clean`: 학습·풀이 결과를 보존하면서 중복 입력, 실행 로그와 재생성 캐시 정리
- 복합 pwn 문제의 최근 20단계 체크포인트와 1MiB 원격 transcript 상한
- `ctf-pwn`, `ctf-rev`, `ctf-web`은 기본적으로 `gpt-5.6-sol` + `max` 추론을 사용하고 `fast` 서비스 티어와 Fast mode를 유지
- `ctf-learn-*`은 불필요한 비용을 줄이기 위해 `low` 추론 + `fast` 서비스 티어를 사용
- `ctf-export`: 원본을 수정하지 않고 GitHub 공개용 복사본과 로컬 커밋 생성
- pwn, reverse engineering, web, crypto, forensics/misc 라우팅
- 신뢰할 수 없는 실행 파일의 호스트 실행 금지와 Docker 네트워크 격리

## WSL 설치

```bash
git clone https://github.com/no1pjw/ctf_agent.git
cd ctf_agent
./install-wsl.sh
```

기본 문제 루트는 Windows의 `C:\Users\JW\Desktop\agents\ctf_seeds`이며 WSL에서는 `/mnt/c/Users/JW/Desktop/agents/ctf_seeds`로 접근합니다. 분야별 문제는 `pwn`, `rev`, `web`, `crypto`, `forensics` 하위 폴더에 둡니다.

```text
C:\Users\JW\Desktop\agents\ctf_seeds\
├── pwn\baby-bof\
├── rev\crackme\
└── web\web-test\
```

런처는 이 위치에서 문제를 찾아 WSL 내부의 `~/workspace/CTF/ctf-agent/challenges/<문제명>/input`으로 복사한 뒤 분석합니다. 공통 루트를 바꾸려면 `CTF_SEEDS_ROOT`를 지정하고, 특정 분야만 바꾸려면 기존 분야별 환경 변수를 지정합니다.

```bash
export CTF_SEEDS_ROOT=/path/to/ctf_seeds
# 또는 pwn만 변경
export CTF_PWNABLE_SOURCE=/path/to/pwn
```

## 사용

```bash
ctf-pwn challenge-name
ctf-pwn --extra-prompt challenge-name
ctf-pwn --verbose challenge-name
ctf-pwn --no-skill challenge-name
ctf-pwn --fast-only challenge-name
ctf-pwn --deep challenge-name
ctf-pwn --keep-docker challenge-name
ctf-pwn challenge-name host.example:31337
ctf-pwn challenge-name host.example 31337
ctf-rev --source /path/to/reversing challenge-name
ctf-rev --extra-prompt challenge-name
ctf-rev --verbose challenge-name
ctf-rev --no-skill challenge-name
ctf-rev --fast-only --source /path/to/reversing challenge-name
ctf-rev --deep --source /path/to/reversing challenge-name
ctf-rev --prepare-only --source /path/to/reversing challenge-name
ctf-web --source /path/to/web challenge-name
ctf-web --verbose --source /path/to/web challenge-name
ctf-web --no-skill --source /path/to/web challenge-name
ctf-web --source /path/to/web --port 8080 challenge-name
ctf-web challenge-name https://challenge.example:8443/
ctf-web --extra-prompt challenge-name https://challenge.example:8443/
ctf-pwn-claude challenge-name host.example:31337
ctf-pwn-claude --no-skill challenge-name host.example:31337
ctf-rev-claude --source /path/to/reversing challenge-name
ctf-web-claude --source /path/to/web challenge-name
ctf-pwn-mix --description /path/to/problem.md challenge-name host.example:31337
ctf-pwn-mix --no-skill challenge-name host.example:31337
ctf-bench-pwn --source /path/to/pwn challenge-name
ctf-bench-pwn --verbose challenge-name host.example:31337
ctf-bench-pwn --extra-prompt challenge-name host.example:31337
ctf-bench-pwn --remote host.example:31337 challenge-name
ctf-bench-rev --source /path/to/rev challenge-name
ctf-bench-rev --extra-prompt challenge-name
ctf-bench-web --source /path/to/web challenge-name
ctf-bench-crypto --source /path/to/crypto challenge-name
ctf-bench-forensics --source /path/to/forensics challenge-name
ctf-learn challenge-name
ctf-learn-pwn challenge-name
ctf-learn-rev challenge-name
ctf-learn-web challenge-name
ctf-writeup challenge-name
ctf-writeup --no-skill challenge-name
ctf-writeup --force challenge-name
ctf-clean
ctf-clean --caches --apply
```

`ctf-pwn`, `ctf-rev`, `ctf-bench-pwn`, `ctf-bench-rev`에 `--extra-prompt`를 지정하면 여러 줄 지시를 입력할 수 있습니다. 붙여넣기가 끝나면 새 줄에 `.end`를 입력하거나 `Ctrl+D`로 종료하며, 생략하려면 바로 `.end`를 입력합니다. 벤치마크에서는 전체 문장을 LUNA·TERRA·SOL 세 모델에 동일하게 전달하고 실행별 prompt 파일에도 보존합니다. 자동화에서는 줄바꿈이 포함된 `CTF_EXTRA_PROMPT` 환경 변수를 사용할 수 있습니다. 추가 지시는 기존 CTF 범위·격리·안전 규칙을 완화할 수 없습니다.

`ctf-pwn`, `ctf-rev`, `ctf-web`은 기본적으로 비대화형 실행이지만 Codex가 작업 시작과 주요 단계 전환에서 현재 하는 일과 다음 행동을 짧게 알립니다. 실제 명령과 도구 결과까지 봐야 할 때 `--verbose`를 지정합니다. `ctf-bench-*`는 경쟁 진행을 확인할 수 있도록 세 모델의 의미 있는 행동 로그를 기본 표시하며, `CTF_BENCH_QUIET=true`로 최종 표만 남길 수 있습니다.

분야별 `SKILL.md` 없이 원시 모델 성능을 확인하려면 일반 풀이, Claude 단독, Claude→Codex mix 또는 `ctf-compare-*`에 `--no-skill`을 지정합니다. Codex 실행에서는 발견된 skills와 프로젝트 `AGENTS.md` 주입을 그 실행에만 비활성화하고, Claude 실행에서는 `--safe-mode`와 slash command 비활성화를 사용합니다. 전역 설정이나 설치된 스킬 파일은 수정하지 않으며 다음 기본 실행은 다시 스킬을 사용합니다. 자동화에서는 `CTF_USE_SKILL=false`를 사용할 수 있습니다. 범위·격리·성공 판정 같은 최소 안전 계약은 런처 프롬프트에 직접 유지됩니다.

동일 문제에서 Codex 단독과 Claude→Codex의 성공 여부, 전체 시간, 단계 시간, 토큰을 비교하려면 `ctf-compare-pwn`, `ctf-compare-rev`, `ctf-compare-web`을 사용합니다. 두 방식은 동일 원본을 별도 작업공간에서 순차 실행하고 `benchmarks/comparisons/<분야>/<run-id>/report.md`에 표를 저장합니다. 예: `ctf-compare-pwn podnote host3.dreamhack.games:12995`.

`ctf-pwn-claude`, `ctf-rev-claude`, `ctf-web-claude`는 Claude가 분석부터 solver 작성과 검증까지 단독 수행합니다. `ctf-pwn-mix`, `ctf-rev-mix`, `ctf-web-mix`는 Claude가 먼저 읽기 전용 정적 triage를 수행해 `work/claude-handoff.md`를 만들고, Codex가 이를 독립적으로 검증해 solver와 exploit을 완성하는 순차 모드입니다. Claude의 기본 모델은 Opus 4.6, effort는 `max`, 단계별 제한은 600초입니다. 모델·effort·제한 시간은 `CTF_CLAUDE_MODEL`, `CTF_CLAUDE_EFFORT`, `CTF_CLAUDE_TIMEOUT_SECONDS`로 바꿀 수 있습니다.

Claude 단독과 mix의 Claude 단계는 비대화형 승인 대기로 멈추지 않도록 `bypassPermissions` Full Access로 실행됩니다. Codex 단계도 `danger-full-access`와 승인 정책 `never`를 사용합니다. 권한 승인은 생략되지만 공식 CTF 대상, 격리 하니스, 원격 범위 제한은 계속 적용됩니다.

Claude→Codex `ctf-*-mix` 명령은 TTY에서 기본적으로 전체 화면형 스트림 UI를 사용합니다. 준비, Claude triage, Codex 검증, 재검토·재시도 단계가 같은 터미널 화면을 순차 교체하며 Claude 원본 이벤트는 `work/claude-events-*.jsonl`에 유지됩니다. 기존 일반 출력으로 즉시 되돌리려면 `--no-stream-ui`를 붙이거나 `CTF_STREAM_UI=false`를 지정합니다.

```bash
ctf-pwn-mix --no-stream-ui challenge-name host.example:31337
CTF_STREAM_UI=false ctf-pwn-mix challenge-name host.example:31337
```

일반 `ctf-pwn`, `ctf-rev`, `ctf-web`도 실행이 끝나면 Codex 실행의 총 소요 시간을 `HH:MM:SS`와 초 단위로 표시하고, JSONL의 `turn.completed.usage`를 합산해 입력·캐시 입력·출력·추론 출력·총 토큰을 표시합니다. `--audit` 실행은 원본 JSONL도 해당 문제의 audit 디렉터리에 `codex-events.jsonl`로 보존합니다. 완료 이벤트가 오기 전에 프로세스가 중단되면 토큰을 0으로 표시하지 않고 `미집계`로 표시합니다.

`ctf-learn-pwn`, `ctf-learn-rev`, `ctf-learn-web`은 분야가 명령 이름에 고정된 학습 명령입니다. 각각 `pwn-agent/feedback`, `rev-agent/feedback`, `web-agent/feedback`만 수정하며 `--category`로 다른 분야에 우회할 수 없습니다. 기존 `ctf-learn --category <분야> 문제명`도 계속 사용할 수 있습니다.

`ctf-writeup <문제명>`은 `work/.solved=verified`인 문제만 받아 `work/solve.py` 또는 `work/recover.py`와 최소 보존 자료를 읽고 `work/writeup.md`를 생성합니다. 문제·solver·Docker를 다시 실행하지 않고 네트워크도 사용하지 않습니다. 공개본이 기본이므로 flag payload, 토큰, 개인 절대경로와 원시 transcript는 저장 전에 한 번 더 결정적으로 가립니다. 기존 문서는 자동으로 덮어쓰지 않으며 `--force`를 지정하면 시간표시가 붙은 백업을 남긴 뒤 교체합니다. `--no-skill`과 `CTF_USE_SKILL=false`도 지원하며, 생성 시간과 토큰은 `work/writeup-usage.json`에 기록됩니다.

## 벤치마크

벤치마크는 더 이상 plain/FAST_LOCAL 순차 비교가 아니라 LUNA·TERRA·SOL max 모델의 병렬 경쟁입니다. 첫 플래그 포착 시 승자와 플래그를 즉시 출력하고 나머지 모델을 중단합니다. 토큰 수는 플래그 직전까지 도착한 `turn.completed.usage`만 집계되며, 조기 종료로 usage가 없으면 `미집계`로 표시합니다.

`ctf-bench-pwn <문제 이름> <HOST:PORT>`는 같은 문제를 `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.6-sol` 세 모델로 동시에 실행합니다. 모두 `max` 추론 강도와 fast service tier, 동일한 ctf Agent·skill·feedback 컨텍스트를 사용합니다. 문제 입력과 공용 Docker 이미지·libc/ld 런타임은 동일하게 제공하지만 작업공간·Codex 홈·실행 컨테이너는 모델별로 격리합니다. 셋 중 하나가 명시적인 로컬 `FLAG=` 또는 원격 하니스 플래그를 포착하면 해당 모델을 승자로 즉시 로그에 출력하고 나머지 Codex 프로세스 그룹을 종료합니다. 전체 JSONL은 파일에 보존하고, 터미널에는 기본적으로 시작·승자·최종 비교표만 표시하며 중간 행동 로그는 `--verbose`에서만 표시합니다.

각 Codex 실행은 systemd memory scope에서 기본 `MemoryHigh=1536MiB`, `MemoryMax=2048MiB`, `MemorySwapMax=512MiB`로 제한됩니다. JSONL 집계도 전체 파일을 메모리에 올리지 않고 스트리밍하므로 긴 max-effort 실행에서 메모리가 수 GB까지 증가하는 현상을 막습니다. 필요할 때만 `CTF_BENCH_MEMORY_HIGH_MB`와 `CTF_BENCH_MEMORY_MAX_MB`로 조정합니다.

벤치마크는 시작 직전 Docker 컨테이너·이미지 ID를 기록합니다. 정상 종료, 실패, 사용자 중단 여부와 관계없이 이번 실행에서 생긴 컨테이너와 교체된 이전 캐시 이미지·불필요한 중간 이미지를 정리합니다. 문제별 `ctf-bench-cache-<category>-<challenge>:local` 공용 이미지는 다음 실행의 Docker 레이어 캐시로 한 개만 유지합니다. 같은 문제를 다시 벤치마크하면 Dockerfile을 다시 평가하되 변경되지 않은 QEMU 같은 대형 설치 레이어는 재사용합니다.

```bash
ctf-bench-pwn --source /path/to/challenge challenge-name
ctf-bench-pwn --remote host.example:31337 challenge-name
ctf-bench-pwn challenge-name host.example:31337
ctf-bench-pwn --no-exact-tokens --remote host.example:31337 challenge-name
ctf-bench-rev --source /path/to/challenge challenge-name
ctf-bench-web --source /path/to/challenge challenge-name
ctf-bench-crypto --source /path/to/challenge challenge-name
ctf-bench-forensics --source /path/to/challenge challenge-name
# 자동 종료가 꼭 필요할 때만 명시
ctf-bench-pwn --timeout 2400 challenge-name
```

Pwn 벤치는 현재 `ctf-pwn`과 같은 런타임 준비 과정을 먼저 수행합니다. 제공 libc/ld를 우선 사용하고, 누락되면 정확한 Docker 이미지에서 추출하며, 제공 libc가 이미지 libc와 다르면 원격 계산용 제공 libc와 로컬 구조 검증용 이미지 libc/ld를 섞지 않고 분리합니다. 새 solver 버전이 로컬에서 성공할 때마다 즉시 같은 버전을 정확한 원격 주소에 동기화합니다. 고정된 총 시도 제한은 없지만 변경 없는 자동 반복·무차별 대입·flood는 금지합니다. 하니스가 실제 원격 플래그를 포착하는 순간 성공으로 기록하고 재검증·writeup·`.solved` 판정 없이 종료합니다. `--remote`는 pwn 벤치에서만 사용할 수 있습니다.

결과는 `benchmarks/runs/<category>/<run-id>/report.md`와 각 실행의 JSONL 이벤트에 남습니다. 기본 제한 시간은 `0`, 즉 풀이 중 자동 종료 없음이며 사용자가 `--timeout`을 준 경우만 제한합니다. 경쟁 모드에서는 플래그 포착 시각을 즉시 성공 시각으로 고정하고 추가 도구 실행을 허용하지 않으며, 나머지 모델 프로세스도 즉시 종료합니다. 조기 종료로 usage가 도착하지 않으면 토큰을 거짓 `0` 대신 `미집계`로 표시합니다. `ctf-bench-pwn --dry-run challenge-name`처럼 모델 호출 없이 분야·설정·범위를 먼저 확인할 수 있습니다.

`ctf-rev`는 입력을 복사한 뒤 실행 없이 형식·아키텍처·런타임 후보를 `work/intake-exec.txt`에 기록하고, 가장 짧은 복원 경로를 `work/recover.py`에 구현합니다. 제공된 Dockerfile은 Codex 시작 전에 한 번 빌드하며, rev 전용 runner가 입력을 `/ctf-input`에 읽기 전용으로 마운트하여 네트워크가 차단된 일회용 컨테이너에서만 동적 검증합니다. Dockerfile과 정확한 캐시 이미지가 없거나 빌드가 실패하면 호스트 실행 없이 STATIC-ONLY로 계속합니다. 기본 원본 경로는 `$CTF_SEEDS_ROOT/rev`이며 다른 위치는 `--source` 또는 `CTF_REV_SOURCE`로 지정합니다. 검증된 flag는 문서 작업보다 먼저 출력하고 즉시 종료합니다.

`ctf-bench-rev`도 동일한 세 모델 경쟁 구조를 사용합니다. 각 모델은 실제 `ctf-rev`와 같은 루트 `AGENTS.md`, `$ctf-rev` 스킬, rev 피드백, intake를 받으며, 먼저 검증된 `FLAG=`를 출력한 모델이 승리합니다. Dockerfile은 한 번만 빌드하여 세 모델이 같은 불변 이미지를 공유하되 실행 컨테이너와 작업공간은 분리합니다.

`ctf-web`은 white-box와 black-box Web CTF를 모두 지원합니다. 제공된 Compose 파일(`compose.yaml`, `compose.yml`, `docker-compose.yml`, `docker-compose.yaml`)을 가장 먼저 사용하고, 없으면 `Dockerfile`을 빌드해 서비스를 Codex보다 먼저 시작합니다. 원격 URL을 함께 주면 로컬에서 검증한 최소 solver를 같은 원격 문제에 즉시 재생하며, 소스나 Docker가 없어도 정확히 기록된 HTTP(S) origin에서 저소음 black-box 풀이를 계속합니다. 첫 응답에서 forms·scripts·same-origin links·endpoint hints를 추출한 뒤 관찰된 경로만 baseline/단일 mutation 방식으로 시험하며, 서브도메인·포트 스캔, 일반 wordlist, 외부 callback과 write-up 검색은 사용하지 않습니다.

Compose는 disposable 소스 복사본에서 실행하며 포트를 `127.0.0.1`의 임의 포트로 다시 묶고 runtime Docker 네트워크를 internal로 바꿉니다. privileged/host namespace/device/external network 및 작업 복사본 밖 bind mount는 거부합니다. 로컬/원격 scope는 `work/web-runtime.env`, `scope/web-scope.env`, `CTF_WEB_TARGET_URL`, `CTF_WEB_SCOPE_ORIGIN`에 기록됩니다. 종료 시 해당 Compose 프로젝트·볼륨·로컬 이미지 또는 단일 컨테이너·네트워크·이미지만 정리하며 `--keep-docker`로 보존할 수 있습니다.

```bash
ctf-web --source /path/to/web challenge-name
ctf-web --source /path/to/web --port 8080 challenge-name
ctf-web challenge-name https://challenge.example:8443/
ctf-web --source /path/to/web challenge-name https://challenge.example:8443/
ctf-web --deep --keep-docker --source /path/to/web challenge-name
```

일반 풀이 `ctf-pwn`, `ctf-rev`, `ctf-web`과 모든 `ctf-bench-*` 변형은 추론 강도 `max`를 사용합니다. 학습 명령 `ctf-learn-*`만 `low`를 사용합니다. 모두 `service_tier="fast"`와 `fast_mode`를 명시적으로 적용합니다. 일반 풀이를 일시적으로 변경해야 할 때만 `CTF_CODEX_MODEL`, `CTF_CODEX_REASONING_EFFORT`, `CTF_CODEX_SERVICE_TIER` 환경 변수를 지정합니다.

`ctf-clean`은 기본적으로 미리보기만 수행합니다. `--apply`를 지정해도 `ctf-learn` 피드백, `work/solve.py`, `work/recover.py`, `work/writeup.md`, `evidence/private`, `scope`는 항상 보존합니다. 문제의 `input/`은 풀이가 완료됐고 외부 원본 경로가 실제로 확인될 때만 삭제합니다. `--caches`는 다시 내려받거나 생성할 수 있는 Go 빌드, pip, uv 캐시만 추가로 정리하며 설치된 도구와 라이브러리는 제거하지 않습니다.

WSL 내부 파일을 삭제해도 `ext4.vhdx`의 Windows 실제 크기가 줄지 않으면 관리자 PowerShell에서 다음 스크립트를 실행합니다. 정확한 배포판 VHDX를 검증하고 WSL을 정상 종료한 뒤 빈 블록만 압축하며, 위험한 sparse 옵션은 사용하지 않습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\references\tools\ctf-compact-wsl.ps1
```

공식 CTF pwn 서비스 주소를 함께 주면 정확한 로컬 런타임에서 새롭게 성공한 solver 버전마다 즉시 같은 버전을 원격 실행해 로컬·원격 차이를 확인합니다. 고정 시도 횟수 제한은 없습니다. 정확한 로컬 런타임이 없으면 정적 exploit chain 교차 확인과 문법 검사를 통과한 첫 버전 및 이후 실질적으로 수정된 버전을 원격 실행합니다. 변경 없는 exploit 자동 반복, 무차별 대입, 병렬 flood는 하지 않습니다. 검증된 원격 플래그와 실행 시작부터 수신까지의 시간은 즉시 `획득한 플래그: ...`, `원격 플래그 획득 시간: N.NNN초`로 출력하고 `challenges/<name>/evidence/private/`에도 저장합니다. 공개 write-up에서는 원문을 가리며 scoreboard에는 자동 제출하지 않습니다. 주소를 생략하면 대상 네트워크는 계속 차단됩니다.

`ctf-pwn`은 분석 전에 `work/runtime/runtime.env`를 만듭니다. 문제에 `libc.so.6`와 loader가 있으면 원본을 건드리지 않고 우선 복사해 사용합니다. 한쪽이 없으면 제공된 Dockerfile로 만든 정확한 이미지 또는 이미 존재하는 문제 이미지에서 libc와 loader를 추출하고, Build ID나 파일 일치가 확인된 경우에만 서로 결합합니다. 둘이 다르면 제공 libc와 이미지 쌍을 비교용으로 분리 보존하고 어느 쪽도 원격과 동일한 정확한 로컬 런타임으로 가장하지 않으며, host libc로 대체하지 않습니다. 정확한 로컬 실행은 `pwn-run.sh --runtime-dir ... --binary ...`가 격리 컨테이너 안에서 loader와 libc를 함께 적용합니다. Docker/runtime 확보 실패는 STATIC-ONLY 분석과 허가된 첫 원격 시도를 막지 않습니다.

Dockerfile이 제공된 문제는 풀이의 성공·실패·중단 여부와 관계없이 종료할 때 해당 문제 컨테이너와 `ctf-<challenge>:local` 이미지를 자동 삭제합니다. 디버깅을 위해 보존해야 할 때만 `--keep-docker`를 지정합니다. 다른 이미지, 컨테이너, 볼륨과 base image는 삭제하지 않습니다.

GitHub 공개 준비본을 만들 때는 커밋 메시지를 지정합니다. 기본값은 로컬 커밋까지만 수행합니다.

```bash
ctf-export -m "Initial public release"
```

검토 없이 자동 push되지 않도록 `--push`를 명시한 경우에만 원격 `main` 브랜치로 전송합니다. 이 모드에서는 기존 원격 이력을 먼저 clone하고 공개 허용 목록을 동기화한 뒤 새 커밋을 만들기 때문에 반복 export에서도 독립 이력이나 `fetch first` 충돌이 발생하지 않습니다. Private 저장소는 HTTPS 토큰·GitHub CLI credential helper 또는 SSH 키 인증이 먼저 준비되어 있어야 합니다.

```bash
ctf-export --push -m "Initial public release"
```

push가 인증 또는 실행 중 발생한 원격의 동시 변경 때문에 실패해도 생성된 공개본과 로컬 커밋은 보존됩니다. 강제 push는 수행하지 않습니다.

출력 경로와 커밋 작성자도 선택할 수 있습니다.

```bash
ctf-export \
  --output "$HOME/releases/ctf-agent-public" \
  --message "Prepare public release" \
  --author-name "GitHub Name" \
  --author-email "name@users.noreply.github.com"
```

## 안전 범위

허가된 CTF 문제, 로컬 실습 환경 및 명시적으로 허용된 공식 CTF 엔드포인트에만 사용하세요. 공개 export에는 challenge 입력, evidence, work, 플래그 및 개인 상태 파일이 포함되지 않습니다.

## 공개 전 확인

`ctf-export --dry-run`으로 원본·출력·원격 저장소와 push 여부를 먼저 확인하세요. `--push`를 사용하기 전 공개본의 커밋과 파일 목록을 검토하는 것을 권장합니다.
