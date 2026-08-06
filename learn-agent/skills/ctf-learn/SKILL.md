---
name: ctf-learn
description: Distill verified, reusable lessons from a completed authorized CTF challenge into the matching category feedback index. Use after a CTF solve or substantial failed attempt when Codex should preserve novel techniques, failure patterns, environment caveats, or cheaper future tests without storing challenge-specific answers.
---

# CTF Learn

사용자에게 보이는 진행 상황과 결과는 한국어로 작성한다.

1. 프롬프트에 지정된 문제의 `work/writeup.md`, solver 순서로 검토한다. 기본 읽기·검색 호출은 6회 이내로 제한하고, write-up의 핵심 주장이 불충분할 때만 정확히 알려진 최소 evidence 파일을 추가로 읽는다. `input/` 전체를 열거하지 않는다. 문제를 다시 풀거나 바이너리를 실행하거나 네트워크에 접속하지 않는다.
2. 지정된 feedback 디렉터리의 `index.md`를 먼저 읽고, 관련 문서만 추가로 읽어 `rg`로 중복을 확인한다.
3. 관찰 또는 재현 증거가 있고, 다른 문제에도 적용 가능하며, 기존 피드백에 없고, 다음 저비용 확인법이나 명확한 주의점이 있는 교훈만 채택한다.
4. 플래그, 문제명, 정확한 주소·offset·payload, 계정·토큰 및 문제 전용 경로는 저장하지 않는다. 검증되지 않은 추측이나 단순한 풀이 요약도 저장하지 않는다.
5. 새 교훈은 기존 주제 문서에 합치거나 짧은 kebab-case 주제 문서를 만들고 `index.md`에 검색 단서와 함께 연결한다. 한 사실을 여러 파일에 중복 기록하지 않는다.
6. 지정된 feedback 디렉터리 밖의 스킬, 정책, 도구, challenge 산출물은 수정하지 않는다. 새 교훈이 없으면 어떤 파일도 수정하지 않는다. 변경 확인을 위해 Git 명령을 실행하지 말고 실제 편집 여부만 보고한다.

각 항목은 가능하면 `증상`, `재사용 가능한 교훈`, `가장 싼 확인법`, `환경/적용 한계`를 간결하게 포함한다. 마지막에 추가·통합·건너뛴 내용을 한국어로 보고한다.
