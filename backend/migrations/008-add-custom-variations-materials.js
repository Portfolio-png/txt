module.exports = {
  up: async (db) => {
    // Add custom_variation_values_json to materials table
    await db.run(`
      ALTER TABLE materials
      ADD COLUMN custom_variation_values_json TEXT
    `);
  },
  down: async (db) => {
    // SQLite doesn't easily support dropping columns in older versions, but for recent versions:
    await db.run(`
      ALTER TABLE materials
      DROP COLUMN custom_variation_values_json
    `);
  }
};
