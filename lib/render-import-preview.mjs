// render-import-preview.mjs — print a human-readable import preview
// Outputs exactly the fields required by Phase 4 preview spec:
//   Canonical ID, Registry Type, Version, Source Repo,
//   Artifact Path, Artifact URL, Destination

/**
 * Render an import preview to stdout.
 *
 * @param {object} item        - hub-index item
 * @param {string} destination - resolved destination path
 */
export function renderImportPreview(item, destination) {
  const lines = [
    `Canonical ID:  ${item.canonicalId}`,
    `Registry Type: ${item.registryType}`,
    `Version:       ${item.version}`,
    `Source Repo:   ${item.sourceRepo}`,
    `Artifact Path: ${item.artifactPath}`,
    `Artifact URL:  ${item.artifactUrl}`,
    `Destination:   ${destination}`,
  ];
  process.stdout.write(lines.join('\n') + '\n');
}
