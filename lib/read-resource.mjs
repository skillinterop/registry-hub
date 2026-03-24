// read-resource.mjs — read a JSON/JSON-LD resource from a URL or local path
// Resolves relative URLs found inside the document relative to the source location.

import { readFile } from 'fs/promises';
import { resolve, dirname } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

/**
 * Load and parse a JSON resource from a URL or local path.
 *
 * @param {string} source - http(s) URL or absolute/relative local path
 * @returns {Promise<{ data: object, sourceDir: string|null }>}
 *   data       — parsed JSON object
 *   sourceDir  — directory of the source file (for resolving relative refs),
 *                null for remote URLs
 */
export async function readResource(source) {
  if (/^https?:\/\//i.test(source)) {
    const res = await fetch(source);
    if (!res.ok) {
      throw new Error(`Failed to fetch ${source}: ${res.status} ${res.statusText}`);
    }
    const data = await res.json();
    return { data, sourceDir: null };
  }

  // Local path
  const absolutePath = resolve(source);
  const raw = await readFile(absolutePath, 'utf8');
  let data;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    throw new Error(`Failed to parse JSON at ${absolutePath}: ${err.message}`);
  }
  return { data, sourceDir: dirname(absolutePath) };
}

/**
 * Resolve a relative contentUrl or artifactUrl to an absolute path or URL,
 * given the directory of the parent document.
 *
 * If the ref is already an absolute URL, return it unchanged.
 * If sourceDir is null (remote parent), return the ref unchanged.
 *
 * @param {string} ref       - the relative or absolute URL/path from the document
 * @param {string|null} sourceDir - directory of the containing document
 * @returns {string}
 */
export function resolveRef(ref, sourceDir) {
  if (/^https?:\/\//i.test(ref)) {
    return ref;
  }
  if (!sourceDir) {
    return ref;
  }
  return resolve(sourceDir, ref);
}
