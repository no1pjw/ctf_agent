# Pwn feedback index

Fast Probe 중에는 이 색인만 확인한다. 증상이나 실패 유형이 일치할 때 관련 문서만 읽는다.

- `input-framing.md`: `scanf`/`printf` 포맷-인자 타입·개수 불일치, 개행 소비, EOF·half-close, 반복 qword overwrite의 epilogue·비복귀 경로
- `stack-canary-leaks.md`: 비종단 `%s` 에코, 카나리 선행 NUL 덮기, 짧은 `read`로 인접 스택 보존, 짧은 누출 거부
- `bounds-validation.md`: 상한만 검사한 signed index의 곱셈 wrap 별칭, `scanf` 저장 후 범위 거부의 잔존 부작용
- `shell-filter-reparse.md`: 원문 substring blacklist 뒤의 shell expansion 재해석, `${IFS}` 토큰 분리, command substitution의 `stderr` 관찰, 셸별 `echo` escape 차이
- `xor-write-primitives.md`: out-of-bounds XOR 제한 쓰기, 같은 PIE 페이지 포인터의 ASLR 불변 XOR delta, `.fini_array` 종료 trigger
- `failures.md`: 반복하기 쉬운 도구·실행·검증 실패
- `long-running.md`: brute force, symbolic execution 및 장시간 작업 제한
