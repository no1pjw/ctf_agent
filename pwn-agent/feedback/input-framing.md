# Input framing lessons

## EOF도 payload의 일부다

입력 기반 exploit에서는 값뿐 아니라 delimiter, newline, EOF 및 socket half-close의 위치도 명시적으로 설계한다. 성공한 입력 프레이밍은 `solve.py`에 그대로 표현하고 timeout을 둔다.

## formatted input 뒤의 raw read

- **증상:** 메뉴와 숫자는 `scanf`류로 받고 payload는 `read(0, ...)`로 받기 때문에, 남은 newline이나 한 번에 보낸 다음 명령이 payload로 흡수된다.
- **재사용 가능한 교훈:** 숫자와 delimiter를 먼저 보내고 raw-input prompt를 수신한 뒤 payload를 별도 전송한다. prompt를 프로토콜 프레이밍 장벽으로 사용하면 stdio buffering과 커널 read 경계를 추측할 필요가 줄어든다.
- **가장 싼 확인법:** 짧고 식별 가능한 payload 뒤에 다음 메뉴 입력을 붙여 보내는 경우와, prompt 확인 후 분리 전송하는 경우를 각각 한 번 비교해 저장·에코 길이를 본다.
- **환경/적용 한계:** prompt가 실제 raw read 전에 flush되어야 한다. 출력 buffering으로 prompt가 보이지 않거나 프로그램이 고정 길이를 모두 기다리면 delimiter와 정확한 전송 길이를 별도로 모델링해야 한다.

## Malformed variadic input

- `scanf` 계열 포맷의 변환 지정자 수가 전달된 포인터 수보다 많으면 undefined behavior다.
- `%c`는 선행 공백을 건너뛰지 않으므로 남아 있는 newline도 즉시 소비할 수 있다.
- 마지막 정상 변환 직후 EOF 또는 send 방향 half-close를 만들면, 제공된 libc에서는 뒤따르는 미지정 변환이 입력 부족으로 실패해 잘못된 포인터 쓰기를 피할 수 있다. 이는 ABI나 libc 전반의 보장이 아니므로 반드시 제공된 컨테이너에서 검증한다.
- 넓은 libc 분석 전에 `delimiter / newline / EOF / half-close`의 작은 조합만 비교한다.

### 변환별 목적지 타입

- **증상:** 변환 지정자 수가 맞아 보여도 지정자가 요구하는 포인터 타입과 실제 객체 타입이 다르면 호출은 여전히 undefined behavior다. 정적 저장 기간의 더 넓은 객체가 0으로 초기화되고 작은 값만 입력되면 일부 ABI에서 폭 불일치가 정상 동작처럼 가려질 수 있다.
- **재사용 가능한 교훈:** 폭과 signedness를 포함해 각 변환과 목적지를 1:1로 대조한다. 예를 들어 `%d`는 `int *`, `%ld`는 `long *`, `%lx`는 `unsigned long *`을 요구한다.
- **가장 싼 확인법:** 소스가 있으면 수동 대조와 함께 `-Wall -Wextra -Wformat=2 -fsyntax-only` 컴파일 경고를 확인한다.
- **환경/적용 한계:** 경고는 호출 계약 위반만 입증한다. 실제로 기록되는 바이트와 exploit 안정성은 ABI·libc·컴파일러에 따라 달라질 수 있으므로 제공 환경에서 별도로 검증한다.

## 반복 qword overwrite 검증

- 배열의 qword 인덱스를 지역 변수, saved frame pointer, saved return address 순으로 지도화한다.
- saved frame pointer가 덮여도 함수 epilogue가 이를 레지스터로 꺼낸 뒤 곧바로 `ret`한다면, 즉시 실패하지 않고 다음 saved return address 제어가 핵심이 될 수 있다. 실제 epilogue를 확인한다.
- 첫 `ret` 전이가 성공해도 전이 대상이 반환하면 그 다음 stack word가 continuation으로 사용될 수 있다. 소스나 짧은 disassembly로 모든 종료 경로가 `exit` 같은 비복귀 호출에 도달하는지 먼저 확인하고, 반환 가능하면 유효한 후속 주소를 따로 마련한다.
- 반환 주소까지 닿는 쓰기 횟수와 정확히 한 칸 덜 쓰는 횟수를 비교한다. 한 칸 덜 쓴 음성 대조군이 실패하면 성공 원인이 saved return address 제어라는 증거가 강해진다.

## 환경 경계

Malformed variadic 호출은 libc 구현과 호출 시점의 레지스터·스택 상태에 의존한다. 원격 endpoint가 없으면 공식 Docker 환경에서 성공 2회와 음성 대조군 1회를 확인한다. 공식 원격 endpoint가 있으면 exploit으로 로컬 플래그를 1회 얻는 즉시 Fast-to-Remote를 먼저 수행하고, 반복 성공과 음성 대조군은 원격 실패 시에만 진행한다. 무관한 libc 버전으로 일반화하지 않는다.
