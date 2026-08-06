# ctf-agent

Codex CLI에서 로컬 CTF 문제를 분야별 에이전트와 재현 가능한 절차로 분석하기 위한 작업 공간입니다.

## 주요 기능

- `ctf-pwn`: pwn 문제 복사, Adaptive Fast→Deep 풀이, Docker 또는 STATIC-ONLY 실행
- `ctf-learn`: 완료된 풀이에서 검증된 재사용 교훈만 분야별 피드백에 축적
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
ctf-learn challenge-name
```

공식 CTF pwn 서비스 주소를 함께 주면 로컬 exploit이 플래그를 한 번 재현하는 즉시 반복 검증이나 write-up보다 원격 실행을 먼저 수행합니다. 검증된 원격 플래그와 실행 시작부터 수신까지의 시간은 즉시 `획득한 플래그: ...`, `원격 플래그 획득 시간: N.NNN초`로 출력하고 `challenges/<name>/evidence/private/`에도 저장합니다. 첫 원격 시도가 실패할 때만 차이를 분석해 수정된 exploit으로 한 번 더 시도합니다. 공개 write-up에서는 원문을 가리며 scoreboard에는 자동 제출하지 않습니다. 주소를 생략하면 대상 네트워크는 계속 차단됩니다.

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
