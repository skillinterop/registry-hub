#!/usr/bin/env node
// registry-hub-import — hub-driven import CLI for SkillInterop registry items
// Usage: registry-hub-import preview <canonical-id> [options]

import { resolveImportItem } from '../lib/resolve-import-item.mjs';
import { resolveImportDestination } from '../lib/resolve-import-destination.mjs';
import { renderImportPreview } from '../lib/render-import-preview.mjs';

const USAGE = `Usage: registry-hub-import preview <canonical-id> [options]

Commands:
  preview <canonical-id>   Resolve and display import preview (no files written)
  help                     Show this help message

Options:
  --catalog <path-or-url>  Path or URL to registry-catalog.jsonld
                           (default: https://raw.githubusercontent.com/skillinterop/registry-hub/main/registry-catalog.jsonld)
  --runtime <runtime>      Target runtime for skill destination mapping (codex|claude-code)
  --project-root <path>    Project root directory for destination resolution
  --target-path <path>     Explicit destination path (required when runtime is unknown)

Examples:
  registry-hub-import preview skill/org/workmux-router@1.0.0 --runtime codex
  registry-hub-import preview cao-profile/org/default-cao@0.1.0 --project-root "$PWD"
  registry-hub-import preview skill/org/workmux-router@1.0.0 --target-path ./my-skills/workmux-router/SKILL.md
`;

function parseArgs(argv) {
  const args = {
    command: null,
    canonicalId: null,
    catalog: null,
    runtime: null,
    projectRoot: null,
    targetPath: null,
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

  process.stderr.write(`Error: unknown command '${args.command}'\n`);
  process.stderr.write('Usage: registry-hub-import preview <canonical-id>\n');
  process.exit(1);
}

main().catch((err) => {
  process.stderr.write(`Unexpected error: ${err.message}\n`);
  process.exit(1);
});
