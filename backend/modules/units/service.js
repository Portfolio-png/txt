/**
 * Units Engine & Standard Conversion Ladders (Phase 2)
 *
 * Single source of truth for physical quantities per .claude/skills/units/SKILL.md
 * Invariant I1: No floats in the quantity path. Base units are integers.
 * Invariant I2: Units are data, not code.
 * Invariant I4: Arithmetic only within a family.
 * Invariant I6: Never silently round input.
 */

class UnitParseError extends Error {
  constructor(message) {
    super(message);
    this.name = 'UnitParseError';
    this.statusCode = 400;
  }
}

const STANDARD_FAMILIES = [
  {
    code: 'count',
    name: 'Count',
    dimension: 'count',
    integralOnly: 1,
    base: {
      name: 'Piece',
      symbol: 'Pc',
      factorToBase: 1,
      isBase: 1,
      onLadder: 1,
      uqc: 'NOS',
      notes: 'Discrete finished goods and components.',
    },
    ladder: [
      {
        name: 'Dozen',
        symbol: 'doz',
        factorToBase: 12,
        isBase: 0,
        onLadder: 1,
        uqc: 'DOZ',
        notes: '12 pieces.',
      },
      {
        name: 'Gross',
        symbol: 'gro',
        factorToBase: 144,
        isBase: 0,
        onLadder: 1,
        uqc: 'GRS',
        notes: '144 pieces (12 dozen).',
      },
    ],
  },
  {
    code: 'mass',
    name: 'Mass',
    dimension: 'mass',
    integralOnly: 0,
    base: {
      name: 'Milligram',
      symbol: 'mg',
      factorToBase: 1,
      isBase: 1,
      onLadder: 0,
      uqc: 'MGM',
      notes: 'Base unit for weight (milligram).',
    },
    ladder: [
      {
        name: 'Gram',
        symbol: 'g',
        factorToBase: 1000,
        isBase: 0,
        onLadder: 1,
        uqc: 'GMS',
        notes: 'Small weight measurement.',
      },
      {
        name: 'Kilogram',
        symbol: 'kg',
        factorToBase: 1000000,
        isBase: 0,
        onLadder: 1,
        uqc: 'KGS',
        notes: 'Standard metric weight (1,000 g).',
      },
      {
        name: 'Quintal',
        symbol: 'qtl',
        factorToBase: 100000000,
        isBase: 0,
        onLadder: 1,
        uqc: 'QTL',
        notes: 'Commercial weight (100 kg).',
      },
      {
        name: 'Tonne',
        symbol: 't',
        factorToBase: 1000000000,
        isBase: 0,
        onLadder: 1,
        uqc: 'TON',
        notes: 'Metric ton (1,000 kg).',
      },
    ],
  },
  {
    code: 'length',
    name: 'Length',
    dimension: 'length',
    integralOnly: 0,
    base: {
      name: 'Micrometer',
      symbol: 'µm',
      factorToBase: 1,
      isBase: 1,
      onLadder: 0,
      uqc: null,
      notes: 'Base unit for length (micron).',
    },
    ladder: [
      {
        name: 'Millimeter',
        symbol: 'mm',
        factorToBase: 1000,
        isBase: 0,
        onLadder: 1,
        uqc: 'MML',
        notes: 'Sheet and strip dimensions (1,000 µm).',
      },
      {
        name: 'Centimeter',
        symbol: 'cm',
        factorToBase: 10000,
        isBase: 0,
        onLadder: 1,
        uqc: 'CMS',
        notes: 'Metric centimeter (10 mm).',
      },
      {
        name: 'Meter',
        symbol: 'm',
        factorToBase: 1000000,
        isBase: 0,
        onLadder: 1,
        uqc: 'MTR',
        notes: 'Standard metric length (1,000 mm).',
      },
      {
        name: 'Inch',
        symbol: 'in',
        factorToBase: 25400,
        isBase: 0,
        onLadder: 1,
        uqc: 'INH',
        notes: 'Imperial inch (25.4 mm).',
      },
      {
        name: 'Foot',
        symbol: 'ft',
        factorToBase: 304800,
        isBase: 0,
        onLadder: 1,
        uqc: 'FTS',
        notes: 'Imperial foot (12 inches).',
      },
    ],
  },
  {
    code: 'area',
    name: 'Area',
    dimension: 'area',
    integralOnly: 0,
    base: {
      name: 'Square Millimeter',
      symbol: 'mm²',
      factorToBase: 1,
      isBase: 1,
      onLadder: 0,
      uqc: null,
      notes: 'Base unit for area.',
    },
    ladder: [
      {
        name: 'Square Centimeter',
        symbol: 'cm²',
        factorToBase: 100,
        isBase: 0,
        onLadder: 1,
        uqc: null,
        notes: 'Square centimeter (100 mm²).',
      },
      {
        name: 'Square Meter',
        symbol: 'm²',
        factorToBase: 1000000,
        isBase: 0,
        onLadder: 1,
        uqc: 'SQM',
        notes: 'Standard square meter.',
      },
    ],
  },
  {
    code: 'volume',
    name: 'Volume',
    dimension: 'volume',
    integralOnly: 0,
    base: {
      name: 'Milliliter',
      symbol: 'mL',
      factorToBase: 1,
      isBase: 1,
      onLadder: 1,
      uqc: 'MLT',
      notes: 'Base unit for volume.',
    },
    ladder: [
      {
        name: 'Liter',
        symbol: 'L',
        factorToBase: 1000,
        isBase: 0,
        onLadder: 1,
        uqc: 'LTR',
        notes: 'Standard liter (1,000 mL).',
      },
    ],
  },
  {
    code: 'time',
    name: 'Time',
    dimension: 'time',
    integralOnly: 0,
    base: {
      name: 'Second',
      symbol: 's',
      factorToBase: 1,
      isBase: 1,
      onLadder: 1,
      uqc: 'SEC',
      notes: 'Base unit for time.',
    },
    ladder: [
      {
        name: 'Minute',
        symbol: 'min',
        factorToBase: 60,
        isBase: 0,
        onLadder: 1,
        uqc: 'MIN',
        notes: '60 seconds.',
      },
      {
        name: 'Hour',
        symbol: 'hr',
        factorToBase: 3600,
        isBase: 0,
        onLadder: 1,
        uqc: 'HRS',
        notes: '60 minutes (3,600 seconds).',
      },
    ],
  },
];

