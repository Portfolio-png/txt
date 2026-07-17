const fs = require('fs');

const itemsData = [
  {
    itemName: 'Switch Action Dolly',
    props: [
      { name: 'Action Dolly Amp', value: '5 Amp', code: '5A' },
      { name: 'Action Patti Number', value: '11', code: '11' },
      { name: 'Action Dabbi Number', value: '1', code: '1' },
      { name: 'Action Dolly Alloy', value: 'Brass', code: 'BR' },
      { name: 'Action Dolly Contact', value: '1 Way', code: '1W' },
      { name: 'Action Dolly Type', value: 'Dolly', code: 'AD' },
      { name: 'Action Dolly Rivet Type', value: 'Copper Rivet', code: 'CR' },
      { name: 'Action Dolly Plating', value: 'Without Plating', code: 'WP' }
    ]
  },
  {
    itemName: 'Switch Action Rocker',
    props: [
      { name: 'Action Rocker Amp', value: '5 Amp', code: '5A' },
      { name: 'Action Rocker Name', value: 'Modular', code: 'MOD' },
      { name: 'Action Rocker Alloy', value: 'Brass', code: 'BR' },
      { name: 'Action Rocker Contact', value: '1 Way Zula', code: '1W' },
      { name: 'Action Rocker Rivet Type', value: 'Copper Rivet', code: 'CR' },
      { name: 'Action Rocker Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Socket',
    props: [
      { name: 'Socket Amp', value: '10 Amp', code: '10A' },
      { name: 'Socket Name', value: 'Modular', code: 'MOD' },
      { name: 'Socket Alloy', value: 'Brass', code: 'BR' },
      { name: 'Socket Type', value: 'Socket Face', code: 'SF' },
      { name: 'Socket Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Cutout',
    props: [
      { name: 'Cutout Amp', value: '63 Amp', code: '63A' },
      { name: 'Cutout Alloy', value: 'Brass', code: 'BR' },
      { name: 'Cutout Type', value: 'Cutout U Part', code: 'CU' },
      { name: 'Cutout Plating', value: 'Nickel', code: 'NK' }
    ]
  },
  {
    itemName: 'Coutout Kitkat',
    props: [
      { name: 'Kitkat Name', value: 'Roma Kitkat', code: 'ROMA' },
      { name: 'Kitkat Alloy', value: 'Brass', code: 'BR' },
      { name: 'Kitkat Type', value: 'Base Part', code: 'CKB' },
      { name: 'Kitkat Plating', value: 'Nickel', code: 'NK' }
    ]
  },
  {
    itemName: 'Multiplug',
    props: [
      { name: 'Multiplug Amp', value: '5 Amp', code: '5A' },
      { name: 'Multiplug Name', value: 'New Multiplug', code: 'NEW' },
      { name: 'Multiplug Alloy', value: 'Brass', code: 'BR' },
      { name: 'Multiplug Type', value: 'Face Live', code: 'MPF' },
      { name: 'Multiplug Plating', value: 'Without Plating', code: 'WPL' }
    ]
  },
  {
    itemName: 'Double Pole Contact',
    props: [
      { name: 'DP Contact Size', value: '8.0 MM', code: '8MM' },
      { name: 'DP Contact Alloy', value: 'Copper', code: 'CP' },
      { name: 'DP Contact Type', value: 'Double Pole Big Contact', code: 'DPBC' },
      { name: 'DP Contact Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Double Pole Rocker',
    props: [
      { name: 'DP Rocker Amp', value: '15 Amp', code: '15A' },
      { name: 'DP Rocker Name', value: 'Penta Double Pole', code: 'PENTA' },
      { name: 'DP Rocker Alloy', value: 'Brass', code: 'BR' },
      { name: 'DP Rocker Type', value: '1 Way Zula', code: '1W' },
      { name: 'DP Rocker Rivet Type', value: 'Bimetal Rivet', code: 'BMR' },
      { name: 'DP Rocker Plating', value: 'Without Plating', code: 'WPL' }
    ]
  },
  {
    itemName: 'Double Pole Stand',
    props: [
      { name: 'DP Stand Amp', value: '15 Amp', code: '15A' },
      { name: 'DP Stand Name', value: 'Penta Double Pole', code: 'PENTA' },
      { name: 'DP Stand Alloy', value: 'Copper', code: 'CP' },
      { name: 'DP Stand Type', value: 'Stand', code: 'DPST' },
      { name: 'DP Stand Plating', value: 'Without Plating', code: 'WPL' }
    ]
  },
  {
    itemName: 'Double Pole Rivet Part',
    props: [
      { name: 'DP Rivet Part Amp', value: '15 Amp', code: '15A' },
      { name: 'DP Rivet Part Name', value: 'Nice', code: 'NICE' },
      { name: 'DP Rivet Part Alloy', value: 'Brass', code: 'BR' },
      { name: 'DP Rivet Part Type', value: 'Rivet Part', code: 'DPRP' },
      { name: 'DP Rivet Part', value: 'Bimetal Rivet', code: 'BMR' }
    ]
  },
  {
    itemName: 'Double Pole Fuse',
    props: [
      { name: 'DP Fuse Size', value: '8.0 MM', code: '8MM' },
      { name: 'DP Fuse Alloy', value: 'Brass', code: 'BR' },
      { name: 'DP Fuse Type', value: 'Double Pole Fuse Wire', code: 'DPF' },
      { name: 'DP Fuse Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Double Pole Dabbi',
    props: [
      { name: 'DP Dabbi No', value: '1 No', code: '1' },
      { name: 'DP Dabbi Alloy', value: 'Mild Steel', code: 'MS' },
      { name: 'DP Dabbi Type', value: 'Double Pole Dabbi', code: 'DPD' },
      { name: 'DP Dabbi Plating', value: 'Navrang', code: 'NV' }
    ]
  },
  {
    itemName: 'Double Pole Febric',
    props: [
      { name: 'DP Febric Name', value: 'GM', code: 'GM' },
      { name: 'DP Febric Type', value: 'Double Pole Febric', code: 'DPRF' }
    ]
  }
];

let itemsJS = itemsData.map(i => {
  return `{
    name: '${i.itemName}',
    displayName: '${i.itemName}',
    quantity: 100,
    groupId: primaryGroup.id,
    unitId: pieceUnit.id,
    variationTree: [
      ${i.props.map(p => `{
        kind: 'property',
        name: '${p.name}',
        children: [
          {
            kind: 'value',
            name: '${p.value}',
            code: '${p.code}'
          }
        ]
      }`).join(',\\n      ')}
    ]
  }`;
}).join(',\\n    ');

const ensureDemoItemsPresentCode = `async function ensureDemoItemsPresent() {
  const groups = await getGroupsWithUsage();
  const units = await getUnitsWithUsage();
  const groupByName = new Map(
    groups.map((group) => [normalizeUnitValue(group.name), group]),
  );
  const unitBySymbol = new Map(
    units.map((unit) => [normalizeUnitValue(unit.symbol), unit]),
  );

  const primaryGroup = groupByName.get('primary group') || groups[0];
  const pieceUnit = unitBySymbol.get('pc') || units[0];

  if (!primaryGroup || !pieceUnit) {
    return;
  }

  const itemSeeds = [
    ${itemsJS}
  ];

  for (const seed of itemSeeds) {
    await ensureItemRecord(seed);
  }
}`;

const ensureDemoGroupsPresentCode = `async function ensureDemoGroupsPresent() {
  const units = await getUnitsWithUsage();
  const bySymbol = new Map(
    units.map((unit) => [normalizeUnitValue(unit.symbol), unit]),
  );
  const pieceUnit = bySymbol.get('pc') || units[0];
  
  await ensureGroupRecord({
    name: 'Primary Group',
    unitId: pieceUnit.id,
  });
}`;

const ensureDemoUnitsPresentCode = `async function ensureDemoUnitsPresent() {
  const units = [
    {
      name: 'Piece',
      symbol: 'Pc',
      notes: 'Discrete finished goods and components.',
    },
    {
      name: 'Box',
      symbol: 'Box',
      notes: 'Packed kits and shipping cartons.',
    },
    {
      name: 'Carton',
      symbol: 'Ctn',
      notes: 'Shipping cartons.',
    }
  ];

  for (const unit of units) {
    await ensureUnitRecord(unit);
  }
}`;

const serverJsPath = 'server.js';
let code = fs.readFileSync(serverJsPath, 'utf8');

// Replace ensureDemoItemsPresent
code = code.replace(/async function ensureDemoItemsPresent\(\) \{[\s\S]*?(?=^async function buildItemDisplayName)/m, ensureDemoItemsPresentCode + '\n\n');

// Replace ensureDemoGroupsPresent
code = code.replace(/async function ensureDemoGroupsPresent\(\) \{[\s\S]*?(?=^function buildItemDisplayName)/m, ensureDemoGroupsPresentCode + '\n\n');

// Replace ensureDemoUnitsPresent
code = code.replace(/async function ensureDemoUnitsPresent\(\) \{[\s\S]*?(?=^async function backfillMaterialUnitIds)/m, ensureDemoUnitsPresentCode + '\n\n');

fs.writeFileSync(serverJsPath, code);
console.log('Replaced demo data functions successfully!');
