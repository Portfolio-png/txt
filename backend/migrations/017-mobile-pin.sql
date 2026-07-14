ALTER TABLE users ADD COLUMN mobile_pin TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_mobile_pin ON users(mobile_pin);
