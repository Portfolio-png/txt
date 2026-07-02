// Finishes the HR schema from 005: a label on payroll_run_details (so statutory
// lines with no component_id still print a name), a leave_requests table
// (apply -> approve -> adjust balance), and a default company statutory_config.
exports.up = async (db) => {
  const exec = (sql) => new Promise((resolve, reject) => db.exec(sql, err => err ? reject(err) : resolve()));
  const run = (sql, params = []) => new Promise((resolve, reject) => db.run(sql, params, err => {
    if (err && err.message.includes('duplicate column name')) return resolve();
    if (err) return reject(err);
    resolve();
  }));

  await run("ALTER TABLE payroll_run_details ADD COLUMN label TEXT DEFAULT ''");

  await exec(`
    CREATE TABLE IF NOT EXISTS leave_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        leave_type_id INTEGER NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,
        from_date TEXT NOT NULL,
        to_date TEXT NOT NULL,
        days REAL NOT NULL DEFAULT 0,
        reason TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        decided_at TEXT
    );
  `);

  // Company-wide statutory defaults (single tenant). Keyed client_id = 0.
  await run(`
    INSERT OR IGNORE INTO statutory_config
      (client_id, pf_wage_ceiling, pf_employee_rate, pf_employer_rate,
       esi_eligible_threshold, esi_employee_rate, esi_employer_rate,
       pt_slabs_json, tds_config_json)
    VALUES (0, 15000, 12.0, 12.0, 21000, 0.75, 3.25,
      '[{"upTo":7500,"amount":0},{"upTo":10000,"amount":175},{"upTo":null,"amount":200}]', '{}')
  `);
};
