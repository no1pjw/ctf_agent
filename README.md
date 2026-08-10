# ctf-agent

Codex CLI에서 로컬 CTF 문제를 분야별 에이전트와 재현 가능한 절차로 분석하기 위한 작업 공간입니다.

## 주요 기능

- `ctf-pwn`: pwn 문제 복사, Adaptive Fast→Deep 풀이, Docker 또는 STATIC-ONLY 실행
- pwn 문제의 제공 `libc`·`ld`를 우선 적용하고, 부족할 때만 정확한 Docker 이미지에서 검증된 한 쌍 추출
- `ctf-rev`: 리버싱 문제 복사, Adaptive Fast→Deep 분석, 격리 실행 강제
- `ctf-learn`: 완료된 풀이에서 검증된 재사용 교훈만 분야별 피드백에 축적
- `ctf-clean`: 학습·풀이 결과를 보존하면서 중복 입력, 실행 로그와 재생성 캐시 정리
- 복합 pwn 문제의 최근 20단계 체크포인트와 1MiB 원격 transcript 상한
- `ctf-pwn`은 기본적으로 `gpt-5.6-sol` + `ultra` 추론 + `fast` 서비스 티어 사용
- `ctf-rev` 문제 풀이는 기본적으로 `gpt-5.6-sol` + `ultra` 추론 사용
- `ctf-export`: 원본을 수정하지 않고 GitHub 공개용 복사본과 로컬 커밋 생성
- pwn, reverse engineering, web, crypto, forensics/misc 라우팅
- 신뢰할 수 없는 실행 파일의 호스트 실행 금지와 Docker 네트워크 격리

## WSL 설치

```bash
git clone https://github.com/no1pjw/ctf_agent.git
cd ctf_agent
./install-wsl.sh
```

기본 pwn 문제 경로는 `$HOME/ctf-challenges/pwnable`입니다. 다른 위치는 환경 변수로 지정합니다.

```bash
export CTF_PWNABLE_SOURCE=/path/to/pwnable
```

## 사용

```bash
ctf-pwn challenge-name
ctf-pwn --fast-only challenge-name
ctf-pwn --deep challenge-name
ctf-pwn --keep-docker challenge-name
ctf-pwn challenge-name host.example:31337
ctf-pwn challenge-name host.example 31337
ctf-rev --source /path/to/reversing challenge-name
ctf-bench challenge-name
ctf-bench --source /path/to/challenge challenge-name
ctf-bench --remote host.example:31337 challenge-name
ctf-bench --exact-tokens --remote host.example:31337 challenge-name
ctf-learn challenge-name
ctf-clean
ctf-clean --caches --apply
```

## 벤치마크

`ctf-bench`는 같은 pwn 문제를 `plain Codex`와 `FAST_LOCAL`의 격리된 작업공간에서 동시에 실행합니다. 두 실행 모두 `gpt-5.6-sol`, `xhigh`, 멀티에이전트·자동 스킬 검색 비활성화 및 ephemeral non-interactive 모드를 강제하며, 실행별 Docker 이미지 이름과 이벤트 로그를 분리합니다. 실행 중에는 인증만 연결한 임시 `CODEX_HOME`을 사용하므로 전역 CTF 스킬이 plain 기준선에 섞이지 않으며, 종료 시 임시 홈을 정리합니다. 벤치마크 프롬프트는 “문제를 바로 풀어 플래그를 구하라”는 짧은 계약만 사용합니다. plain은 프로젝트 CTF 정책·스킬을 사용하지 않고, FAST_LOCAL은 간결한 `AGENTS.md`와 준비된 pwntools solver 골격을 사용합니다. FAST_LOCAL은 한 번의 좁은 정적 조사 후 solver를 작성하고 문법 검사와 원격 하니스 실행을 한 명령으로 결합하며, 막힌 증상과 맞는 피드백만 선택적으로 확인합니다. 진행 중 이벤트는 터미널에 흘려보내지 않고 파일에만 저장하며, 완료 후 한글 표시 폭을 보정한 요약 표만 출력합니다.

```bash
ctf-bench challenge-name
ctf-bench --source /path/to/challenge challenge-name
ctf-bench --remote host.example:31337 challenge-name
ctf-bench challenge-name host.example:31337
ctf-bench --exact-tokens --remote host.example:31337 challenge-name
ctf-bench --timeout 2400 --order fast-first challenge-name
```

