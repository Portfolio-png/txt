'use strict';

// ---------------------------------------------------------------------------
// Kernel contract engine (kernel rule K4: payload shape is the target
// module's border question).
//
// A contract declares an entity's ingress shape once; checkPayload() reports
// structural problems without mutating or rejecting anything — enforcement
// mode is the caller's choice (log-only during evacuation, reject after).
//
// Field spec:
//   type:      'string' | 'number' | 'integer' | 'boolean' | 'array' |
//              'object' | 'any'
//   required:  value must be present (undefined is a problem)
//   nullable:  null is explicitly fine
//   nonEmpty:  strings must contain non-whitespace
//   enum:      allowed values (strings)
//   min/max:   numeric bounds (after coercion)
//   gt:        strictly-greater-than bound
//   items:     spec for array elements; pass a function for recursive shapes
//   fields:    nested object field specs
//   openFields: object tolerates undeclared keys (default true during the
//               log-only phase; tighten per-entity at evacuation)
//
// Checks are deliberately representation-tolerant: numbers may arrive as
// numeric strings (handlers Number() them), null on an optional field is not
// a problem. Guards exist to catch structural impossibilities — a negative
// node id, a missing owner reference, a factor of zero — not formatting.
// ---------------------------------------------------------------------------

const MAX_PROBLEMS = 25;

function coerceNumber(value) {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }
  return null;
}

function isBooleanish(value) {
  return (
    typeof value === 'boolean' ||
    value === 0 ||
    value === 1 ||
    value === 'true' ||
    value === 'false'
  );
}

function resolveSpec(spec) {
  return typeof spec === 'function' ? spec() : spec;
}

function checkValue(rawSpec, value, path, problems) {
  if (problems.length >= MAX_PROBLEMS) {
    return;
  }
  const spec = resolveSpec(rawSpec);
  if (value === undefined) {
    if (spec.required) {
      problems.push({ path, code: 'missing', message: `${path} is required` });
    }
    return;
  }
  if (value === null) {
    if (spec.required && !spec.nullable) {
      problems.push({ path, code: 'null', message: `${path} must not be null` });
    }
    return;
  }

  switch (spec.type) {
    case 'any':
      return;
    case 'string': {
      if (typeof value !== 'string') {
        problems.push({ path, code: 'not-a-string', message: `${path} must be a string` });
        return;
      }
      if (spec.nonEmpty && !value.trim()) {
        problems.push({ path, code: 'empty', message: `${path} must not be empty` });
      }
      if (spec.enum && !spec.enum.includes(value)) {
        problems.push({
          path,
          code: 'not-in-enum',
          message: `${path} must be one of ${spec.enum.join(', ')} (got '${value}')`,
        });
      }
      return;
    }
    case 'number':
    case 'integer': {
      const numeric = coerceNumber(value);
      if (numeric === null) {
        problems.push({ path, code: 'not-a-number', message: `${path} must be a number` });
        return;
      }
      if (spec.type === 'integer' && !Number.isInteger(numeric)) {
        problems.push({ path, code: 'not-an-integer', message: `${path} must be an integer` });
        return;
      }
      if (spec.min != null && numeric < spec.min) {
        problems.push({
          path,
          code: 'below-min',
          message: `${path} must be >= ${spec.min} (got ${numeric})`,
        });
      }
      if (spec.gt != null && numeric <= spec.gt) {
        problems.push({
          path,
          code: 'not-above',
          message: `${path} must be > ${spec.gt} (got ${numeric})`,
        });
      }
      if (spec.max != null && numeric > spec.max) {
        problems.push({
          path,
          code: 'above-max',
          message: `${path} must be <= ${spec.max} (got ${numeric})`,
        });
      }
      return;
    }
    case 'boolean': {
      if (!isBooleanish(value)) {
        problems.push({ path, code: 'not-a-boolean', message: `${path} must be a boolean` });
      }
      return;
    }
    case 'array': {
      if (!Array.isArray(value)) {
        problems.push({ path, code: 'not-an-array', message: `${path} must be an array` });
        return;
      }
      if (spec.items) {
        value.forEach((element, index) => {
          checkValue(spec.items, element, `${path}[${index}]`, problems);
        });
      }
      return;
    }
    case 'object': {
      if (typeof value !== 'object' || Array.isArray(value)) {
        problems.push({ path, code: 'not-an-object', message: `${path} must be an object` });
        return;
      }
      const fields = spec.fields || {};
      for (const [fieldName, fieldSpec] of Object.entries(fields)) {
        checkValue(fieldSpec, value[fieldName], `${path}.${fieldName}`, problems);
      }
      if (spec.openFields === false) {
        for (const key of Object.keys(value)) {
          if (!(key in fields)) {
            problems.push({
              path: `${path}.${key}`,
              code: 'unexpected-field',
              message: `${path}.${key} is not part of the contract`,
            });
          }
        }
      }
      return;
    }
    default:
      problems.push({
        path,
        code: 'unknown-spec-type',
        message: `${path}: contract declares unknown type '${spec.type}'`,
      });
  }
}

// Returns a (possibly empty) list of problems; never throws on payload data.
function checkPayload(contract, payload) {
  const problems = [];
  checkValue(
    {
      type: 'object',
      fields: contract.fields || {},
      openFields: contract.openFields !== false,
    },
    payload,
    contract.entity || 'payload',
    problems,
  );
  return problems;
}

module.exports = { checkPayload, MAX_PROBLEMS };
