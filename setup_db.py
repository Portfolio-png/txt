import sqlite3, json
conn = sqlite3.connect('backend/database.sqlite')
cursor = conn.cursor()
cursor.execute('SELECT config FROM sandbox_clients WHERE client_id=''test''')
row = cursor.fetchone()
config = json.loads(row[0]) if row and row[0] else {}
config['update'] = {'latest_version': '2.0.0', 'channel': 'stable', 'appcast_url': 'http://localhost:8000/paper_update.exe'}
cursor.execute('UPDATE sandbox_clients SET config=? WHERE client_id=''test''', (json.dumps(config),))
conn.commit()
print('done')
