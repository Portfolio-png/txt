const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const dbPath = path.join(__dirname, '..', 'paper.db');
const db = new sqlite3.Database(dbPath);

const run = (query, params = []) => new Promise((resolve, reject) => db.run(query, params, function(err) { if (err) reject(err); else resolve(this); }));
const get = (query, params = []) => new Promise((resolve, reject) => db.get(query, params, (err, row) => { if (err) reject(err); else resolve(row); }));

async function runTests() {
  console.log('--- Running Payroll API Tests ---');
  try {
    await run('BEGIN TRANSACTION');
    
    const now = new Date().toISOString();
    const compRes = await run('INSERT INTO payroll_components (name, type, calculation_method, is_statutory) VALUES (?, ?, ?, ?)', 
      ['Basic Pay', 'earning', 'fixed', 0]);
    
    const compId = compRes.lastID;
    console.log('SUCCESS: Created Payroll Component');

    const structRes = await run('INSERT INTO employee_salary_structures (employee_id, effective_from) VALUES (1, ?)', [now]);
    const structId = structRes.lastID;
    console.log('SUCCESS: Created Salary Structure');

    await run('INSERT INTO employee_salary_structure_lines (structure_id, component_id, amount_or_formula, sequence) VALUES (?, ?, ?, 1)', [structId, compId, '25000']);
    console.log('SUCCESS: Linked Component to Salary Structure');
    
    await run('ROLLBACK');
    console.log('--- Payroll Tests Passed ---\\n');
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    console.error('PAYROLL TESTS FAILED:', error);
    process.exit(1);
  }
}

runTests().then(() => db.close());