로컬 모드는 기존처럼 clean replay와 `.solved=verified`를 성공 조건으로 사용합니다. `--remote` 또는 두 번째 위치 인수로 사용자가 허가한 정확한 `HOST:PORT`를 지정한 원격 모드에서는 다른 주소와 scoreboard 접속을 금지합니다. Dockerfile·캐시 이미지·로컬 플래그가 없어도 정적으로 parameterized solver가 완성되면 공용 원격 하니스로 variant당 즉시 1회 실행합니다. 하니스가 실제 원격 플래그를 포착하는 순간 성공으로 기록하고 프로세스를 중단하며 재검증·writeup·`.solved` 판정은 생략합니다.

결과는 기본적으로 `benchmarks/runs/<run-id>/report.md`와 각 실행의 JSONL 이벤트에 남습니다. 기본 원격 모드는 플래그를 잡는 즉시 종료하므로 Codex의 마지막 `turn.completed.usage`가 오지 않은 경우 토큰을 거짓 `0` 대신 `미집계 (즉시 종료)`로 표시합니다. 정확한 토큰 비교가 필요하면 `--exact-tokens`를 추가합니다. 이 모드는 플래그 시각을 성공 시각으로 즉시 고정하고 추가 도구 호출을 차단한 채 최종 usage 이벤트만 최대 30초 기다립니다. `ctf-bench --dry-run challenge-name` 또는 `ctf-bench --dry-run --remote HOST:PORT challenge-name`으로 모델 호출 없이 고정 설정과 범위를 먼저 확인할 수 있습니다.

리버싱 문제의 기본 원본 경로는 `$HOME/ctf-challenges/reversing`입니다. 다른 위치는 `--source` 또는 `CTF_REV_SOURCE`로 지정합니다. 제공된 Dockerfile이 없으면 바이너리를 호스트에서 실행하지 않는 STATIC-ONLY 분석으로 진행합니다.

문제 풀이 모델은 기본적으로 `gpt-5.6-sol`, 추론 강도는 `ultra`입니다. `ctf-pwn`은 여기에 `service_tier="fast"`와 `fast_mode`를 명시적으로 적용합니다. 일시적으로 변경해야 할 때만 `CTF_CODEX_MODEL`, `CTF_CODEX_REASONING_EFFORT`, `CTF_CODEX_SERVICE_TIER` 환경 변수를 지정합니다.

`ctf-clean`은 기본적으로 미리보기만 수행합니다. `--apply`를 지정해도 `ctf-learn` 피드백, `work/solve.py`, `work/writeup.md`, `evidence/private`, `scope`는 항상 보존합니다. 문제의 `input/`은 풀이가 완료됐고 외부 원본 경로가 실제로 확인될 때만 삭제합니다. `--caches`는 다시 내려받거나 생성할 수 있는 Go 빌드, pip, uv 캐시만 추가로 정리하며 설치된 도구와 라이브러리는 제거하지 않습니다.

WSL 내부 파일을 삭제해도 `ext4.vhdx`의 Windows 실제 크기가 줄지 않으면 관리자 PowerShell에서 다음 스크립트를 실행합니다. 정확한 배포판 VHDX를 검증하고 WSL을 정상 종료한 뒤 빈 블록만 압축하며, 위험한 sparse 옵션은 사용하지 않습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\references\tools\ctf-compact-wsl.ps1
```

공식 CTF pwn 서비스 주소를 함께 주면 정확한 로컬 런타임이 있을 때는 로컬 플래그 한 번 후, 없을 때는 정적 exploit chain 교차 확인과 solver 문법 검사 후 반복 검증이나 write-up보다 원격 실행을 먼저 수행합니다. Dockerfile·캐시 이미지·로컬 플래그 부재는 첫 원격 시도의 blocker가 아닙니다. 검증된 원격 플래그와 실행 시작부터 수신까지의 시간은 즉시 `획득한 플래그: ...`, `원격 플래그 획득 시간: N.NNN초`로 출력하고 `challenges/<name>/evidence/private/`에도 저장합니다. 첫 원격 시도가 실패할 때만 차이를 분석해 수정된 exploit으로 한 번 더 시도합니다. 공개 write-up에서는 원문을 가리며 scoreboard에는 자동 제출하지 않습니다. 주소를 생략하면 대상 네트워크는 계속 차단됩니다.

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
