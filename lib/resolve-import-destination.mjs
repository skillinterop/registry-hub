// resolve-import-destination.mjs — compute the destination path for an imported artifact
// Phase 4 destination policy (locked decisions D-06 through D-10):
//   skill + --runtime codex        -> $HOME/.codex/skills/<name>/SKILL.md
//   skill + --runtime claude-code  -> $HOME/.claude/skills/<name>/SKILL.md
//   skill + unknown/missing runtime -> require --target-path
//   cao-profile                    -> <project-root>/.registry/profiles/<name>/PROFILE.md
//   reprogate                      -> fail fast (deferred for Phase 4)

import { resolve } from 'path';
import { homedir } from 'os';

const SUPPORTED_RUNTIMES = ['codex', 'claude-code'];

/**
 * Compute the destination path for an imported hub-index item.
 *
 * @param {object} item - hub-index item with registryType, name, artifactPath
 * @param {{ runtime?: string, projectRoot?: string, targetPath?: string }} options
 * @returns {string} absolute destination path
 */
export function resolveImportDestination(item, options = {}) {
  const { runtime, projectRoot, targetPath } = options;
  const { registryType, name } = item;

  // Explicit target path always wins (any registry type)
  if (targetPath) {
    return resolve(targetPath);
  }

  switch (registryType) {
    case 'skill': {
      if (runtime === 'codex') {
        return resolve(homedir(), '.codex', 'skills', name, 'SKILL.md');
      }
      if (runtime === 'claude-code') {
        return resolve(homedir(), '.claude', 'skills', name, 'SKILL.md');
      }
      // Unknown or missing runtime — require --target-path
      throw new Error(
        `Unknown runtime${runtime ? ` '${runtime}'` : ''}; provide --target-path or --runtime (codex|claude-code)`
      );
    }

    case 'cao-profile': {
      const root = projectRoot ? resolve(projectRoot) : resolve(process.cwd());
      return resolve(root, '.registry', 'profiles', name, 'PROFILE.md');
    }

    case 'reprogate': {
      throw new Error('reprogate imports are deferred for Phase 4');
    }

    default: {
      throw new Error(`Unsupported registry type: ${registryType}`);
    }
  }
}
