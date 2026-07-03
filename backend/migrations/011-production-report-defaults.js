function tableInfo(db, table) {
  return new Promise((resolve, reject) => {
    db.all(`PRAGMA table_info(${table})`, (err, rows) => {
      if (err) return reject(err);
      resolve(rows || []);
    });
  });
}

function exec(db, sql) {
  return new Promise((resolve, reject) => {
    db.exec(sql, (err) => (err ? reject(err) : resolve()));
  });
}

async function addColumnIfMissing(db, table, column, definition) {
  const columns = await tableInfo(db, table);
  if (!columns.some((c) => c.name === column)) {
    await exec(db, `ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}

async function up(db) {
  await addColumnIfMissing(db, 'machines', 'report_output_per_hour', 'REAL');
  await addColumnIfMissing(db, 'machines', 'setup_minutes', 'REAL');
  await addColumnIfMissing(db, 'machines', 'labor_count', 'REAL');
  await addColumnIfMissing(db, 'machines', 'power_kw', 'REAL');
  await addColumnIfMissing(db, 'machines', 'report_notes', "TEXT NOT NULL DEFAULT ''");
  await addColumnIfMissing(db, 'dies', 'strokes_per_piece', 'REAL');
  await addColumnIfMissing(db, 'dies', 'setup_minutes', 'REAL');
  await addColumnIfMissing(db, 'dies', 'report_notes', "TEXT NOT NULL DEFAULT ''");
}

module.exports = { up };
