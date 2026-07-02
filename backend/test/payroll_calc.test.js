// Run: node backend/test/payroll_calc.test.js   (no framework; throws on failure)
const assert = require('assert');
const { computePayslip, computeStatutory } = require('../payroll_calc');

const statCfg = {
  pf_wage_ceiling: 15000, pf_employee_rate: 12.0,
  esi_eligible_threshold: 21000, esi_employee_rate: 0.75,
  pt_slabs_json: JSON.stringify([{ upTo: 7500, amount: 0 }, { upTo: 10000, amount: 175 }, { upTo: null, amount: 200 }]),
  tds_config_json: '{}',
};

// Basic 15000 + HRA 6000 = gross 21000, full attendance.
const lines = [
  { component_id: 1, name: 'Basic', type: 'earning', calculation_method: 'fixed', amount_or_formula: '15000' },
  { component_id: 2, name: 'HRA', type: 'earning', calculation_method: 'fixed', amount_or_formula: '6000' },
];
const s = computePayslip({ lines, statCfg, attendanceRatio: 1 });
assert.strictEqual(s.gross, 21000, 'gross');
// PF = 12% of min(15000,15000)=1800; ESI = 0.75% of 21000 (<=21000) = 157.5; PT slab = 200.
assert.strictEqual(s.deductions, 1800 + 157.5 + 200, 'deductions');
assert.strictEqual(s.net, 21000 - 2157.5, 'net');

// Attendance proration: half the month -> everything halves, ESI now applies (gross < ceiling), PF on halved basic.
const half = computePayslip({ lines, statCfg, attendanceRatio: 0.5 });
assert.strictEqual(half.gross, 10500, 'prorated gross');
assert.strictEqual(computeStatutory(7500, 10500, statCfg).pf, 900, 'PF on prorated basic');

// percent_of_basic: 40% of basic 15000 = 6000.
const pct = computePayslip({
  lines: [
    { component_id: 1, name: 'Basic', type: 'earning', calculation_method: 'fixed', amount_or_formula: '15000' },
    { component_id: 3, name: 'HRA', type: 'earning', calculation_method: 'percent_of_basic', amount_or_formula: '40' },
  ], statCfg, attendanceRatio: 1,
});
assert.strictEqual(pct.gross, 21000, 'percent_of_basic gross');

// No statutory config -> no statutory deductions.
const bare = computePayslip({ lines, statCfg: null, attendanceRatio: 1 });
assert.strictEqual(bare.deductions, 0, 'no statCfg => no deductions');
assert.strictEqual(bare.net, 21000, 'no statCfg => net==gross');

// Above ESI ceiling -> no ESI.
assert.strictEqual(computeStatutory(30000, 30000, statCfg).esi, 0, 'no ESI above ceiling');

console.log('payroll_calc: all assertions passed');
