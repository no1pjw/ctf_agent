# Selective emulation lessons

## 내부 primitive 경계에서 런타임 값을 수집하기

- 증상: 대형 정적 바이너리나 펼쳐진 제어 흐름 때문에 key schedule, state transition 또는 암호 검증식을 끝까지 수동 복구하는 비용이 크다.
- 재사용 가능한 교훈: 전체 바이너리를 이해하려 하지 말고 결정적인 내부 함수만 instruction emulator로 실행한다. `PT_LOAD` segment, synthetic stack/heap/TLS를 최소로 준비하고 allocator·복사·출력 같은 외부 경계만 좁게 stub한다. round 함수 또는 state 전이 경계의 인자에서 ephemeral key와 block을 수집한다.
- 가장 싼 확인법: 16바이트 block 처리, 반복 round, S-box·GF 연산 또는 동일 함수의 연속 호출이 보이면 한 block에 대해 함수 진입 인자와 각 round 경계만 hook한다. 수집한 값이 다음 round 입력과 일관되는지 확인한다.
- 환경/적용 한계: stub은 target이 실제로 사용하는 반환값과 side effect만 구현해야 한다. relocation, TLS cookie, SIMD 상태나 전역 초기화가 필요한 경우 이를 생략한 성공을 실제 동작으로 일반화하지 않는다.

## 표준 암호 이름 추측보다 구조를 역변환하기

- 증상: block 크기와 상수가 익숙하다는 이유로 표준 AES·TEA 등의 라이브러리 조합을 여러 개 대입하지만 모두 실패한다.
- 재사용 가능한 교훈: 표준 구현 여부를 추측하지 말고 관찰된 구조를 그대로 모델링한다. 변형 S-box, byte permutation, MixColumns 계열 선형층과 실제 round key 순서를 각각 분리하여 inverse를 작성한다.
- 가장 싼 확인법: 후보 ciphertext 한 block을 역변환한 뒤 동일한 관찰 round key로 다시 암호화해 원문 ciphertext와 정확히 일치하는지 확인한다. 이 re-encryption이 라이브러리 이름 추측보다 강한 판별법이다.
- 환경/적용 한계: authenticated mode, feedback mode 또는 block 간 state가 있으면 단일 block 일치만으로 전체 메시지 복원을 증명하지 않는다.

## 단계형 검증기는 상태를 함께 전진시키기

- 증상: 첫 stage의 정답은 복원되지만 다음 stage부터 key나 target이 달라져 독립적으로 풀리지 않는다.
- 재사용 가능한 교훈: 각 stage의 accepted payload뿐 아니라 성공 시 갱신되는 state를 동일한 순서로 재현한다. 이전 정답을 state transition 함수에 공급한 뒤 다음 key와 target을 추출한다.
- 가장 싼 확인법: stage마다 `recover → re-encrypt/compare → state advance` 세 단계를 한 loop로 묶고, stage 번호와 성공 여부만 출력한다.
- 환경/적용 한계: 실패 횟수, 시간, 랜덤 값 또는 프로세스 외부 상태가 transition에 포함되면 정적 순차 모델에 그 입력을 명시적으로 추가해야 한다.

## 에뮬레이션 결과는 독립 정방향 계산으로 검증하기

- 증상: hook에서 얻은 key나 emulator가 반환한 plaintext가 그럴듯하지만 stub 또는 memory model 오류 가능성이 남는다.
- 재사용 가능한 교훈: emulator 밖의 짧은 순수 구현으로 inverse와 forward transform을 모두 작성하고 `forward(recovered) == target`을 확인한다. flag 형태만으로 성공을 판정하지 않는다.
- 가장 싼 확인법: 한 block을 먼저 round-trip 검증한 뒤 같은 코드로 나머지 stage를 처리한다.
- 환경/적용 한계: emulator와 독립 구현이 동일한 잘못된 상수 추출을 공유하지 않도록 target bytes와 round key의 출처를 별도로 확인한다.

## ciphertext 기반 chaining은 앞에서부터 복호화하기

- 증상: block마다 state가 바뀌어 전체 ciphertext를 역순으로 풀거나 plaintext를 추측해야 한다고 오인한다.
- 재사용 가능한 교훈: 다음 state가 현재 plaintext가 아니라 이미 주어진 ciphertext와 block index만으로 갱신되면, 각 block의 inverse를 적용한 직후 관찰 ciphertext로 state를 전진시키며 처음부터 순차 복호화할 수 있다.
- 가장 싼 확인법: state update 함수의 데이터 의존성을 먼저 표시해 plaintext 참조가 없는지 확인하고, 첫 두 block에 대해 `inverse(cipher, state) → update(state, cipher)`가 일관되는지 검사한다. 마지막에는 padding, 선언 길이, 알려진 파일 magic을 함께 검증한다.
- 환경/적용 한계: update가 plaintext, 인증 tag, 앞에서 복원되지 않은 값 또는 외부 난수에 의존하면 이 단순한 forward pass를 적용하지 않는다.

## 의존적인 self-inverse 연산도 기록 순서는 뒤집기

- 증상: `dst ^= f(src)`가 자체 역연산이라는 이유로 여러 연산을 암호화 순서 그대로 다시 적용했는데 복원이 실패한다.
- 재사용 가능한 교훈: 개별 XOR update가 self-inverse여도 뒤 연산이 앞 연산의 source나 destination을 바꾸면 합성은 교환되지 않는다. 각 primitive는 그대로 쓰되 operation stream 전체를 역순으로 적용한다.
- 가장 싼 확인법: 두 연산만 떼어 임의의 작은 state에서 `inverse(forward(x)) == x`를 확인하고, 각 update에서 source와 destination이 같지 않도록 보정되는지도 점검한다.
- 환경/적용 한계: source와 destination이 같거나 `f(src)` 계산 중 destination의 갱신값을 다시 읽는 primitive는 같은 XOR을 한 번 더 하는 것만으로 역연산이 되지 않을 수 있다.

## 난독화 record table은 유효성 필터 뒤 reachable chain만 따른다

- 증상: 큰 고정폭 record table에 무효 entry와 실제 operation node가 섞여 있어 전체 CFG나 모든 record를 해석하려 한다.
- 재사용 가능한 교훈: loader에서 복구한 field decode 식으로 record를 bounded parsing한 뒤 index·opcode 범위 같은 구조적 invariant를 만족하는 entry만 map에 넣는다. 시작 index에서 sentinel까지 연결된 chain만 operation stream으로 사용한다.
- 가장 싼 확인법: 소수 record에서 decode된 field 폭과 범위를 확인하고, chain traversal에 missing node·cycle·최대 길이 guard를 둔다. 추출 stream은 한 block의 forward/inverse round-trip으로 검증한다.
- 환경/적용 한계: 중복 index의 우선순위, 조건 분기 또는 runtime에 바뀌는 table이 있으면 단순 dictionary와 단일 chain 모델로 일반화하지 않는다.
