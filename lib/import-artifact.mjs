// import-artifact.mjs — copy or download a registry artifact to its destination
// Supports both http(s) URLs and local absolute paths (rewritten by read-resource).
// Conflict behavior: abort by default unless --overwrite is passed.
// Atomic write: write to a same-directory temp file, then rename into place.

import { createWriteStream, existsSync } from 'fs';
import { mkdir, rename, unlink, writeFile } from 'fs/promises';
import { readFile } from 'fs/promises';
import { dirname, basename, join } from 'path';
import { tmpdir } from 'os';
import { randomBytes } from 'crypto';

/**
 * Import an artifact from its resolved source URL or local path to the destination.
 *
 * @param {object} item        - hub-index item (provides artifactUrl, name, etc.)
 * @param {string} destination - absolute destination path
 * @param {{ overwrite?: boolean }} options
 * @returns {Promise<void>}
 * @throws if destination exists and overwrite is not set, or on I/O error
 */
export async function importArtifact(item, destination, options = {}) {
  const { overwrite = false } = options;

  // 1. Overwrite guard — check before any network or disk I/O
  if (existsSync(destination) && !overwrite) {
    throw new Error(`Destination already exists: ${destination}`);
  }

  // 2. Ensure destination directory exists
  await mkdir(dirname(destination), { recursive: true });

  // 3. Determine source — item.artifactUrl is canonical
  const source = item.artifactUrl;
  if (!source) {
    throw new Error(`Item has no artifactUrl: ${item.canonicalId}`);
  }

  // 4. Write to a same-directory temp file, then rename atomically
  const destDir = dirname(destination);
  const suffix = randomBytes(6).toString('hex');
  const tmpFile = join(destDir, `.tmp-import-${suffix}-${basename(destination)}`);

  try {
    if (/^https?:\/\//i.test(source)) {
      // Remote URL — stream into temp file
      await downloadToFile(source, tmpFile);
    } else {
      // Local absolute path (rewritten by resolveRef/read-resource)
      const content = await readFile(source);
      await writeFile(tmpFile, content);
    }

    // Rename temp file into destination (atomic on POSIX)
    await rename(tmpFile, destination);
  } catch (err) {
    // Clean up temp file on failure, ignore cleanup errors
    await unlink(tmpFile).catch(() => {});
    throw err;
  }
}

/**
 * Download a remote URL to a local file path using Node.js fetch + streaming.
 *
 * @param {string} url      - http(s) URL
 * @param {string} filePath - destination file path (must exist's dir)
 */
async function downloadToFile(url, filePath) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Failed to download ${url}: ${res.status} ${res.statusText}`);
  }

  // Collect response body as Buffer
  const arrayBuffer = await res.arrayBuffer();
  await writeFile(filePath, Buffer.from(arrayBuffer));
}
