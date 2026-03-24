# Registry Resolution

registry-hub가 leaf 레지스트리를 해석하고 집계하는 방식을 설명.

## Canonical Source Of Truth

허브가 어떤 leaf 레지스트리를 포함하는지는 `hub-config.json`이 유일하게 결정한다.

- 유지보수자 원본: `hub-config.json`
- 공개 엔트리포인트: `registry-catalog.jsonld`
- 생성 산출물: `hub-index.json`

즉, `registry-catalog.jsonld`의 `hasPart`는 사람이 별도로 관리하는 목록이 아니라 `hub-config.json.sources`와 같은 멤버십을 반영해야 한다.

## Hub → Leaf Resolution 흐름

```
                    ┌─────────────────┐
                    │  registry-hub   │
                    │ hub-config.json │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ skill-registry  │ │ cao-profile-reg │ │reprogate-registry│
│   index.jsonld  │ │   index.jsonld  │ │   index.jsonld   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   hub-index.json │
                    └─────────────────┘
```

1. **hub-config.json 읽기** — 유지보수 도구가 `sources`를 읽어 어떤 레지스트리를 허브에 포함할지 결정함
2. **소스 순회** — `sources` 배열의 각 소스에 대해:
   - 지정된 `repoUrl`, `branch`, `catalogPath`에서 leaf 레지스트리의 `index.jsonld` fetch
   - `repoUrl`은 `https://github.com/...` 에서 `https://raw.githubusercontent.com/.../{branch}/{catalogPath}` 로 해석됨
   - `channel`에 따라 dataset 항목을 필터링함 (`stable` 또는 `all`)
3. **공개 엔트리포인트 반영** — `registry-catalog.jsonld.hasPart`는 `hub-config.json.sources`와 동일한 레지스트리 집합을 보여줌
4. **항목 집계** — leaf catalog의 `dataset[]` 항목을 통합 `hub-index.json`으로 결합
5. **충돌 처리** — 두 소스가 동일한 `canonicalId`를 가지면 `hub-config.json`에 먼저 선언된 소스가 우선

## registry-catalog.jsonld와 hub-config.json의 관계

`hub-config.json`은 유지보수자용 원본이고, `registry-catalog.jsonld`는 외부 소비자가 읽는 공개 진입점이다.

`registry-catalog.jsonld.hasPart`는 다음 규칙으로 `hub-config.json.sources`에서 유도된다.

```json
{
  "registryType": "skill",
  "repoUrl": "https://github.com/skillinterop/skill-registry",
  "catalogPath": "index.jsonld",
  "branch": "main",
  "channel": "all"
}
```

이 source는 공개 엔트리포인트에서 다음 `hasPart` 항목으로 나타난다.

```json
{
  "@type": "DataCatalog",
  "name": "Skill Registry",
  "url": "https://raw.githubusercontent.com/skillinterop/skill-registry/main/index.jsonld",
  "skillinterop:registryType": "skill"
}
```

즉, `registry-catalog.jsonld`는 `hub-config.json`과 독립적으로 관리하면 안 되고, 항상 같은 registry membership를 보여줘야 한다.

## Submodule을 선택하지 않은 이유

| 접근 방식 | 장점 | 단점 |
|----------|------|------|
| **JSON-LD catalog + generated index (선택됨)** | 실제 저장소 상태와 일치, 공개 엔트리포인트 유지, leaf 구조와 자연스럽게 연결 | 집계 시점에 fetch 필요 |
| **Git submodule** | 콘텐츠가 로컬에 있음 | 복잡한 업데이트, 중첩된 git 상태, 어려운 CI |
| **Git subtree** | 평탄한 히스토리, 인라인 콘텐츠 | 비대해진 repo, 동기화 복잡성, merge 충돌 |

이 접근 방식은 각 저장소를 독립적으로 유지하면서도 허브에 공개 진입점과 집계 인덱스를 둘 수 있게 한다.

## Leaf 콘텐츠 벤더링 금지

Hub는 다음을 **해서는 안 됨**:
- Leaf 레지스트리에서 `skills/`, `profiles/`, `gates/` 디렉토리 복사
- Hub 저장소에 실제 패키지 콘텐츠 저장
- Leaf 항목 내용을 허브에 수동으로 복붙

Hub는 다음을 **해야 함**:
- Leaf 레지스트리를 URL로만 참조
- Fetch한 `index.jsonld`에서 `hub-index.json`을 동적으로 생성
- 필요하면 캐시된 leaf catalog 스냅샷을 `sources/`에 저장

## 우선순위와 충돌 처리

여러 leaf 레지스트리가 포함될 때, 충돌은 **소스 선언 순서**로 해결:

1. 소스는 `hub-config.json`에 나타나는 순서대로 처리
2. 동일한 `canonicalId`를 가진 항목이 여러 소스에 있으면, 첫 번째 소스가 우선
3. `canonicalId`가 `registryType`을 prefix로 포함하므로, 타입 간 충돌은 불가능

우선순위 예시:
```json
"sources": [
  { "registryType": "skill", ... },      // 우선순위 1
  { "registryType": "cao-profile", ... }, // 우선순위 2
  { "registryType": "reprogate", ... }    // 우선순위 3
]
```

## 채널 필터링

각 소스는 어떤 채널을 포함할지 지정 가능:

| Channel | 동작 |
|---------|------|
| `"stable"` | `skillinterop:channel == "stable"` 인 dataset 항목만 포함 |
| `"all"` | 채널과 관계없이 모든 dataset 항목 포함 |

현재 bootstrap 상태에서는 세 leaf registry의 기존 항목을 모두 노출하기 위해 `"all"` 이 안전하다.

## Canonical ID 형식

각 레지스트리 타입별 `canonicalId` 패턴:

| Type | Pattern | 예시 |
|------|---------|------|
| skill | `skill/{namespace}/{name}@{version}` | `skill/org/workmux-router@1.0.0` |
| cao-profile | `cao-profile/{namespace}/{name}@{version}` | `cao-profile/org/default@1.0.0` |
| reprogate | `reprogate/{namespace}/{name}@{version}` | `reprogate/org/code-review@1.0.0` |

## 공개 소비자 관점

외부 도구나 프로젝트는 두 경로를 사용할 수 있다.

1. `registry-catalog.jsonld` 를 읽고 `hasPart` 로 현재 활성 leaf catalog를 해석한다.
2. `hub-index.json` 이 존재하면 생성된 집계 결과를 직접 소비한다.

핵심은 둘 다 같은 source membership를 보여줘야 한다는 점이다. `hub-config.json`과 다른 `hasPart` 목록이 생기면 허브 계약이 깨진다.
