exports.up = async (db) => {
  const exec = (sql) => new Promise((resolve, reject) => db.exec(sql, err => err ? reject(err) : resolve()));
  const run = (sql) => new Promise((resolve, reject) => db.run(sql, err => {
    // Ignore duplicate column errors
    if (err && err.message.includes('duplicate column name')) return resolve();
    if (err && err.message.includes('no such table')) return resolve(); // ignore missing tables like 'orders'
    if (err) return reject(err);
    resolve();
  }));

  // Payroll Additions to employees
  await run("ALTER TABLE employees ADD COLUMN bank_account_number TEXT DEFAULT ''");
  await run("ALTER TABLE employees ADD COLUMN ifsc_code TEXT DEFAULT ''");
  await run("ALTER TABLE employees ADD COLUMN uan_number TEXT DEFAULT ''");
  await run("ALTER TABLE employees ADD COLUMN esi_number TEXT DEFAULT ''");
  await run("ALTER TABLE employees ADD COLUMN tax_regime TEXT DEFAULT 'new'");
  
  await exec(`
    CREATE TABLE IF NOT EXISTS payroll_components (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER REFERENCES clients(id),
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        calculation_method TEXT NOT NULL,
        is_statutory INTEGER NOT NULL DEFAULT 0,
        config_json TEXT NOT NULL DEFAULT '{}'
    );

    CREATE TABLE IF NOT EXISTS employee_salary_structures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        effective_from TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS employee_salary_structure_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        structure_id INTEGER NOT NULL REFERENCES employee_salary_structures(id) ON DELETE CASCADE,
        component_id INTEGER NOT NULL REFERENCES payroll_components(id) ON DELETE CASCADE,
        amount_or_formula TEXT NOT NULL,
        sequence INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS attendance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        in_time TEXT,
        out_time TEXT,
        hours_worked REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'present'
    );

    CREATE TABLE IF NOT EXISTS leave_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER REFERENCES clients(id),
        name TEXT NOT NULL,
        paid INTEGER NOT NULL DEFAULT 1,
        accrual_rule TEXT NOT NULL DEFAULT ''
    );

    CREATE TABLE IF NOT EXISTS leave_balances (
        employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        leave_type_id INTEGER NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,
        opening REAL NOT NULL DEFAULT 0,
        credited REAL NOT NULL DEFAULT 0,
        availed REAL NOT NULL DEFAULT 0,
        closing REAL NOT NULL DEFAULT 0,
        PRIMARY KEY(employee_id, leave_type_id)
    );

    CREATE TABLE IF NOT EXISTS payroll_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER REFERENCES clients(id),
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        processed_at TEXT,
        total_gross REAL NOT NULL DEFAULT 0,
        total_deduction REAL NOT NULL DEFAULT 0,
        total_net REAL NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS payroll_run_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id INTEGER NOT NULL REFERENCES payroll_runs(id) ON DELETE CASCADE,
        employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        component_id INTEGER REFERENCES payroll_components(id),
        amount REAL NOT NULL DEFAULT 0,
        is_deduction INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS payslips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id INTEGER NOT NULL REFERENCES payroll_runs(id) ON DELETE CASCADE,
        employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        pdf_path TEXT DEFAULT '',
        emailed_at TEXT
    );

    CREATE TABLE IF NOT EXISTS statutory_config (
        client_id INTEGER PRIMARY KEY REFERENCES clients(id) ON DELETE CASCADE,
        pf_wage_ceiling REAL NOT NULL DEFAULT 15000,
        pf_employee_rate REAL NOT NULL DEFAULT 12.0,
        pf_employer_rate REAL NOT NULL DEFAULT 12.0,
        esi_eligible_threshold REAL NOT NULL DEFAULT 21000,
        esi_employee_rate REAL NOT NULL DEFAULT 0.75,
        esi_employer_rate REAL NOT NULL DEFAULT 3.25,
        pt_slabs_json TEXT NOT NULL DEFAULT '[]',
        tds_config_json TEXT NOT NULL DEFAULT '{}'
    );

    CREATE TABLE IF NOT EXISTS portal_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        last_login TEXT
    );

    CREATE TABLE IF NOT EXISTS portal_invites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
        token TEXT NOT NULL UNIQUE,
        expires_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS portal_carts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        portal_user_id INTEGER NOT NULL REFERENCES portal_users(id) ON DELETE CASCADE,
        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS portal_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        sender_type TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
  `);

  await run("ALTER TABLE orders ADD COLUMN created_by_portal_user_id INTEGER REFERENCES portal_users(id)");
  await run("ALTER TABLE order_headers ADD COLUMN created_by_portal_user_id INTEGER REFERENCES portal_users(id)");
  await run("ALTER TABLE delivery_challans ADD COLUMN created_by_portal_user_id INTEGER REFERENCES portal_users(id)");
  await run("ALTER TABLE invoice_headers ADD COLUMN created_by_portal_user_id INTEGER REFERENCES portal_users(id)");
};
