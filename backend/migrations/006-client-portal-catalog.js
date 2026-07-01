exports.up = async (db) => {
    await db.exec(`
        CREATE TABLE IF NOT EXISTS client_portal_catalog (
            client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
            item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            PRIMARY KEY (client_id, item_id)
        );
    `);
};

exports.down = async (db) => {
    await db.exec(`DROP TABLE IF EXISTS client_portal_catalog;`);
};
