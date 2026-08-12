# Long-running work

Record task, start time, process/runtime, expected bound, checkpoint, resource limit, and safe resume command.

## 변경 없는 복원기 반복 실행 금지

- 증상: 긴 에뮬레이션이나 복원기가 출력 없이 끝나지 않자 같은 코드와 입력을 여러 번 다시 실행한다.
- 재사용 가능한 교훈: 한 solver 버전은 한 번만 실행한다. 실패·무출력·장시간 실행 후에는 재시도 전에 반드시 계측, bound 또는 코드가 실질적으로 달라져야 한다.
- 가장 싼 확인법: stage 이름, 마지막 통과 단계, hook 횟수와 현재 block 번호처럼 비밀이 아닌 진행 마커를 추가하고, 명령에 명시적인 instruction count 또는 timeout을 둔다. 다음 실행은 바뀐 한 요소를 기록한다.
- 환경/적용 한계: 첫 실행이 외부 부하로 명확히 중단된 경우에는 동일 버전을 한 번 재개할 수 있지만, 반복 실행을 일반적인 디버깅 방법으로 사용하지 않는다.

## 전체 에뮬레이션보다 함수 단위 호출

- 증상: entry부터 전체 프로그램을 에뮬레이션하며 syscall, allocator, TLS, 종료 처리까지 재현하느라 실행 시간이 길어지고 blocker가 늘어난다.
- 재사용 가능한 교훈: 입력·출력 계약이 확인된 내부 함수만 synthetic stack과 sentinel return address로 호출한다. 프로그램 전체 진행이 꼭 필요한 경우에도 상태 초기화와 stage 전이 함수까지만 연결한다.
- 가장 싼 확인법: target 함수의 인자 레지스터, 읽고 쓰는 메모리 구간, 반환값만 먼저 적고 최소 메모리 map과 stub으로 한 호출을 재현한다.
- 환경/적용 한계: signal, thread, self-modifying code 또는 호출자 의존 전역 상태가 핵심이면 함수 단위 모델이 불완전할 수 있으므로 실제 의존성을 하나씩 추가한다.
