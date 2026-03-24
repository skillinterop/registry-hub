# registry-hub

인터옵 에코시스템의 최상위 허브 레지스트리.

## 개요

이 저장소는 leaf 레지스트리를 직접 담는 콘텐츠 저장소가 아니라, 어떤 레지스트리를 허브에 포함할지 선언하고 공개 허브 메타데이터를 배포하는 **허브 저장소**다.

- `hub-config.json`: 유지보수자가 수정하는 canonical source-of-truth
- `registry-catalog.jsonld`: 외부 도구와 프로젝트가 읽는 public hub entry point
- `hub-index.json`: `hub-config.json`을 기준으로 생성되는 집계 결과물

즉, 유지보수자는 `hub-config.json`을 수정하고, 소비자는 `registry-catalog.jsonld` 또는 생성된 `hub-index.json`을 읽는다.

## 디렉토리 구조

```text
registry-hub/
├── hub-config.json            # 허브에 포함할 leaf 레지스트리 선언
├── hub-index.json             # 생성된 허브 인덱스
├── registry-catalog.jsonld    # 공개 허브 엔트리포인트
├── schemas/
│   ├── hub-config.schema.json # hub-config.json용 JSON Schema
│   ├── hub-index.schema.json  # hub-index.json용 JSON Schema
│   └── shared/                # 공유 스키마 정의
├── sources/                   # 동기화 시 생성되는 소스 캐시
├── docs/
│   └── resolution.md          # 허브 해석 흐름 문서
└── README.md
```

## 현재 허브에 포함된 레지스트리

