#!/usr/bin/env node
// registry-hub-import — hub-driven import CLI for SkillInterop registry items
// Usage: registry-hub-import <command> <canonical-id> [options]

import { resolveImportItem } from '../lib/resolve-import-item.mjs';
import { resolveImportDestination } from '../lib/resolve-import-destination.mjs';
import { renderImportPreview } from '../lib/render-import-preview.mjs';
import { importArtifact } from '../lib/import-artifact.mjs';
import { writeImportReceipt } from '../lib/write-import-receipt.mjs';
import { createInterface } from 'readline';

const USAGE = `Usage: registry-hub-import <command> <canonical-id> [options]

Commands:
  preview <canonical-id>   Resolve and display import preview (no files written)
  import <canonical-id>    Resolve, confirm, and write the artifact to its destination
  help                     Show this help message

Options:
  --catalog <path-or-url>  Path or URL to registry-catalog.jsonld
                           (default: https://raw.githubusercontent.com/skillinterop/registry-hub/main/registry-catalog.jsonld)
  --runtime <runtime>      Target runtime for skill destination mapping (codex|claude-code)
  --project-root <path>    Project root directory for destination resolution
  --target-path <path>     Explicit destination path (required when runtime is unknown)
  --overwrite              Replace an existing destination file (default: abort)
  --yes                    Skip the confirmation prompt and proceed automatically
  --save-receipt           Write a project-local import receipt to <project-root>/.registry/imports/

State policy:
  No lockfile or import metadata is written by default in Phase 4.
  --save-receipt           Opt in to a hidden provenance file under .registry/imports/

Examples:
  registry-hub-import preview skill/org/[MASKED_EMAIL] --runtime codex
  registry-hub-import import skill/org/[MASKED_EMAIL] --runtime codex --yes
  registry-hub-import import cao-profile/org/[MASKED_EMAIL] --project-root "$PWD" --save-receipt --yes
  registry-hub-import preview skill/org/[MASKED_EMAIL] --target-path ./my-skills/workmux-router/SKILL.md
`;

function parseArgs(argv) {
  const args = {
    command: null,
    canonicalId: null,
    catalog: null,
    runtime: null,
    projectRoot: null,
    targetPath: null,
    overwrite: false,
    yes: false,
    saveReceipt: false,
  };

  const positional = [];
  let i = 0;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg === '--catalog') {
      args.catalog = argv[++i];
    } else if (arg === '--runtime') {
      args.runtime = argv[++i];
    } else if (arg === '--project-root') {
      args.projectRoot = argv[++i];
    } else if (arg === '--target-path') {
      args.targetPath = argv[++i];
    } else if (arg === '--overwrite') {
      args.overwrite = true;
    } else if (arg === '--yes' || arg === '-y') {
      args.yes = true;
    } else if (arg === '--save-receipt') {
      args.saveReceipt = true;
    } else {
      positional.push(arg);
    }
    i++;
  }

  if (positional.length > 0) {
    args.command = positional[0];
  }
  if (positional.length > 1) {
    args.canonicalId = positional[1];
  }

  return args;
}

/**
 * Prompt the user with a yes/no question and return true if they answer y/yes.
 */
async function promptConfirm(question) {
  return new Promise((resolve) => {
    const rl = createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    rl.question(question, (answer) => {
      rl.close();
      const normalized = answer.trim().toLowerCase();
      resolve(normalized === 'y' || normalized === 'yes');
    });
  });
}

async function main() {
  const argv = process.argv.slice(2);
  const args = parseArgs(argv);

  if (!args.command || args.command === 'help' || args.command === '--help' || args.command === '-h') {
    process.stdout.write(USAGE);
    process.exit(0);
  }

  if (args.command === 'preview') {
    if (!args.canonicalId) {
      process.stderr.write('Error: canonical-id is required\n');
      process.stderr.write('Usage: registry-hub-import preview <canonical-id>\n');
      process.exit(1);
    }

    let item;
    try {
      item = await resolveImportItem(args.canonicalId, { catalog: args.catalog });
    } catch (err) {
      process.stderr.write(`Error: ${err.message}\n`);
      process.exit(1);
    }

    let destination;
    try {
      destination = resolveImportDestination(item, {
        runtime: args.runtime,
        projectRoot: args.projectRoot,
        targetPath: args.targetPath,
      });
    } catch (err) {
      process.stderr.write(`Error: ${err.message}\n`);
      process.exit(1);
    }

    renderImportPreview(item, destination);
    process.exit(0);
  }

  if (args.command === 'import') {
    if (!args.canonicalId) {
      process.stderr.write('Error: canonical-id is required\n');
      process.stderr.write('Usage: registry-hub-import import <canonical-id>\n');
      process.exit(1);
    }

    // 1. Resolve item from catalog
    let item;
    try {
      item = await resolveImportItem(args.canonicalId, { catalog: args.catalog });
    } catch (err) {
      process.stderr.write(`Error: ${err.message}\n`);
      process.exit(1);
    }

    // 2. Resolve destination
    let destination;
    try {
      destination = resolveImportDestination(item, {
        runtime: args.runtime,
        projectRoot: args.projectRoot,
        targetPath: args.targetPath,
      });
    } catch (err) {
      process.stderr.write(`Error: ${err.message}\n`);
      process.exit(1);
    }

    // 3. Print preview before any write
    renderImportPreview(item, destination);
    process.stdout.write('\n');

    // 4. Confirmation prompt (skipped if --yes)
    if (!args.yes) {
      const confirmed = await promptConfirm('Proceed with import? [y/N] ');
      if (!confirmed) {
        process.stdout.write('Import aborted.\n');
        process.exit(0);
      }
    }

    // 5. Perform the actual artifact write
    try {
      await importArtifact(item, destination, { overwrite: args.overwrite });
    } catch (err) {
      process.stderr.write(`Error: ${err.message}\n`);
      process.exit(1);
    }

    process.stdout.write(`Imported: ${destination}\n`);

    // 6. Opt-in receipt persistence
    if (args.saveReceipt) {
      const projectRoot = args.projectRoot || process.cwd();
      try {
        const receiptPath = await writeImportReceipt(item, destination, { projectRoot });
        process.stdout.write(`Receipt: ${receiptPath}\n`);
      } catch (err) {
        process.stderr.write(`Warning: receipt write failed: ${err.message}\n`);
      }
    } else {
      process.stdout.write('Receipt: skipped (default)\n');
    }

    process.exit(0);
  }

  process.stderr.write(`Error: unknown command '${args.command}'\n`);
  process.stderr.write('Usage: registry-hub-import <command> <canonical-id>\n');
  process.exit(1);
}

main().catch((err) => {
  process.stderr.write(`Unexpected error: ${err.message}\n`);
  process.exit(1);
});
