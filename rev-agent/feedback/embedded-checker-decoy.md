# Embedded checker and decoy lessons

## 후보 산출물과 공식 성공을 분리하기

- 큰 컨테이너 바이너리가 여러 checker와 암호화된 리소스를 품고 있으면, 첫 복호화 결과의 flag 모양 문자열은 미끼일 수 있다.
- 복원 파일을 공식 validator에 다시 넣어 성공 응답을 확인하기 전에는 완료로 판정하지 않는다.
- 공식 validator 성공은 terminal event다. 성공한 동일 명령에서 `$CTF_REV_FLAG_SUCCESS '<flag>'`를 마지막으로 실행하고 즉시 종료한다. 재현 스크립트 정리는 flag 이후에 하지 않는다.

## 전체 checker 대신 결정적인 checker만 추적하기

- 수백 개의 embedded ELF를 모두 분석하지 않는다. 부모의 fork/exec 순서와 최초 실패·성공 분기에서 결정적인 checker index를 먼저 찾는다.
- self-relocation 또는 메모리 복호화가 있으면 디스크 ELF를 억지로 완전 복원하기보다, 격리된 Docker에서 exec 이후 필요한 bounded 영역만 ptrace로 덤프한다.
- 기준 입력과 소수의 ±1·bit perturbation trace를 비교해 입력 의존 영역을 좁힌 뒤, 해당 변환만 역산한다.

## 반복 checker는 고정 상대 위치를 표본화하기

- 증상: 컨테이너의 table이 같은 형식의 embedded checker를 많이 가리켜 각 checker를 따로 disassemble하려 한다.
- 재사용 가능한 교훈: 두세 checker에서 key·ciphertext 같은 결정적 상수가 동일한 상대 위치에 있는지 확인한 뒤, table의 base/offset만 바꾸는 bounded parser로 일괄 추출한다. 복호화 뒤의 바이트열이 `0`을 제외한 radix digit이라면 각 digit에 `-1`을 적용한 positional integer를 원래 고정 폭의 big-endian 바이트로 되돌리는 packing도 점검한다.
- 가장 싼 확인법: 첫 두 record에서 상대 위치와 block 크기가 같은지 확인하고, 한 block을 `decode → fixed-width bytes → encode`로 round-trip한다. 최종 결합물은 알려진 파일 magic과 종단 구조를 모두 검사한다.
- 환경/적용 한계: checker별 코드 배치가 달라지거나 relocation·압축으로 상수 위치가 변하면 고정 상대 위치를 일반화하지 않는다. radix와 출력 폭도 반복문의 실제 연산 및 소비 길이에서 확인해야 한다.

## 이번 유형의 최단 경로

1. 외부 컨테이너의 table과 XTEA 조각을 bounded parsing하여 1차 리소스를 복원한다.
2. 1차 리소스의 flag 모양 문자열을 후보로만 취급하고 공식 validator에 넣는다.
3. 미끼라면 결정적인 embedded checker 하나의 relocated state와 비교 테이블만 추출한다.
4. 최소 inverse로 실제 리소스를 만들고 공식 validator의 성공을 확인한다.
5. 같은 명령에서 success helper를 호출해 flag를 즉시 출력한다.
