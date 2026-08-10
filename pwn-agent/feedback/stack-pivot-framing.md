# Stack pivot and fixed-read framing

## Fake frame pointers also control ABI alignment

- **증상:** saved frame-pointer pivot reaches the intended region, but a later variadic or libc call fails inconsistently.
- **재사용 가능한 교훈:** treat the fake frame pointer as both a control-flow value and an ABI-alignment parameter. Calculate `rsp` at every `leave`, `ret`, and function call; a numerically parsed fake frame can make the chain misaligned even when the pivot address is valid.
- **가장 싼 확인법:** annotate the expected `rsp mod 16` beside each stage and verify one end-to-end image-runtime run before a scarce remote attempt.
- **환경/적용 한계:** the exact libc may differ remotely, so local structural success validates alignment and stage order, not remote offsets.

## Bit-dependent pivots must fit the attempt budget

- **증상:** a one-bit saved-frame-pointer change works only for some ASLR stack values.
- **재사용 가능한 교훈:** derive the reachable region and success probability before calling the exploit ready. Compare it with the official attempt budget; do not hide a probabilistic prerequisite behind a deterministic solver interface.
- **가장 싼 확인법:** sample only enough sandbox runs to confirm the relevant address bit distribution, then seek a deterministic framing/state improvement if the budget is too small.
- **환경/적용 한계:** local ASLR distribution is evidence about the primitive, not a guarantee about the official service.

## Fixed-length reads do not append a terminator

- **증상:** a parser needs one more digit or byte than the immediately preceding fixed-size read writes.
- **재사용 가능한 교훈:** `read(fd, buf, n)` does not append NUL. When the following byte is deterministically retained from an earlier stage, a staged write can pre-position the extra parser byte. Model the complete buffer state rather than only the latest read.
- **가장 싼 확인법:** prefill the destination with a visible sentinel, perform the exact bounded read in the sandbox, and inspect only `n+1` bytes to prove whether the adjacent byte is retained.
- **환경/적용 한계:** never rely on uninitialized or unproven stale data. Use this only when the prior write and buffer reuse are demonstrated in the exact process flow.

## 가짜 스택은 활성 프레임과 호출자의 확장 공간을 함께 피한다

- **증상:** writable 정적 영역으로의 pivot 자체는 성공하지만, 재입력 함수나 큰 libc 호출 직후 읽기 전용 매핑에서 fault가 난다.
- **재사용 가능한 교훈:** 가짜 스택의 현재 `rsp`만 보지 말고, 입력 함수의 활성 프레임과 이후 호출이 아래쪽으로 소비할 최대 stack 범위를 함께 지도화한다. 후속 payload가 현재 활성 프레임을 덮는다면 상단의 복귀 프레임은 이전 단계에서 미리 설치하고, 새 chain은 그 프레임과 겹치지 않는 낮은 writable 구간에 둔다. 불필요하게 stack을 크게 쓰는 출력·variadic 경로는 우회 후보로 취급한다.
- **가장 싼 확인법:** 각 단계의 write 범위와 예상 `rsp`부터 다음 비정상 mapping 경계까지를 주소축 하나에 표시하고, fault 주소가 그 아래 경계와 일치하는지 확인한다.
- **환경/적용 한계:** libc 함수의 실제 stack 사용량은 구현·호출 경로에 따라 달라진다. 정확한 런타임이 없으면 구조적 충돌 가능성만 판정하고 구체적인 여유 크기는 원격 offset의 증거로 삼지 않는다.

## Line reader payload에는 제어 주소의 바이트도 프레이밍 제약이다

- **증상:** 유효한 `leave; ret` 또는 ROP gadget을 넣었는데 line 기반 입력이 payload 중간에서 끝나 이후 프레임이 전달되지 않는다.
- **재사용 가능한 교훈:** gadget의 의미뿐 아니라 직렬화된 주소에 delimiter가 포함되는지도 검사한다. 금지 바이트가 든 gadget은 같은 epilogue 효과를 내는 더 긴 instruction suffix나 다른 경로로 교체할 수 있다.
- **가장 싼 확인법:** payload를 보내기 전에 전체 blob에서 `newline`, NUL 등 실제 reader의 종료·변환 바이트 위치를 검사하고, 후보 gadget 주소들의 packed bytes에도 같은 검사를 적용한다.
- **환경/적용 한계:** 금지 집합은 `fgets`, `scanf`, 직접 `read` 등 입력 API와 후속 파서에 따라 다르며, ASLR이 주소 바이트를 바꾸면 실행마다 재검사가 필요할 수 있다.

