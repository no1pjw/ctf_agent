---
name: ctf-rev
description: Solve explicitly authorized local CTF reverse-engineering challenges by bounded static analysis, sandboxed execution, minimal recovery scripting, and verified flag derivation.
---

# CTF Reverse Engineering

목표는 전체 프로그램 이해가 아니라 가장 짧은 검증 가능한 flag 추출이다. 진행을 설명하지 말고 다음 검사를 실행한다.

## Fast path

1. `$CTF_REV_WORK_DIR/intake-exec.txt`를 읽고, 제공되면 `"$CTF_REV_FAST_PROBE" "$CTF_REV_INPUT_DIR"`를 한 번 실행한다. 경로·Skill·정책을 다시 검색하지 않는다.
2. flag 문자열/리소스 → 성공 참조·비교 상수 → 가장 가까운 validator/decoder 순으로 본다. 첫 출력은 16 KiB 이하로 제한한다.
3. 직접 가설은 최대 두 개만 시험한다. embedded data, 짧은 decoder, validator 역산, bounded constraint를 우선한다.
4. 변환이 보이면 즉시 최소 inverse를 작성한다. 전체 함수 열거, CFG, broad decompile, raw blob 전체 dump는 하지 않는다.

큰 blob은 먼저 참조 offset을 구한 뒤 bounded window만 본다. VM/obfuscation도 flag에 필요한 dispatcher state와 opcode slice만 복원한다. 대수적 역산이 가능하면 emulator/solver보다 우선하며 모든 후보는 정방향 식으로 재검증한다. 프로그램 payload와 `PREFIX{payload}` 제출 wrapper를 구분한다.

## 경계와 검증

- 입력은 수정하지 않고 호스트에서 실행하지 않는다. 동적 검증은 `$CTF_REV_RUNNER`와 `$CTF_REV_IMAGE`가 제공될 때 network-disabled Docker에서 bounded command로만 수행한다.
- Docker가 없으면 STATIC-ONLY로 계속한다. decompiler 결과의 width, signedness, index, constant는 disassembly나 독립 구현으로 확인한다.
- 필요한 경우에만 최소 `work/recover.py`를 만들고, 복구·syntax·검증·`.solved` 기록을 가능한 한 한 도구 턴으로 합친다.
- flag처럼 보이는 산출물은 후보일 뿐이다. 공식 validator의 성공 응답 또는 그와 동등한 독립 검증이 있어야 성공이다.
- 공식 validator가 성공한 **동일 도구 호출의 마지막 명령**으로 `"$CTF_REV_FLAG_SUCCESS" '<flag>'`를 실행한다. 이 명령이 `FLAG=<value>`와 `.solved=verified`를 원자적으로 기록한다. 이후 재현기 정리·추가 검증·분석·write-up 없이 즉시 종료한다.

직접 복원 두 번 실패, packing/VM/난독화, anti-debugging 또는 환경 불일치가 있을 때만 관련 feedback 하나를 읽고 같은 세션에서 범위를 확장한다.
