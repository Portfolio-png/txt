const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('backend/paper.db');

db.serialize(() => {
  db.run("PRAGMA foreign_keys = ON;");
  
  db.run("BEGIN TRANSACTION");
  
  // Apply the same deletes as server.js
  const targetId = 6; // Or whichever we want to test
  
  db.run('DELETE FROM auth_sessions WHERE user_id = ?', [targetId]);
  db.run('DELETE FROM user_permission_overrides WHERE user_id = ?', [targetId]);
  db.run('DELETE FROM user_permission_templates WHERE user_id = ?', [targetId]);
  db.run('UPDATE auth_events SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
  db.run('UPDATE auth_events SET target_user_id = NULL WHERE target_user_id = ?', [targetId]);
  db.run('UPDATE global_audit_logs SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
  db.run('UPDATE delete_requests SET reviewed_by_user_id = NULL WHERE reviewed_by_user_id = ?', [targetId]);
  db.run('DELETE FROM delete_requests WHERE requested_by_user_id = ?', [targetId]);
  db.run('UPDATE users SET created_by_user_id = NULL WHERE created_by_user_id = ?', [targetId]);
  db.run('UPDATE procurement_requests SET created_by_user_id = NULL WHERE created_by_user_id = ?', [targetId]);
  db.run('UPDATE procurement_requests SET raised_by_user_id = NULL WHERE raised_by_user_id = ?', [targetId]);
  db.run('UPDATE procurement_requests SET cancelled_by_user_id = NULL WHERE cancelled_by_user_id = ?', [targetId]);
  db.run('UPDATE procurement_requests SET closed_by_user_id = NULL WHERE closed_by_user_id = ?', [targetId]);
  db.run('UPDATE procurement_activity_log SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
  db.run('UPDATE delivery_challans SET created_by = NULL WHERE created_by = ?', [targetId]);
  db.run('UPDATE delivery_challans SET updated_by = NULL WHERE updated_by = ?', [targetId]);
  db.run('DELETE FROM search_history WHERE user_id = ?', [targetId]);
  db.run('DELETE FROM search_clicks WHERE user_id = ?', [targetId]);
  
  db.run('DELETE FROM users WHERE id = ?', [targetId], function(err) {
    if (err) {
      console.error("Error deleting user:", err);
      db.run("ROLLBACK");
    } else {
      console.log("User deleted successfully!");
      db.run("ROLLBACK"); // rollback anyway so we don't destroy local data
    }
  });
});
