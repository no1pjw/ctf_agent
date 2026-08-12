# Reverse feedback index

피드백은 시작 시 전체를 읽지 않는다. 구체적인 증상과 일치하는 문서 하나만 연다.

- `failures.md`: 이미 실패한 가설과 더 저렴한 미래 판별법
- `fast-path.md`: 경로 재탐색, 과도한 정적 출력, 큰 blob 전수 분석, ROP·VM 검증식 역산, payload·제출 형식 혼동으로 리버싱이 느릴 때
- `long-running.md`: symbolic execution, bounded brute force, emulation 등 장시간 작업의 체크포인트
- `selective-emulation.md`: 큰 정적 바이너리의 내부 함수·암호 primitive만 격리 에뮬레이션하여 상태와 round key를 복원할 때
- `lossy-verifier-inversion.md`: raw boot image의 난독화 verifier에서 operation stream을 복원하고 bijective layer 역산·lossy bit 후보 탐색·hash 필터링을 수행할 때
