// Node-only I/O helpers for the CV engine: load replay fixtures and the acupoint
// dataset from the repo. Kept separate from engine.js so the engine stays pure and
// browser-safe (this file imports node: built-ins).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url)); // demo-app/cv
const REPO_ROOT = resolve(HERE, '..', '..');
export const FIXTURE_DIR = resolve(REPO_ROOT, 'claude-deliverables', 'fixtures');
export const POINTS_PATH = resolve(REPO_ROOT, 'claude-deliverables', 'data', 'acuguide_hand_points.json');

// The five replay fixtures, in scenario order.
export const FIXTURES = [
  'fixture_1_te3_correct_good_rhythm.json',
  'fixture_2_te3_wrong_position.json',
  'fixture_3_pc6_correct_too_fast.json',
  'fixture_4_no_hand_then_partial.json',
  'fixture_5_te3_full_flow.json',
];

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

// loadFixture(name) accepts a bare filename ("fixture_1_*.json") or an absolute path.
export function loadFixture(nameOrPath) {
  const path = nameOrPath.includes('/') || nameOrPath.includes('\\')
    ? nameOrPath
    : resolve(FIXTURE_DIR, nameOrPath);
  return readJson(path);
}

export function loadPointsData(path = POINTS_PATH) {
  return readJson(path);
}
