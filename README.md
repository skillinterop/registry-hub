# registry-hub

인터옵 에코시스템의 최상위 허브 레지스트리.

## 개요

이 저장소는 **인덱스/집계 저장소**이며, 콘텐츠 저장소가 아님. Leaf 레지스트리를 참조로만 포함하고 실제 패키지 콘텐츠는 저장하지 않음. Wrapper 도구는 이 저장소 하나만 등록하면 나머지를 재귀적으로 해석할 수 있음.

## 디렉토리 구조

```
registry-hub/
├── hub-config.json            # 소스 참조가 담긴 Hub 설정
├── hub-index.json             # 생성된 인덱스 (sync 전까지 비어있음)
├── schemas/
│   ├── hub-config.schema.json # hub-config.json용 JSON Schema
│   ├── hub-index.schema.json  # hub-index.json용 JSON Schema
│   └── shared/                # 공유 스키마 정의
│       ├── common.schema.json       # 공통 타입 (Version, Channel 등)
│       └── manifest-base.schema.json # Manifest 기본 속성
├── sources/                   # 캐시된 manifest 스냅샷 (초기에는 비어있음)
│   └── .gitkeep
├── docs/
│   └── resolution.md          # Resolution 흐름 문서
├── README.md
└── .gitignore
```

## 등록된 소스

| Registry Type | Repository | Branch | Channel |
|---------------|------------|--------|---------|
| skill | [skillinterop/skill-registry](https://github.com/skillinterop/skill-registry) | main | stable |
| cao-profile | [skillinterop/cao-profile-registry](https://github.com/skillinterop/cao-profile-registry) | main | stable |
| reprogate | [skillinterop/reprogate-registry](https://github.com/skillinterop/reprogate-registry) | main | stable |

## Hub Config 형식

`hub-config.json`은 어떤 leaf 레지스트리를 포함할지 정의:

```json
{
  "hubVersion": "0.1.0",
  "sources": [
    {
      "registryType": "skill",
      "repoUrl": "https://github.com/skillinterop/skill-registry",
      "manifestPath": "manifest.json",
      "branch": "main",
      "channel": "stable"
    }
  ]
}
```

## 소스 추가 방법

1. Leaf 레지스트리에 유효한 `manifest.json`이 있는지 확인
2. `hub-config.json`의 `sources` 배열에 새 항목 추가
3. `registryType`, `repoUrl`, `manifestPath`, `branch`, `channel` 지정
4. PR 생성

## 우선순위 규칙

여러 소스가 동일한 `canonicalId`를 가진 항목을 포함할 때:

1. **선언 순서 우선** — `hub-config.json`에서 먼저 나열된 소스가 우선권을 가짐
2. **타입 간 충돌 불가** — `canonicalId`가 `registryType`을 prefix로 포함하므로 타입이 다르면 충돌 없음

자세한 내용은 [docs/resolution.md](./docs/resolution.md) 참조.

## 핵심 원칙

- **Manifest-only 연결** — Hub는 leaf repo를 URL로만 참조, git submodule 사용 안 함
- **콘텐츠 벤더링 금지** — 실제 패키지는 leaf 레지스트리에만 존재
- **재귀적 해석** — Wrapper 도구가 이 hub를 fetch한 후 각 leaf를 해석
- **채널 필터링** — 소스별로 `stable` 또는 `all` 채널 필터 가능

## Shared Schema

공통 타입 정의는 `schemas/shared/`에 위치:

| 파일 | 내용 |
|------|------|
| `common.schema.json` | SemanticVersion, Channel, RegistryType, KebabCaseName, ItemStatus, ISODateTime |
| `manifest-base.schema.json` | BaseManifestProperties, BaseManifestItem |

Leaf 레지스트리는 GitHub raw URL로 이 스키마들을 `$ref` 참조:
```json
"$ref": "https://raw.githubusercontent.com/skillinterop/registry-hub/main/schemas/shared/common.schema.json#/definitions/Channel"
```

## 관련 저장소

- [`skill-registry`](https://github.com/skillinterop/skill-registry) — Skill leaf 레지스트리
- [`cao-profile-registry`](https://github.com/skillinterop/cao-profile-registry) — CAO profile leaf 레지스트리
- [`reprogate-registry`](https://github.com/skillinterop/reprogate-registry) — ReproGate leaf 레지스트리

## TODO

- [x] 공유 스키마 추출 (`schemas/shared/`)
- [ ] hub-index 생성 로직 구현
- [ ] 자동 인덱스 재생성 CI workflow 추가

## 라이선스

MIT
