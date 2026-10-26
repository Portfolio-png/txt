-- Packing comes before Barcode.
--
-- Migration 052 seeded the nine stages with Barcode at 6 and Packing at 7. That
-- was a guess, and two independent artefacts disagree with it: the factory
-- sheet's own seeded ribbon and the test that pins it both read
-- ...Assembly, Packing, Barcode, Billing, Delivery. A label goes on a packed
-- box, so the box is packed first.
--
-- Corrected HERE rather than in 052 because 052 seeds with INSERT OR IGNORE on
-- `code` — editing it would fix only databases that have never booted, and
-- leave every existing one with the wrong order while the file claimed
-- otherwise. The master is the single place the order lives, so the master is
-- what gets fixed.
--
-- Addressed by code, not by id: ids depend on insert order, and this file runs
-- against databases that were seeded before it existed. Idempotent — running
-- it twice sets the same two numbers.

UPDATE process_stages SET position = 6 WHERE code = 'packing';
UPDATE process_stages SET position = 7 WHERE code = 'barcode';
