import sqlite3
import datetime

conn = sqlite3.connect('backend/paper.db')
c = conn.cursor()

c.execute('SELECT id FROM groups WHERE name = "Scrap"')
if c.fetchone() is None:
    now = datetime.datetime.now().isoformat()
    c.execute("INSERT INTO groups (name, group_type, created_at, updated_at) VALUES ('Scrap', 'item', ?, ?)", (now, now))
    conn.commit()
    print('Scrap group inserted')
else:
    print('Scrap group already exists')

conn.close()
