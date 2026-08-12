---
name: ctf-pwn
description: Solve explicitly authorized CTF pwn challenges from supplied artifacts and an optional exact official endpoint, using sandboxed local validation and rapid flag acquisition.
---

# CTF Pwn

목표는 검증된 flag까지의 시간을 최소화하는 것이다. 진행을 설명하지 말고 다음 검사를 실행한다.

## 시작

1. `work/runtime/runtime.env`, `work/intake-exec.txt`, 비어 있지 않은 `work/state.json`만 읽는다. 다른 정책·playbook·feedback은 blocker가 생겼을 때 관련 파일 하나만 연다.
2. 소스, mitigations, symbols/imports, 관련 함수만 한 번의 좁은 probe로 본 뒤 가장 싼 가설을 고르고 즉시 `work/solve.py`를 만든다.
3. `win`/flag 함수, 기존 call·hook·return slot처럼 단계가 짧은 경로를 범용 arbitrary-RW·ORW·긴 gadget chain보다 우선한다. heap이라는 이유만으로 Deep으로 가지 않는다.

## 런타임

- `ready`: 기록된 libc와 일치하는 loader/libc를 `pwn-run.sh`로 사용한다. host libc, `LD_PRELOAD` 단독, 입력 binary patch는 금지한다.
- `incompatible`: 원격용 supplied libc와 로컬 image pair를 섞지 않는다. image pair는 구조 검증에만 쓴다.
- Docker/runtime이 없으면 STATIC-ONLY로 계속한다. 문제 binary는 호스트에서 실행하지 않는다.
- bare image/service를 방치하지 말고 모든 로컬 실행을 bounded harness로 수행한다.

## 빠른 exploit

- primitive가 보이면 layout discriminator는 최대 한 번만 수행하고 첫 solver를 실행한다.
- 필요한 gadget semantics를 먼저 정한 뒤 gadget index는 한 번만 사용한다. 부족하면 기존 call/dispatch/leak 등 다른 짧은 primitive로 전환한다.
- syntax check와 다음 로컬/원격 실행을 한 명령으로 합친다. 환경·framing 실패를 exploit 실패와 구분한다.
- solver에는 필요한 경우 `STAGE=<name>`과 bounded `DIAG=`만 넣고 장황한 transcript는 만들지 않는다.

## 원격과 완료

- 새 solver가 로컬 성공할 때마다 기록된 정확한 endpoint에 즉시 동기화한다. 로컬 실행이 불가능하면 정적 교차 확인된 첫 버전과 실질적으로 수정된 버전만 시도한다.
- 변경 없는 자동 반복, brute force, flood는 금지한다. 실패 후에는 마지막 stage, framing, leak/base, runtime 출처만 비교한다.
- 원격 `FLAG=<flag>`를 받으면 연결을 닫고 즉시 출력한 뒤 `.solved=verified`를 기록하고 종료한다. 검증·cleanup·write-up을 기다리지 않는다.

두 근거 있는 solver 실패, race/확률성, 난독화 또는 환경 불일치가 있을 때만 기존 결과를 유지한 채 Deep으로 확장한다.
