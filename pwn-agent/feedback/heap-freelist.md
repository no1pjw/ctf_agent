# Heap freelist lessons

## safe-linking encoded NULL을 먼저 찾는다

- **증상:** 해제 뒤 포인터가 남아 있어 freed chunk의 첫 word를 읽거나 쓸 수 있고, allocator가 safe-linking을 사용한다.
- **재사용 가능한 교훈:** singly linked freelist의 마지막 항목은 다음 포인터가 NULL이므로 저장값 자체가 해당 link 저장 위치에서 유도된 safe-linking 값이다. 임의의 heap 포인터 누출을 먼저 찾기보다, 같은 size class를 채우고 가장 아래 항목의 encoded NULL을 읽는 편이 더 싸고 직접적일 수 있다.
- **가장 싼 확인법:** 동일 size class의 항목을 순서대로 해제한 뒤 마지막 항목의 첫 word가 주소 정렬에 맞는 작은 값인지 확인한다. 그 값으로 인코딩한 후보를 한 번만 할당해 예상 freelist 전이가 일어나는지 검증한다.
- **환경/적용 한계:** 인코딩식과 freelist 구조는 allocator·libc 버전에 종속된다. link 저장 위치가 서로 다른 페이지라면 한 항목에서 얻은 값을 다른 항목에 그대로 재사용할 수 없다. tcache와 fastbin의 포화 상태도 따로 추적한다.

## encoded NULL과 인접 link로 페이지 내 주소를 유일화한다

- **증상:** safe-linking freelist의 tail과 그 앞 노드를 함께 읽을 수 있지만, encoded NULL로는 link 저장 위치의 페이지만 복원된다.
- **재사용 가능한 교훈:** 두 노드의 간격이나 size class가 알려져 있다면, 정렬된 페이지 내 후보를 열거해 `후보 next 주소 XOR link 위치에서 유도된 값 == 저장된 encoded link`를 만족하는 배치를 찾을 수 있다. 별도 full heap pointer leak 없이도 정확한 chunk 주소가 유일해질 수 있다.
- **가장 싼 확인법:** 한 페이지의 allocator 정렬 후보만 순회하고 알려진 chunk 간격을 적용해 식을 만족하는 해의 개수를 센다. 해가 정확히 하나가 아니면 exploit을 진행하지 않는다.
- **환경/적용 한계:** 인코딩식, link 필드 위치, chunk 간격이 정확해야 한다. 후보 노드가 페이지 경계를 넘거나 allocator가 추가 tagging·randomization을 쓰면 탐색식과 범위를 다시 세워야 한다.

## `calloc`도 allocator 경로를 별도로 검증한다

- **증상:** tcache가 찬 상태에서 fastbin을 조작했지만, `malloc` 계열 호출이 먼저 tcache를 소비해 의도한 poisoned chain에 닿지 않는다.
- **재사용 가능한 교훈:** 일부 glibc 버전의 `calloc`은 동일 크기의 `malloc`과 다른 경로를 밟아 tcache 항목이 남아 있어도 fastbin 쪽 후보를 반환할 수 있다. exploit 설계에서 API 이름을 동의어로 취급하지 말고 실제 제공 libc의 allocation path를 이용한다.
- **가장 싼 확인법:** 제공 컨테이너에서 한 size class의 tcache와 fastbin에 서로 구분되는 표식을 넣고, `malloc`과 `calloc` 각 1회의 반환 출처만 비교한다.
- **환경/적용 한계:** 버전과 패치에 따라 달라지는 구현 세부사항이다. zeroing 범위, chunk 검증, consolidation 가능성까지 포함해 제공 런타임에서 확인해야 하며 다른 libc에 일반화하지 않는다.

## 정적 영역의 가짜 chunk는 인접 필드와 함께 설계한다

- **증상:** non-PIE 또는 주소가 알려진 writable 정적 영역에 allocator가 받아들일 수 있는 크기 필드가 있고, 그 user area가 전역 포인터 테이블 같은 민감한 필드와 겹친다.
- **재사용 가능한 교훈:** freelist poisoning의 목표를 곧바로 최종 쓰기 주소로 잡기보다, 검증을 통과하는 가짜 chunk를 먼저 반환받아 인접 포인터 필드를 재지정하면 제한된 UAF write를 임의 주소 쓰기로 승격할 수 있다.
- **가장 싼 확인법:** 정적 레이아웃에서 `header -> user area -> 민감 필드` 겹침을 종이에 먼저 표시하고, 짧은 allocation 입력이 목표 필드만 바꾸며 이웃 필드를 보존하는지 확인한다.
- **환경/적용 한계:** 필요한 정렬, size class, 다음 chunk 검사와 writable 여부는 allocator 및 보호 설정에 따라 다르다. Full RELRO 등으로 최종 목표가 쓰기 불가능하면 별도 writable control target이 필요하다.
