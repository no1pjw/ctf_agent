---
name: ctf-web
description: Solve explicitly authorized local CTF web challenges from supplied source and isolated containers, using bounded route and trust-boundary analysis with reproducible flag derivation.
---

# CTF Web

1. `work/web-runtime.env`를 읽고 기록된 loopback origin만 사용한다. 입력은 수정하지 않고 외부 host에는 접속하지 않는다.
2. 소스에서 flag까지 필요한 route, role/state, parser, sink만 좁혀 가장 싼 가설 최대 세 개를 세운다.
3. 각 가설은 baseline → 단일 mutation → 필요할 때만 negative control로 검증한다. broad scanner, brute force, DoS, 외부 callback은 금지한다.
4. 다음 요청이 명확하면 진행 설명 없이 실행한다. blocker가 생겼을 때만 관련 feedback 하나를 읽는다.
5. 준비된 `work/solve.py`를 최소 재현으로 수정한다. 상세 trace와 write-up은 flag 전에는 만들지 않는다.
6. 실제 flag가 재현되면 즉시 `FLAG=<value>`를 출력하고 `.solved=verified`를 기록한 뒤 종료한다.

Compose/Dockerfile이 없으면 STATIC-ONLY로 분석하며, 동적 검증은 work 전용 Docker 격리 안에서만 수행한다.