| Registry Type | Repository | Catalog | Branch | Channel |
|---------------|------------|---------|--------|---------|
| skill | [skillinterop/skill-registry](https://github.com/skillinterop/skill-registry) | `index.jsonld` | main | all |
| cao-profile | [skillinterop/cao-profile-registry](https://github.com/skillinterop/cao-profile-registry) | `index.jsonld` | main | all |
| reprogate | [skillinterop/reprogate-registry](https://github.com/skillinterop/reprogate-registry) | `index.jsonld` | main | all |

## Canonical Contract

`hub-config.json`은 허브에 어떤 leaf 레지스트리를 포함할지 선언하는 유일한 유지보수용 원본 파일이다. 각 source는 leaf 저장소의 GitHub URL과 해당 저장소의 `index.jsonld` 위치를 명시한다.

```json
{
  "hubVersion": "0.1.0",
  "sources": [
    {
      "registryType": "skill",
      "repoUrl": "https://github.com/skillinterop/skill-registry",
      "catalogPath": "index.jsonld",
      "branch": "main",
      "channel": "all"
    },
    {
      "registryType": "cao-profile",
      "repoUrl": "https://github.com/skillinterop/cao-profile-registry",
      "catalogPath": "index.jsonld",
      "branch": "main",
      "channel": "all"
    },
    {
      "registryType": "reprogate",
      "repoUrl": "https://github.com/skillinterop/reprogate-registry",
      "catalogPath": "index.jsonld",
      "branch": "main",
      "channel": "all"
    }
  ]
}
```

`schemas/hub-config.schema.json`은 이 계약을 검증하며, `registryType`, `repoUrl`, `catalogPath`, `branch`, `channel` 다섯 필드를 요구한다.

## Hub Resolution Flow

1. 유지보수자가 `hub-config.json`에서 허브에 포함할 레지스트리를 선언한다.
2. 허브 도구가 각 source의 `repoUrl`, `branch`, `catalogPath`를 따라 leaf `index.jsonld`를 읽는다.
3. source 선언 순서와 `channel` 필터를 적용해 허브 메타데이터를 결합한다.
4. 결과를 `hub-index.json`으로 생성하고, 외부 소비자는 `registry-catalog.jsonld`에서 허브 엔트리포인트를 찾는다.

`registry-catalog.jsonld`는 공개용 진입점이고, `hub-config.json`은 유지보수자가 버전 관리하는 내부 source declaration이라는 점이 핵심이다.

## 새 레지스트리 소스 추가 방법

1. 새 leaf 저장소가 GitHub에 존재하고 루트에 `index.jsonld`를 제공하는지 확인한다.
2. `hub-config.json`의 `sources` 배열에 새 source를 추가한다.
3. `registryType`, `repoUrl`, `catalogPath`, `branch`, `channel`을 명시한다.
4. `hub-config.schema.json`과 충돌하지 않는지 검증한 뒤 PR을 연다.

## 공개 허브 메타데이터

- `registry-catalog.jsonld`는 허브가 포함하는 leaf 카탈로그의 공개 진입점이다.
- `hub-index.json`은 허브가 실제로 집계한 결과를 담는 generated artifact다.
- 두 파일 모두 `hub-config.json`에 정의된 source membership를 기준으로 해석되어야 한다.

## 핵심 원칙

- **Hub config is canonical**: 허브에 어떤 레지스트리가 속하는지는 `hub-config.json`만이 결정한다.
- **JSON-LD catalogs are the leaf contract**: leaf 레지스트리는 `index.jsonld`로 자신을 노출한다.
- **No content vendoring**: 실제 패키지 콘텐츠는 각 leaf 저장소에 남고, hub는 메타데이터만 집계한다.
- **Deterministic ordering**: source 우선순위는 `hub-config.json`의 선언 순서를 따른다.

## Validation Targets

현재 허브에서 로컬 검증 대상으로 취급하는 메타데이터 경계는 다음과 같다.

| Metadata File | Schema File | 역할 |
|---------------|-------------|------|
| `hub-config.json` | `schemas/hub-config.schema.json` | 유지보수자용 source-of-truth |
| `registry-catalog.jsonld` | `schemas/registry-catalog.schema.json` | 공개 허브 엔트리포인트 |
| `hub-index.json` | `schemas/hub-index.schema.json` | 생성된 집계 인덱스 |
| leaf `index.jsonld` | `schemas/shared/jsonld-catalog.schema.json` 기반 leaf schema | 리프 레지스트리 공개 카탈로그 |

로컬 검증 명령은 `bash scripts/validate-registry-contracts.sh` 로 제공된다. 자세한 실패 해석은 `docs/validation.md` 에서 다룬다.

## Validate before push

푸시 전에 아래 명령을 실행한다.

```bash
bash scripts/validate-registry-contracts.sh
```

실패 형식과 트러블슈팅은 `docs/validation.md` 를 따른다.

## Publish a leaf item

Leaf registry publication now has one documented flow in the hub repo.

1. Prepare the markdown content file with matching frontmatter.
2. Run `bash scripts/publish-leaf-item.sh ...` with the correct `--registry-type`.
3. Review the selected leaf repo diff and confirm validation passes.

Start with `docs/publish.md` for the canonical workflow and `docs/validation.md` for failure triage.

## Import registry items

Projects can import a registry item from the hub without cloning any registry repository. Use the `npx`-style CLI to preview and import items by canonical identifier.

```bash
# Preview a skill import (codex runtime)
npx @skillinterop/registry-hub-import preview skill/org/[MASKED_EMAIL] --runtime codex

# Preview a CAO profile import
npx @skillinterop/registry-hub-import preview cao-profile/org/[MASKED_EMAIL] --project-root "$PWD"
```

The preview resolves `registry-catalog.jsonld` to find `hub-index.json` and shows the resolved item, source repository, artifact URL, and destination path before any file is written.

See [docs/import.md](docs/import.md) for the full consumer import guide including destination policy and all CLI options.

## GitHub automation rollout

GitHub Actions enforce the shared contract and keep hub artifacts in sync. The rollout uses `configure-github-merge-gates.sh` to apply required checks only after workflow contexts exist. Required checks are enabled only after workflow contexts exist — the script refuses to apply protections until the live check contexts have appeared at least once.

- **Rollout guide:** [docs/github-automation.md](docs/github-automation.md) — workflow inventory, required checks, bot setup, and staged rollout order
- **Rollout script:** `bash scripts/configure-github-merge-gates.sh --owner skillinterop`
- **Validation triage:** [docs/validation.md](docs/validation.md) — OK/FAIL contract interpretation

## 관련 저장소

- [`skill-registry`](https://github.com/skillinterop/skill-registry) — Skill leaf registry
- [`cao-profile-registry`](https://github.com/skillinterop/cao-profile-registry) — CAO profile leaf registry
- [`reprogate-registry`](https://github.com/skillinterop/reprogate-registry) — ReproGate leaf registry

## 라이선스

MIT
