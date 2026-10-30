# Long-running work

Record local fuzzing or test task, target build, corpus, limits, checkpoint, and safe resume command. Do not run it against remote infrastructure.

## 취약점 발견 뒤 고비용 상태 생성으로 너무 일찍 넘어가지 않기

- **증상:** 신뢰 경계나 rollback 불일치 같은 유효한 primitive를 찾았지만, 이를 발동할 선행 상태를 만들기 위해 게임 탐색·solver·fuzzing 같은 고비용 계산을 즉시 시작한다. 계산은 계속 진행되지만 `work/solve.py`는 미완성이고 flag 경로의 불확실성은 줄지 않는다.
- **재사용 가능한 교훈:** primitive와 trigger는 분리해서 평가한다. 고비용 trigger 생성 전에 이미 관찰된 route, 비활성 기능의 원격 차이, 상태 import/fork/restore, 클라이언트 제공 식별자, rollback 뒤 남는 다른 메모리 상태처럼 동일 primitive에 도달하는 저비용 상태 주입 경로를 먼저 소진한다. “실행 가능”은 “최단 경로”의 근거가 아니다.
- **가장 싼 확인법:** 장시간 명령 전에 `목표 상태`, `필요한 불변조건`, `후보당 비용`, `최대 후보 수`, `예상 총시간`, `중단 조건`을 한 줄씩 계산한다. 예상 시간이 60초를 넘거나 후보 수가 입력에 따라 커지면, 상태 생성 없이 primitive를 확인할 수 있는 요청 1회와 대체 상태 주입 경로 2개를 먼저 검사한다.
- **환경/적용 한계:** 문제 설계상 계산 퍼즐 자체가 유일한 trigger이고 다른 상태 주입면이 없다는 정적·동적 증거가 있으면 bounded 계산을 사용할 수 있다. 이때도 로컬에서만 실행하고 wall-clock 제한, 후보·깊이 상한, 진행 checkpoint를 설정하며 단일 도구 호출이 전체 풀이 제한을 점유하게 두지 않는다.
