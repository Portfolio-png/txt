function exec(db, sql) {
  return new Promise((resolve, reject) => {
    db.exec(sql, (err) => (err ? reject(err) : resolve()));
  });
}

async function up(db) {
  // Drop the junction table if it exists. We ignore the item_variation_nodes columns
  // since SQLite does not support dropping columns easily before v3.35, and leaving
  // them dormant is perfectly safe.
  await exec(db, 'DROP TABLE IF EXISTS property_value_units');
}

module.exports = { up };
