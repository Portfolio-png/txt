'use strict';

// ---------------------------------------------------------------------------
// Items module — ingress contracts.
//
// Declared from the CURRENT accepted payloads (saveItem/saveGroup signatures
// and sanitizeNodes), warts included — the contract documents what the border
// accepts today, not an aspiration. Live in LOG-ONLY mode behind the existing
// routes: mismatches file guard alerts (entity_type 'kernel_guard' in
// entity_activity_log), nothing is rejected yet. Tightening (openFields:
// false, enforcement) happens with the items evacuation.
//
// The single most important rule in here: variation node ids must be POSITIVE
// when present. Synthetic negative ids (-propertyId, minted by the client
// selector for typed Gauge/Numeric values) must never persist — that class of
// bug produced the 2026-07-27 "invalid variation leaf" challan failures.
// ---------------------------------------------------------------------------

const variationNode = {
  type: 'object',
  openFields: true,
  fields: {
    id: { type: 'integer', nullable: true, min: 1 },
    kind: { type: 'string', required: true, enum: ['property', 'value'] },
    name: { type: 'string', required: true, nonEmpty: true },
    code: { type: 'string' },
    displayName: { type: 'string' },
    inputType: { type: 'string', enum: ['Text', 'Numeric', 'Gauge'] },
    nameJoin: { type: 'string' },
    position: { type: 'integer', min: 0 },
    children: { type: 'array', items: () => variationNode },
  },
};

const itemWrite = {
  entity: 'item',
  openFields: true,
  fields: {
    id: { type: 'integer', nullable: true, min: 1 },
    name: { type: 'string', required: true, nonEmpty: true },
    alias: { type: 'string' },
    displayName: { type: 'string' },
    quantity: { type: 'number', min: 0 },
    groupId: { type: 'integer', required: true, min: 1 },
    unitId: { type: 'integer', required: true, min: 1 },
    unitConversions: {
      type: 'array',
      items: {
        type: 'object',
        openFields: true,
        fields: {
          unitId: { type: 'integer', required: true, min: 1 },
          factorToPrimary: { type: 'number', required: true, gt: 0 },
        },
      },
    },
    namingFormat: { type: 'array' },
    variationTree: { type: 'array', items: variationNode },
    defaultPipelineId: { type: 'string', nullable: true },
    baseItemId: { type: 'integer', nullable: true, min: 1 },
    photoUrl: { type: 'string', nullable: true },
    availableForPurchase: { type: 'boolean', nullable: true },
  },
};

const groupWrite = {
  entity: 'group',
  openFields: true,
  fields: {
    id: { type: 'integer', nullable: true, min: 1 },
    name: { type: 'string', required: true, nonEmpty: true },
    parentGroupId: { type: 'integer', nullable: true, min: 1 },
    unitId: { type: 'integer', nullable: true, min: 1 },
    groupType: { type: 'string' },
    groupStructure: { type: 'string' },
    description: { type: 'string' },
  },
};

// Egress projections — the DTO fields the border exposes (declared from
// rowToItemDto / rowToGroupDto). Documentation-first: enforcement (stripping
// undeclared fields) flips together with ingress enforcement at evacuation.
const itemEgress = {
  entity: 'item',
  fields: [
    'id', 'name', 'alias', 'shortCode', 'displayName', 'quantity',
    'groupId', 'unitId', 'unitConversions', 'namingFormat', 'isArchived',
    'usageCount', 'createdAt', 'updatedAt', 'variationTree', 'propertySchema',
    'baseItemId', 'combinationGroupIds', 'photoUrl', 'availableForPurchase',
  ],
};

const groupEgress = {
  entity: 'group',
  fields: [
    'id', 'name', 'groupType', 'groupStructure', 'description',
    'parentGroupId', 'unitId', 'isArchived', 'usageCount',
    'createdAt', 'updatedAt',
  ],
};

module.exports = { itemWrite, groupWrite, variationNode, itemEgress, groupEgress };
