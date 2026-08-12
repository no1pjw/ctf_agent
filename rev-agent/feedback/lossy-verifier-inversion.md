# Lossy verifier inversion lessons

## raw image에서는 파일 offset과 실행 주소를 먼저 고정하기

- 증상: 부트 이미지의 문자열과 검증 코드를 찾았지만 잘못된 load base, segment 또는 BIOS 상태 때문에 emulator가 빈 메모리나 같은 주소를 반복 실행한다.
- 재사용 가능한 교훈: 디스크 offset, stage load address, `CS:IP`, stack, IVT와 필요한 BIOS side effect를 표 하나로 먼저 고정한다. 전체 이미지를 실행하지 말고 verifier 진입점부터 synthetic input과 sentinel return으로 격리한다.
- 가장 싼 확인법: 알려진 문자열·함수의 파일 offset이 emulator의 선형 주소에서 같은 바이트로 보이는지 확인하고, 첫 1000 instruction의 PC 범위와 종료 sentinel 도달 여부만 본다.
- 환경/적용 한계: unreal mode, A20, relocation, self-modifying code 또는 보호 모드 전환이 verifier에 필요하면 real-mode 최소 모델만으로는 충분하지 않다.

## 전체 CFG 대신 상태 경계에서 operation stream 복원하기

- 증상: 난독화된 분기와 anti-analysis 잡음 때문에 정적 disassembly를 넓힐수록 실제 상태 변환 순서가 보이지 않는다.
- 재사용 가능한 교훈: verifier state의 시작·끝과 쓰기 경계만 hook하고 각 이벤트에 `PC, target index, before, after, 관련 register`를 남긴다. 서로 다른 synthetic state 몇 개에 동일 trace를 적용하여 `xor`, `add`, `sub`, rotate, move, swap 같은 연산을 차분 분류한다.
- 가장 싼 확인법: 여러 입력에서 이벤트 수와 `(PC, target index, width)` 순서가 동일한지 먼저 확인하고, 한 상태의 관찰 출력과 짧은 순수 Python 정방향 모델이 완전히 일치하는지 검사한다.
- 환경/적용 한계: 입력에 따라 control flow 자체가 달라지거나 table이 runtime에 복호화되면 고정 stream으로 일반화하지 말고 분기 조건과 table 생성 시점을 함께 기록한다.

## bijective layer와 lossy bit를 분리해 역산하기

- 증상: 검증기가 대부분 가역 연산이지만 중간의 one-bit 삭제 때문에 입력 전체를 brute force하려 한다.
- 재사용 가능한 교훈: 가역 연산은 정확한 역연산으로 되돌리고, 정보가 실제로 사라지는 지점에서만 후보를 분기한다. 역순으로 한 연산씩 적용하고 매 단계 중복 상태를 제거한 뒤 마지막 verifier hash로 후보를 필터링한다.
- 가장 싼 확인법: 각 primitive에 `inverse(forward(x)) == x`를 넣고, 전체 모델에는 `forward(observed_seed) == observed_target`을 먼저 통과시킨다. 그 다음 lossy 지점 하나만 열어 후보 수 증가가 예상 bound와 맞는지 본다.
- 환경/적용 한계: 삭제된 비트가 서로 독립이 아니거나 hash 이전에 비가역 압축이 더 있으면 단순 `2^n` 열거 대신 제약 전파, meet-in-the-middle 또는 SAT/SMT가 필요할 수 있다.

## 좁은 역연산만 native code로 가속하기

- 증상: 전체 emulator는 빠르지만 특정 16비트·32비트 역상 열거가 Python 내부 loop에서 병목이 된다.
- 재사용 가능한 교훈: 전체 solver를 다시 쓰지 말고 가장 뜨거운 bounded inverse primitive만 작은 C 함수로 분리한다. Python은 operation stream, 후보 deduplication, 최종 hash 검증을 담당한다.
- 가장 싼 확인법: 작은 고정 test vector로 C 결과와 Python 정방향 모델의 round-trip을 비교하고, 후보 수·실행 시간·상한을 출력한다.
- 환경/적용 한계: native helper는 파생 산출물로만 두고 입력 artifact를 수정하지 않는다. overflow, rotate width, endianness와 signedness를 명시하지 않으면 빠르게 틀린 결과를 낼 수 있다.

## 일반 비밀번호 사전 대입은 구조 복원 뒤로 미루기

- 증상: verifier hash를 발견하자마자 단어 조합과 leetspeak를 무제한 생성하여 CPU를 오래 점유하지만 구조적 증거는 늘지 않는다.
- 재사용 가능한 교훈: hash는 역산된 후보를 거르는 oracle로 사용한다. 문제에서 명시적인 사전·형식·작은 candidate space가 제공되지 않았다면 임의 단어 조합 탐색을 시작하지 않는다.
- 가장 싼 확인법: 탐색 전에 후보 공간의 근거와 정확한 상한을 한 줄로 계산한다. 구조에서 나온 후보가 없거나 상한이 설명되지 않으면 verifier parsing과 상태 역산으로 돌아간다.
- 환경/적용 한계: 의도된 풀이가 실제 dictionary attack이고 제공 wordlist나 강한 형식 제약이 있다면 bounded 탐색은 허용하되 timeout, worker 수와 checkpoint를 먼저 정한다.

## trace는 이벤트 집계로 제한하기

- 증상: 같은 PC와 register state를 반복 출력하여 로그가 커지지만 새로운 정보는 생기지 않는다.
- 재사용 가능한 교훈: 기본 trace는 unique event counter, 첫·마지막 표본과 단계별 후보 수만 기록한다. 동일 `(PC, state fingerprint)` 반복 또는 instruction budget 초과 시 해당 실험을 종료하고 모델을 수정한다.
- 가장 싼 확인법: 1초 간격으로 로그 크기와 unique event 증가량을 비교한다. 로그만 증가하고 unique event가 늘지 않으면 per-step 출력을 끄고 counter로 바꾼다.
- 환경/적용 한계: race, timing 또는 self-modifying code처럼 반복 자체가 증거인 경우에는 bounded ring buffer와 sampling rate를 명시해 보존한다.
