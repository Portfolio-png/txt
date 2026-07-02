// Pure payroll math — no DB, no I/O, so it's unit-testable (see test/payroll_calc.test.js).
// India statutory model: PF, ESI, Professional Tax (slabs), flat TDS.
// server.js loads rows from the DB and hands them here.

const money = (n) => Math.round((Number(n) || 0) * 100) / 100;
const clamp01 = (n) => Math.max(0, Math.min(1, Number(n) || 0));

// A structure line joined with its component:
//   { component_id, name, type: 'earning'|'deduction', calculation_method: 'fixed'|'percent_of_basic',
//     is_statutory, amount_or_formula }
// 'fixed'            -> amount_or_formula is a rupee amount.
// 'percent_of_basic' -> amount_or_formula is a percent (e.g. "40" = 40% of basic).
function lineAmount(line, basic) {
  const v = Number(line.amount_or_formula) || 0;
  if (line.calculation_method === 'percent_of_basic') return money((v / 100) * basic);
  return money(v);
}

// PF/ESI/PT/TDS from a statutory_config row (rates stored as percentages, e.g. 12.0).
// statCfg may be null/undefined -> all statutory deductions are zero.
function computeStatutory(basicPaid, grossPaid, statCfg) {
  if (!statCfg) return { pf: 0, esi: 0, pt: 0, tds: 0 };

  const pfBase = Math.min(basicPaid, Number(statCfg.pf_wage_ceiling) || Infinity);
  const pf = money((Number(statCfg.pf_employee_rate) || 0) / 100 * pfBase);

  const esiThreshold = Number(statCfg.esi_eligible_threshold) || 0;
  const esi = grossPaid <= esiThreshold
    ? money((Number(statCfg.esi_employee_rate) || 0) / 100 * grossPaid)
    : 0;

  // pt_slabs_json: [{ upTo: 7500, amount: 0 }, { upTo: 10000, amount: 175 }, { upTo: null, amount: 200 }]
  // First slab whose upTo (null = no ceiling) covers grossPaid wins.
  let pt = 0;
  try {
    const slabs = JSON.parse(statCfg.pt_slabs_json || '[]');
    const hit = slabs.find((s) => s.upTo == null || grossPaid <= Number(s.upTo));
    if (hit) pt = money(hit.amount);
  } catch (_) { /* malformed config -> no PT */ }

  // tds_config_json: { "monthly": 1000 } (flat). Real slab-based TDS is a later upgrade.
  let tds = 0;
  try {
    const cfg = JSON.parse(statCfg.tds_config_json || '{}');
    tds = money(cfg.monthly || 0);
  } catch (_) { /* no TDS */ }

  return { pf, esi, pt, tds };
}

// Returns { gross, deductions, net, detailLines: [{ component_id, label, amount, is_deduction }] }.
// detailLines maps 1:1 to payroll_run_details rows. Statutory lines carry component_id = null.
function computePayslip({ lines = [], statCfg = null, attendanceRatio = 1 } = {}) {
  const ratio = clamp01(attendanceRatio);

  // 'basic' is the earning named "basic" (case-insensitive), else the first earning.
  const earnings = lines.filter((l) => l.type === 'earning');
  const basicLine = earnings.find((l) => String(l.name).toLowerCase() === 'basic') || earnings[0];
  const basicFull = basicLine ? lineAmount(basicLine, 0) : 0; // basic is never percent_of_itself

  const detailLines = [];

  // Earnings, prorated by attendance.
  let grossPaid = 0;
  let basicPaid = 0;
  for (const l of earnings) {
    const full = lineAmount(l, basicFull);
    const paid = money(full * ratio);
    grossPaid = money(grossPaid + paid);
    if (l === basicLine) basicPaid = paid;
    detailLines.push({ component_id: l.component_id, label: l.name, amount: paid, is_deduction: 0 });
  }

  // Statutory deductions on the paid amounts.
  const { pf, esi, pt, tds } = computeStatutory(basicPaid, grossPaid, statCfg);
  const statutory = [
    ['PF (Employee)', pf],
    ['ESI (Employee)', esi],
    ['Professional Tax', pt],
    ['TDS', tds],
  ];
  let deductions = 0;
  for (const [label, amount] of statutory) {
    if (amount > 0) {
      deductions = money(deductions + amount);
      detailLines.push({ component_id: null, label, amount, is_deduction: 1 });
    }
  }

  // Non-statutory deduction lines (loans, advances) — not prorated.
  for (const l of lines.filter((x) => x.type === 'deduction')) {
    const amount = lineAmount(l, basicFull);
    if (amount === 0) continue;
    deductions = money(deductions + amount);
    detailLines.push({ component_id: l.component_id, label: l.name, amount, is_deduction: 1 });
  }

  const net = money(grossPaid - deductions);
  return { gross: grossPaid, deductions, net, detailLines };
}

module.exports = { computePayslip, computeStatutory, lineAmount };
