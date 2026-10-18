-- Migration 051: Units Contract Phase 2 — Families and Conversion Ladders
-- Implements the single source of truth for physical quantities per .claude/skills/units/SKILL.md

-- 1. Extend unit_groups: code, integral_only
ALTER TABLE unit_groups ADD COLUMN code TEXT;
ALTER TABLE unit_groups ADD COLUMN integral_only INTEGER NOT NULL DEFAULT 0;

-- 2. Extend units: factor_to_base, is_base, on_ladder, uqc
ALTER TABLE units ADD COLUMN factor_to_base INTEGER NOT NULL DEFAULT 1;
ALTER TABLE units ADD COLUMN is_base INTEGER NOT NULL DEFAULT 0;
ALTER TABLE units ADD COLUMN on_ladder INTEGER NOT NULL DEFAULT 1;
ALTER TABLE units ADD COLUMN uqc TEXT;

-- 3. Unique index on unit_groups code
CREATE UNIQUE INDEX IF NOT EXISTS idx_unit_groups_code ON unit_groups(code);

-- 4. Seed the 6 canonical families
INSERT OR IGNORE INTO unit_groups (name, dimension, code, integral_only, created_at, updated_at)
VALUES
  ('Count', 'count', 'count', 1, datetime('now'), datetime('now')),
  ('Mass', 'mass', 'mass', 0, datetime('now'), datetime('now')),
  ('Length', 'length', 'length', 0, datetime('now'), datetime('now')),
  ('Area', 'area', 'area', 0, datetime('now'), datetime('now')),
  ('Volume', 'volume', 'volume', 0, datetime('now'), datetime('now')),
  ('Time', 'time', 'time', 0, datetime('now'), datetime('now'));

UPDATE unit_groups SET code = 'count', dimension = 'count', integral_only = 1 WHERE LOWER(name) = 'count' AND (code IS NULL OR code = '');
UPDATE unit_groups SET code = 'mass', dimension = 'mass', integral_only = 0 WHERE LOWER(name) = 'mass' AND (code IS NULL OR code = '');
UPDATE unit_groups SET code = 'length', dimension = 'length', integral_only = 0 WHERE LOWER(name) = 'length' AND (code IS NULL OR code = '');
UPDATE unit_groups SET code = 'area', dimension = 'area', integral_only = 0 WHERE LOWER(name) = 'area' AND (code IS NULL OR code = '');
UPDATE unit_groups SET code = 'volume', dimension = 'volume', integral_only = 0 WHERE LOWER(name) = 'volume' AND (code IS NULL OR code = '');
UPDATE unit_groups SET code = 'time', dimension = 'time', integral_only = 0 WHERE LOWER(name) = 'time' AND (code IS NULL OR code = '');
