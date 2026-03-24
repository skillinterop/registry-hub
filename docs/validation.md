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

## What It Checks

1. 각 메타데이터 파일이 대응하는 JSON Schema를 통과하는지
2. `hub-config.json.sources` 와 `registry-catalog.jsonld.hasPart` 가 같은 membership를 나타내는지
3. `scripts/generate-index.sh` 를 다시 실행했을 때 생성 결과가 커밋된 `hub-index.json` 과 일치하는지
4. generator 실행 중 `WARNING:` 이 발생하지 않는지

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
