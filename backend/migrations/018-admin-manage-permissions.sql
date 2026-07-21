-- Grant the built-in `admin` role the users.manage_permissions capability so an
-- admin can scope/assign permissions to the staff (`user`) accounts they create.
-- Pairs with DEFAULT_ROLE_PERMISSIONS.admin in server.js (used for fresh installs);
-- this one-time UPDATE brings already-provisioned databases in line. A super_admin
-- can still toggle this per-role afterward via the Users screen.
UPDATE role_permissions
SET is_allowed = 1, updated_at = datetime('now')
WHERE role = 'admin' AND permission_key = 'users.manage_permissions';