## 재귀 프레임은 1바이트 복귀 주소 덮기를 전체 주소 체인으로 확장할 수 있다

- **증상:** 각 호출에서 saved RIP의 하위 바이트 하나만 바꿀 수 있어 직접 ROP는 불가능해 보이지만, 재귀 호출의 입력 버퍼가 상위 호출 프레임보다 낮은 주소에 연속해서 생긴다.
- **재사용 가능한 교훈:** 하위 프레임의 부분 덮기를 같은 코드 페이지의 `pop rbp; ret` 또는 `leave; ret`로 맞출 수 있으면, 상위 프레임 버퍼에 미리 둔 full-width frame pointer와 return address를 소비하는 운반 체인을 만들 수 있다. 프리미티브를 “1바이트 제어”로만 평가하지 말고 재귀 깊이에 따른 프레임 간 쓰기·소비 관계까지 본다.
- **가장 싼 확인법:** 두 번의 중첩 호출만 그려 각 버퍼, saved RBP, saved RIP의 상대 위치를 표시하고, 가능한 하위 바이트가 epilogue gadget에 닿는지 및 다음 `ret`이 어느 8바이트를 읽는지 정적으로 추적한다.
- **환경/적용 한계:** 프레임 크기와 epilogue는 컴파일러 옵션에 의존한다. 상위 주소 바이트가 목표 gadget과 같아야 하며, CET shadow stack 같은 복귀 무결성 보호가 있으면 성립하지 않을 수 있다.

## 런타임이 남긴 ASLR 포인터도 부분 덮기의 기준 포인터가 된다

- **증상:** 코드 주소 누출은 없지만 startup 또는 재진입 뒤 스택에 실제 libc code pointer가 남고, 공격자는 그 포인터의 하위 바이트만 바꿀 수 있다.
- **재사용 가능한 교훈:** 공격자가 주소를 새로 만들 필요는 없다. 런타임이 기록한 진짜 포인터와 같은 정렬 구간에 유용한 `syscall` 또는 간접 dispatch 지점이 있으면, ASLR 상위 바이트를 그대로 보존한 채 부분 덮기로 재지정할 수 있다. 서로 다른 런타임 포인터를 각 단계의 서로 다른 역할에 쓰는 것도 누출 없는 체인을 단순화한다.
- **가장 싼 확인법:** 정확한 libc/loader의 startup 반환 경로에서 스택에 저장되는 포인터의 출처를 정적으로 확인하고, 원래 지점과 후보 지점의 상위 바이트가 동일하며 저바이트 변경에 carry/borrow가 없는지 계산한다.
- **환경/적용 한계:** 저장 위치와 code layout은 libc/loader 빌드에 종속된다. 같은 페이지라는 직관만 믿지 말고 실제 부분 덮기 폭의 경계를 확인하며, 다른 런타임에서 offset이 유지된다고 일반화하지 않는다.

## 런타임 재진입 뒤에는 fake context의 덮인 구간만 복구한다

- **증상:** writable 정적 영역에 fake sigreturn context를 먼저 설치했지만 startup 재진입이 같은 영역에 부모 프레임이나 보존 값을 써서 일부 레지스터 필드만 깨진다.
- **재사용 가능한 교훈:** runtime의 쓰기를 막을 수 없다면 context 전체를 반복 설치하기보다, 재진입 전후의 write-set을 겹쳐 보고 마지막으로 덮이는 필드 조각을 단계별로 복구한다. 동적으로 생성된 포인터처럼 보존해야 할 슬롯 앞에서 고정 길이 쓰기를 정확히 끝내면 runtime 산출물과 공격자 context를 함께 유지할 수 있다.
- **가장 싼 확인법:** fake context 필드 범위와 각 재진입 write 범위를 한 주소축에 겹쳐 표시한 뒤, solver의 후속 쓰기가 차집합이 아니라 실제 교집합만 복구하고 보존 슬롯 직전에 끝나는지 검사한다.
- **환경/적용 한계:** 커널 ABI의 sigcontext 배치와 runtime의 정확한 프레임 배치를 알아야 한다. 관찰되지 않은 padding이나 다른 libc의 startup write-set을 동일하다고 가정해서는 안 된다.