/**
 * Seeds or updates standard unit families and ladder rungs.
 * Safe to call repeatedly (idempotent).
 */
async function seedStandardUnitFamilies({ run, get, all }) {
  for (const family of STANDARD_FAMILIES) {
    let group = await get(
      'SELECT id, code, base_unit_id FROM unit_groups WHERE code = ? OR LOWER(name) = ?',
      [family.code, family.name.toLowerCase()],
    );

    if (!group) {
      const now = new Date().toISOString();
      const res = await run(
        `INSERT INTO unit_groups (name, dimension, code, integral_only, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [family.name, family.dimension, family.code, family.integralOnly, now, now],
      );
      group = { id: res.lastID, code: family.code, base_unit_id: null };
    } else {
      await run(
        `UPDATE unit_groups
         SET code = ?, dimension = ?, integral_only = ?
         WHERE id = ?`,
        [family.code, family.dimension, family.integralOnly, group.id],
      );
    }

    // Seed or link base unit
    let baseUnit = await get(
      'SELECT id, unit_group_id, factor_to_base FROM units WHERE unit_group_id = ? AND is_base = 1',
      [group.id],
    );

    if (!baseUnit) {
      // Find by symbol or name
      baseUnit = await get(
        'SELECT id, unit_group_id, factor_to_base FROM units WHERE LOWER(symbol) = ? OR LOWER(name) = ?',
        [family.base.symbol.toLowerCase(), family.base.name.toLowerCase()],
      );
    }

    const now = new Date().toISOString();
    if (!baseUnit) {
      const res = await run(
        `INSERT INTO units (
           name, symbol, unit_group_id, factor_to_base, is_base, on_ladder,
           uqc, conversion_factor, conversion_base_unit_id, notes, is_archived,
           created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
        [
          family.base.name,
          family.base.symbol,
          group.id,
          1,
          1,
          family.base.onLadder,
          family.base.uqc,
          1,
          null,
          family.base.notes,
          now,
          now,
        ],
      );
      baseUnit = { id: res.lastID };
    } else {
      await run(
        `UPDATE units
         SET unit_group_id = ?, factor_to_base = 1, is_base = 1, on_ladder = ?,
             uqc = COALESCE(uqc, ?), conversion_factor = 1, conversion_base_unit_id = NULL
         WHERE id = ?`,
        [group.id, family.base.onLadder, family.base.uqc, baseUnit.id],
      );
    }

    // Link group's base_unit_id
    await run('UPDATE unit_groups SET base_unit_id = ? WHERE id = ?', [baseUnit.id, group.id]);

    // Seed ladder units
    for (const rung of family.ladder) {
      let unit = await get(
        'SELECT id FROM units WHERE unit_group_id = ? AND LOWER(symbol) = ?',
        [group.id, rung.symbol.toLowerCase()],
      );
      if (!unit) {
        unit = await get(
          'SELECT id FROM units WHERE LOWER(symbol) = ? OR LOWER(name) = ?',
          [rung.symbol.toLowerCase(), rung.name.toLowerCase()],
        );
      }

      if (!unit) {
        await run(
          `INSERT INTO units (
             name, symbol, unit_group_id, factor_to_base, is_base, on_ladder,
             uqc, conversion_factor, conversion_base_unit_id, notes, is_archived,
             created_at, updated_at
           ) VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 0, ?, ?)`,
          [
            rung.name,
            rung.symbol,
            group.id,
            rung.factorToBase,
            rung.onLadder,
            rung.uqc,
            rung.factorToBase,
            baseUnit.id,
            rung.notes,
            now,
            now,
          ],
        );
      } else {
        await run(
          `UPDATE units
           SET unit_group_id = ?, factor_to_base = ?, is_base = 0, on_ladder = ?,
               uqc = COALESCE(uqc, ?), conversion_factor = ?, conversion_base_unit_id = ?
           WHERE id = ?`,
          [
            group.id,
            rung.factorToBase,
            rung.onLadder,
            rung.uqc,
            rung.factorToBase,
            baseUnit.id,
            unit.id,
          ],
        );
      }
    }
  }
}

/**
 * Parse user text in a chosen unit using exact integer/string arithmetic.
 * Never performs `parseFloat(text) * factor`.
 * Throws UnitParseError if the value is not a whole number of base units (SKILL.md §5, I6).
 *
 * @param {string} text - User input string (e.g. "1.25", "1.5")
 * @param {object} unit - Unit definition with factor_to_base, symbol, etc.
 * @param {object} [family] - Unit family definition with integral_only
 * @returns {number} Integer base quantity
 */
function parseQuantity(text, unit, family = null) {
  if (typeof text !== 'string') {
    text = String(text ?? '');
  }
  const clean = text.trim().replace(/,/g, '');
  if (!clean || !/^-?\d+(\.\d+)?$/.test(clean)) {
    throw new UnitParseError(`Invalid quantity format: "${text}"`);
  }

  const isNegative = clean.startsWith('-');
  const unsigned = isNegative ? clean.slice(1) : clean;
  const [wholeStr, fracStr = ''] = unsigned.split('.');

  const factor = BigInt(unit.factor_to_base || unit.factorToBase || 1);
  const d = fracStr.length;
  const denominator = 10n ** BigInt(d);
  const numerator = BigInt(wholeStr) * denominator + BigInt(fracStr || '0');

  const product = numerator * factor;
  if (product % denominator !== 0n) {
    throw new UnitParseError(
      `"${text} ${unit.symbol || unit.name || ''}" is not a whole number of base units`,
    );
  }

  const baseBig = product / denominator;
  const integralOnly = Boolean(
    family?.integral_only ||
    family?.integralOnly ||
    unit.unit_group_integral_only ||
    unit.integralOnly,
  );

  if (integralOnly && fracStr.length > 0) {
    // If family is integral_only, check that the whole resulting piece count was integer
    // which product % denominator already verifies.
  }

  const result = Number(isNegative ? -baseBig : baseBig);
  if (!Number.isSafeInteger(result)) {
    throw new UnitParseError(`Quantity exceeds safe integer range: "${text}"`);
  }
  return result;
}

/**
 * Auto-promotes or formats an integer base quantity per SKILL.md §5.
 *
 * @param {number} qtyBase - Integer base units
 * @param {object} unitOrFamily - Unit or Family definition with ladder
 * @param {object} [options]
 * @param {'auto'|'pinned'|'base'} [options.mode='auto']
 * @param {object} [options.pinnedUnit] - Unit when mode is 'pinned'
 * @returns {string} Formatted string, e.g. "1.25 kg", "999 g"
 */
function formatQuantity(qtyBase, unitOrFamily, options = {}) {
  const mode = options.mode || 'auto';
  let targetUnit = null;

  const isFamily = Boolean(unitOrFamily?.ladder || unitOrFamily?.units);
  const ladder = isFamily
    ? (unitOrFamily.ladder || unitOrFamily.units || [])
    : (unitOrFamily?.family?.ladder || [unitOrFamily]);

  if (mode === 'base') {
    targetUnit = isFamily
      ? (unitOrFamily.base || ladder[0])
      : (unitOrFamily.base || unitOrFamily);
  } else if (mode === 'pinned') {
    targetUnit = options.pinnedUnit || (!isFamily ? unitOrFamily : ladder[0]);
  } else {
    // Auto-promotion: pick largest unit u with |qtyBase| >= u.factor_to_base
    const absQty = Math.abs(qtyBase);
    const sortedLadder = [...ladder]
      .filter((u) => u.on_ladder !== 0 && u.onLadder !== false)
      .sort((a, b) => (b.factor_to_base || b.factorToBase || 1) - (a.factor_to_base || a.factorToBase || 1));

    // On an INTEGRAL-ONLY family the chosen unit must also divide exactly.
    // Count is integral-only and 228 pieces is 1.5833 gross, which is not a
    // quantity of anything: a third of a piece does not exist, so a screen
    // must never print one. 228 comes back "19 doz", and 229 — which no rung
    // above piece divides — comes back "229 Pc". The base always divides (its
    // factor is 1), so there is always an answer. Mirrors Units.format.
    const family = isFamily ? unitOrFamily : unitOrFamily?.family;
    const integralOnly = Number(family?.integral_only ?? family?.integralOnly ?? 0) === 1;

    targetUnit = sortedLadder.find((u) => {
      const f = u.factor_to_base || u.factorToBase || 1;
      if (absQty < f) return false;
      if (integralOnly && qtyBase % f !== 0) return false;
      return true;
    });
    if (!targetUnit) {
      // Pick smallest ladder unit
      targetUnit = sortedLadder[sortedLadder.length - 1] || unitOrFamily;
    }
  }

  const factor = Number(targetUnit.factor_to_base || targetUnit.factorToBase || 1);
  const symbol = targetUnit.symbol || targetUnit.name || '';
  const maxDecimals = targetUnit.max_decimals ?? targetUnit.precision ?? 4;

  const whole = Math.trunc(qtyBase / factor);
  const remainder = Math.abs(qtyBase % factor);

  if (remainder === 0) {
    return `${whole} ${symbol}`.trim();
  }

  // Exact fraction in decimal
  const frac = remainder / factor;
  let fracStr = frac.toFixed(maxDecimals);
  // Strip "0."
  fracStr = fracStr.slice(2).replace(/0+$/, '');

  const sign = qtyBase < 0 && whole === 0 ? '-' : '';
  if (!fracStr) {
    return `${sign}${whole} ${symbol}`.trim();
  }
  return `${sign}${whole}.${fracStr} ${symbol}`.trim();
}

/**
 * Converts integer base quantity from one unit to another within the same family.
 */
function convertQuantity(qtyBase, fromUnit, toUnit) {
  const fromGroup = fromUnit.unit_group_id || fromUnit.unitGroupId;
  const toGroup = toUnit.unit_group_id || toUnit.unitGroupId;
  if (fromGroup != null && toGroup != null && fromGroup !== toGroup) {
    const err = new Error(
      `Cannot convert across different unit families (${fromUnit.symbol || fromUnit.name} and ${toUnit.symbol || toUnit.name})`,
    );
    err.statusCode = 400;
    throw err;
  }
  return qtyBase;
}

module.exports = {
  UnitParseError,
  STANDARD_FAMILIES,
  seedStandardUnitFamilies,
  parseQuantity,
  formatQuantity,
  convertQuantity,
};
