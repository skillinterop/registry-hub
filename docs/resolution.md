# Registry Resolution

registry-hub가 leaf 레지스트리를 해석하고 집계하는 방식을 설명.

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
│  manifest.json  │ │  manifest.json  │ │  manifest.json  │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

1. **hub-config.json 읽기** — Wrapper가 hub의 설정 파일을 읽음
2. **소스 순회** — `sources` 배열의 각 소스에 대해:
   - 지정된 `repoUrl`, `branch`, `manifestPath`에서 leaf 레지스트리의 `manifest.json` fetch
   - `channel`에 따라 항목 필터링 (stable-only 또는 all)
3. **항목 집계** — 모든 항목을 통합 `hub-index.json`으로 결합
4. **충돌 처리** — 두 소스가 동일한 `canonicalId`를 가진 항목이 있으면, `hub-config.json`에서 먼저 선언된 소스가 우선

## Include 항목은 Repo와 Ref만 참조

hub의 `hub-config.json`은 leaf 레지스트리에 대한 **참조**만 저장:

```json
{
  "registryType": "skill",
  "repoUrl": "https://github.com/skillinterop/skill-registry",
  "manifestPath": "manifest.json",
  "branch": "main",
  "channel": "stable"
}
```

실제 패키지 콘텐츠를 복사하거나 벤더링하지 않음. Hub는 **인덱스/집계 저장소**이지 콘텐츠 저장소가 아님.

## Submodule을 선택하지 않은 이유

| 접근 방식 | 장점 | 단점 |
|----------|------|------|
| **Manifest-only (선택됨)** | 단순함, git 복잡성 없음, CI/CD 쉬움, 명확한 분리 | 해석 시점에 fetch 필요 |
| **Git submodule** | 콘텐츠가 로컬에 있음 | 복잡한 업데이트, 중첩된 git 상태, 어려운 CI |
| **Git subtree** | 평탄한 히스토리, 인라인 콘텐츠 | 비대해진 repo, 동기화 복잡성, merge 충돌 |

Manifest-only 접근 방식은 각 저장소를 독립적이고 단순하게 유지함. Wrapper 도구가 sync 작업 중에 on-demand로 leaf manifest를 fetch.

## Leaf 콘텐츠 벤더링 금지

Hub는 다음을 **해서는 안 됨**:
- Leaf 레지스트리에서 `skills/`, `profiles/`, `gates/` 디렉토리 복사
- Hub 저장소에 실제 패키지 콘텐츠 저장
- Leaf manifest 항목을 hub 파일에 직접 인라인

Hub는 다음을 **해야 함**:
- Leaf 레지스트리를 URL로만 참조
- Fetch한 manifest에서 `hub-index.json`을 동적으로 생성
- 캐시된 manifest 스냅샷을 `sources/`에 저장 (각 sync마다 재생성)

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
| `"stable"` | `item.channel === "stable"`인 항목만 포함 |
| `"all"` | 채널과 관계없이 모든 항목 포함 |

기본값은 프로덕션 사용을 위해 `"stable"`.

## Canonical ID 형식

각 레지스트리 타입별 `canonicalId` 패턴:

| Type | Pattern | 예시 |
|------|---------|------|
| skill | `skill/{namespace}/{name}@{version}` | `skill/org/workmux-router@1.0.0` |
| cao-profile | `cao-profile/{namespace}/{name}@{version}` | `cao-profile/org/default@1.0.0` |
| reprogate | `reprogate/{namespace}/{name}@{version}` | `reprogate/org/code-review@1.0.0` |
