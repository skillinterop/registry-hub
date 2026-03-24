# Registry Validation

로컬에서 허브와 leaf registry 메타데이터를 검증하는 방법을 정리한다.

## Command

```bash
bash scripts/validate-registry-contracts.sh
```

이 명령은 다음을 검증한다.

- `hub-config.json`
- `registry-catalog.jsonld`
- `hub-index.json`
- `../skill-registry/index.jsonld`
- `../cao-profile-registry/index.jsonld`
- `../reprogate-registry/index.jsonld`

## CI Usage

GitHub Actions 같은 깨끗한 runner에서는 먼저 hub repo 의 의존성을 고정된 방식으로 설치해야 한다.

```bash
npm ci
bash scripts/validate-registry-contracts.sh
```

leaf PR 처럼 checkout 된 sibling repo 를 기준으로 허브 검증을 돌릴 때는 아래 환경 변수를 함께 준다.

```bash
REGISTRY_USE_LOCAL_SOURCES=1 \
REGISTRY_WORKSPACE_ROOT=/path/to/workspace-root \
bash scripts/validate-registry-contracts.sh
```

이 모드에서는 `generate-index.sh` 가 raw GitHub `main` 만 보지 않고, `REGISTRY_WORKSPACE_ROOT` 아래의 checked-out sibling repo (`skill-registry`, `cao-profile-registry`, `reprogate-registry`) 를 읽는다. 대신 출력되는 `sourceCatalog` 와 `artifactUrl` 은 계속 canonical GitHub raw URL 형태를 유지한다.

## What It Checks

1. 각 메타데이터 파일이 대응하는 JSON Schema를 통과하는지
2. `hub-config.json.sources` 와 `registry-catalog.jsonld.hasPart` 가 같은 membership를 나타내는지
3. `scripts/generate-index.sh` 를 다시 실행했을 때 생성 결과가 커밋된 `hub-index.json` 과 일치하는지
4. generator 실행 중 fetch 실패, invalid JSON, missing local checkout 같은 문제가 없는지

## Output Format

성공한 파일은 다음 형식으로 출력된다.

```text
OK registry-hub-repo/hub-config.json
OK skill-registry/index.jsonld
```

실패한 파일은 다음 형식으로 출력된다.

```text
FAIL <file-path>: <reason>
```

예시:

```text
FAIL registry-hub-repo/registry-catalog.jsonld: hasPart does not match hub-config.json.sources
FAIL skill-registry/index.jsonld: data/dataset/0/url must match pattern "^\\./skills/[^/]+/SKILL\\.md$"
```

## Failure Triage

- `FAIL registry-hub-repo/hub-config.json: ...`
  `hub-config.json` 또는 `schemas/hub-config.schema.json` 계약이 깨진 상태다.
- `FAIL registry-hub-repo/registry-catalog.jsonld: ...`
  공개 허브 엔트리포인트 자체가 schema를 통과하지 않거나 `hub-config.json` 과 membership가 어긋난 상태다.
- `FAIL registry-hub-repo/hub-index.json: ...`
  생성된 집계 결과가 schema를 통과하지 않거나 재생성 결과와 달라진 상태다.
- `FAIL skill-registry/index.jsonld: ...`
- `FAIL cao-profile-registry/index.jsonld: ...`
- `FAIL reprogate-registry/index.jsonld: ...`
  해당 leaf repo의 `index.jsonld` 또는 `schemas/index.schema.json` 계약이 깨진 상태다.
- `FAIL registry-hub-repo/scripts/generate-index.sh: ...`
  generator 가 fatal 상태로 중단된 것이다. fetch 실패, invalid JSON, missing local checkout 은 더 이상 warning 이 아니라 CI 차단 사유다.

## Leaf-local Validation

leaf repo 자체 무결성만 빠르게 확인하고 싶을 때는 `validate-leaf-local.sh` 를 사용한다.

```bash
bash scripts/validate-leaf-local.sh \
  --repo-root ../skill-registry \
  --logical-root skill-registry \
  --schema-file ../skill-registry/schemas/index.schema.json \
  --artifact-dir skills \
  --artifact-file SKILL.md
```

이 스크립트는 다음을 확인한다.

1. 해당 leaf 의 `index.jsonld` 가 schema 를 통과하는지
2. 각 `dataset[].url` 이 정확히 `./<artifact-dir>/<name>/<artifact-file>` 형태인지
3. URL 이 가리키는 artifact 파일이 실제로 존재하는지

출력 형식은 기존과 동일하게 유지된다.

```text
OK skill-registry/index.jsonld
FAIL skill-registry/index.jsonld: artifact not found at ...
```

## Override Seams

실패 경로를 재현하거나 특정 파일만 바꿔 검증하고 싶을 때는 다음 환경 변수를 사용한다.

- `REGISTRY_HUB_CONFIG_OVERRIDE`
- `REGISTRY_CATALOG_OVERRIDE`
- `HUB_INDEX_OVERRIDE`

예시:

```bash
REGISTRY_HUB_CONFIG_OVERRIDE=/tmp/bad-hub-config.json \
bash scripts/validate-registry-contracts.sh
```

이 경우에도 출력 파일명은 논리 경로 기준으로 유지된다. 예를 들어 실제 override 파일을 읽더라도 출력은 `FAIL registry-hub-repo/hub-config.json: ...` 형식을 사용한다.

## CI Failure Policy

- generator warning 은 더 이상 soft warning 이 아니다. CI 에서는 fatal failure 로 취급한다.
- `REGISTRY_USE_LOCAL_SOURCES=1` 모드에서 필요한 sibling checkout 이 없으면 fatal failure 로 취급한다.
- 출력 계약은 계속 `OK ...` / `FAIL <path>: <reason>` 형식을 유지한다.
