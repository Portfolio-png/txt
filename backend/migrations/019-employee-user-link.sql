-- Unified "People": link an in-house employee (HR master) to a login/profile
-- account in `users`. `user_id` is the connection (NULL = no login, e.g. every
-- freelancer and any in-house employee not yet given access). `email` lets an
-- employee carry the address their login is created with. The link is enforced
-- in application code (SQLite ALTER cannot always add an inline FK).
ALTER TABLE employees ADD COLUMN user_id INTEGER;
ALTER TABLE employees ADD COLUMN email TEXT DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_employees_user_id ON employees(user_id);
