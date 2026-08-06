# Pwn feedback index

Fast Probe 중에는 이 색인만 확인한다. 증상이나 실패 유형이 일치할 때 관련 문서만 읽는다.

- `input-framing.md`: `scanf`/`printf` 포맷-인자 타입·개수 불일치, 개행 소비, EOF·half-close, 반복 qword overwrite의 epilogue·비복귀 경로
- `stack-canary-leaks.md`: 비종단 스택 버퍼의 `%s` 에코, 카나리 선행 NUL 덮기, 짧은 누출 거부
- `failures.md`: 반복하기 쉬운 도구·실행·검증 실패
- `long-running.md`: brute force, symbolic execution 및 장시간 작업 제한
