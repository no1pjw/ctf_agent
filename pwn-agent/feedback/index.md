# Pwn feedback index

- `complex-target-fast-path.md`: layered runner/transport failures, payload-size pivots, evidence-ranked hypotheses, and deterministic final-effect selection

Fast Probe 중에는 이 색인만 확인한다. 증상이나 실패 유형이 일치할 때 관련 문서만 읽는다.

- `input-framing.md`: `scanf`/`printf` 포맷-인자 타입·개수 불일치, 개행 소비, EOF·half-close, 반복 qword overwrite의 epilogue·비복귀 경로
- `failures.md`: 반복하기 쉬운 도구·실행·검증 실패
- `long-running.md`: brute force, symbolic execution 및 장시간 작업 제한
- `stack-pivot-framing.md`: saved RBP pivot의 ABI 정렬, bit-dependent 확률과 원격 시도 예산, fixed-length read 뒤의 검증된 잔여 바이트 재사용
