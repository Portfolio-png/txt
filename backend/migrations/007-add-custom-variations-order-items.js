exports.up = async (db) => {
    const run = (sql) => new Promise((resolve, reject) => db.run(sql, err => {
        if (err && err.message.includes('duplicate column name')) return resolve();
        if (err) return reject(err);
        resolve();
    }));

    await run("ALTER TABLE order_items ADD COLUMN custom_variation_values_json TEXT DEFAULT '{}'");
};

exports.down = async (db) => {
};
