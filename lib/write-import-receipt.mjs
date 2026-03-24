// write-import-receipt.mjs — write an opt-in project-local import receipt
// Receipt location: <project-root>/.registry/imports/<registryType>--<name>.json
// Only written when the CLI is invoked with --save-receipt.
// Default import behavior writes no metadata.

import { createHash } from 'crypto';
import { readFile, mkdir, writeFile } from 'fs/promises';
import { join, resolve } from 'path';

/**
 * Compute the SHA-256 hex digest of a local file.
 *
 * @param {string} filePath - absolute path to the file
 * @returns {Promise<string>} hex digest
 */
async function sha256File(filePath) {
  const buf = await readFile(filePath);
  return createHash('sha256').update(buf).digest('hex');
}

/**
 * Write a project-local import receipt for the given item.
 *
 * @param {object} item        - hub-index item
 * @param {string} destination - absolute path where the artifact was written
 * @param {{ projectRoot?: string }} options
 * @returns {Promise<string>} absolute path to the written receipt file
 */
export async function writeImportReceipt(item, destination, options = {}) {
  const projectRoot = options.projectRoot ? resolve(options.projectRoot) : resolve(process.cwd());

  const receiptDir = join(projectRoot, '.registry', 'imports');
  await mkdir(receiptDir, { recursive: true });

  const receiptName = `${item.registryType}--${item.name}.json`;
  const receiptPath = join(receiptDir, receiptName);

  const sha256 = await sha256File(destination);

  const receipt = {
    canonicalId: item.canonicalId,
    registryType: item.registryType,
    name: item.name,
    version: item.version,
    sourceRepo: item.sourceRepo,
    sourceCatalog: item.sourceCatalog,
    artifactPath: item.artifactPath,
    artifactUrl: item.artifactUrl,
    destinationPath: destination,
    sha256,
    importedAt: new Date().toISOString(),
  };

  await writeFile(receiptPath, JSON.stringify(receipt, null, 2) + '\n', 'utf8');

  return receiptPath;
}
