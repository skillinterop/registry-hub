// resolve-import-item.mjs — resolve a canonical ID to a hub-index item
// Starts from registry-catalog.jsonld, extracts distribution[0].contentUrl,
// loads hub-index.json, and returns the matching item.

import { readResource, resolveRef } from './read-resource.mjs';

const DEFAULT_CATALOG =
  'https://raw.githubusercontent.com/skillinterop/registry-hub/main/registry-catalog.jsonld';

/**
 * Resolve a canonical ID to its hub-index item.
 *
 * @param {string} canonicalId - e.g. "skill/org/[MASKED_EMAIL]"
 * @param {{ catalog?: string }} options
 * @returns {Promise<object>} the matching hub-index item
 */
export async function resolveImportItem(canonicalId, options = {}) {
  const catalogSource = options.catalog || DEFAULT_CATALOG;

  // 1. Load the catalog
  const { data: catalog, sourceDir: catalogDir } = await readResource(catalogSource);

  // 2. Extract distribution[0].contentUrl
  const distributions = catalog.distribution;
  if (!Array.isArray(distributions) || distributions.length === 0) {
    throw new Error(`registry-catalog has no distribution entries: ${catalogSource}`);
  }
  const contentUrl = distributions[0].contentUrl;
  if (!contentUrl) {
    throw new Error(`distribution[0].contentUrl is missing in catalog: ${catalogSource}`);
  }

  // 3. Resolve the hub index location (may be relative to local catalog)
  const indexSource = resolveRef(contentUrl, catalogDir);

  // 4. Load the hub index
  const { data: hubIndex } = await readResource(indexSource);

  const items = hubIndex.items;
  if (!Array.isArray(items)) {
    throw new Error(`hub-index has no items array: ${indexSource}`);
  }

  // 5. Find matching item(s)
  const matches = items.filter((item) => item.canonicalId === canonicalId);

  if (matches.length === 0) {
    throw new Error(`Canonical ID not found: ${canonicalId}`);
  }
  if (matches.length > 1) {
    throw new Error(`Canonical ID is ambiguous: ${canonicalId} (${matches.length} matches)`);
  }

  return matches[0];
}
