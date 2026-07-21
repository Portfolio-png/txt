-- Date of birth for employees. Used to derive a staff member's simple 4-digit
-- login code (DDMM — day+month of their DOB). Stored as ISO 'YYYY-MM-DD'.
ALTER TABLE employees ADD COLUMN date_of_birth TEXT DEFAULT '';
