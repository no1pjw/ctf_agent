# Pwn feedback index

Fast Probe 중에는 이 색인만 확인한다. 증상이나 실패 유형이 일치할 때 관련 문서만 읽는다.

- `input-framing.md`: `scanf`/`printf` 포맷-인자 타입·개수 불일치, stdio `scanf`와 raw `read` 혼용 delimiter, 개행 소비, EOF·half-close, 반복 qword overwrite의 epilogue·비복귀 경로
- `bounds-validation.md`: signed index modular alias, 거부 전 입력 부작용, 실패한 상태 전이의 부분 커밋·롤백 누락, 논리 크기와 실제 allocation 불일치
- `heap-freelist.md`: safe-linking, tcache/fastbin allocation 경로, unsorted split remainder 경계 누출, 정적 영역 fake chunk
- `failures.md`: 반복하기 쉬운 도구·실행·검증 실패
- `long-running.md`: brute force, symbolic execution 및 장시간 작업 제한
- `stack-pivot-framing.md`: saved RBP pivot의 ABI 정렬, bit-dependent 확률과 원격 시도 예산, fixed-length read 뒤의 검증된 잔여 바이트 재사용, 가짜 BSS stack과 활성 프레임·하위 매핑 충돌, line reader payload의 주소 바이트 금지 집합, 재귀 프레임으로 1바이트 saved RIP 제어 확장, startup이 남긴 ASLR 포인터의 부분 덮기 재사용, runtime 재진입 뒤 fake sigreturn context 구간 복구
