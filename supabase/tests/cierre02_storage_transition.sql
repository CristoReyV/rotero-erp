\set ON_ERROR_STOP on
-- Own restored local database only. The Storage bucket itself is never changed.
BEGIN;
CREATE TEMP TABLE c02_storage_transition(versioning_status text NOT NULL
 CHECK(versioning_status IN('DISABLED','ENABLED','SUSPENDED')));
CREATE TRIGGER c02_test_storage_transition BEFORE UPDATE OF versioning_status ON c02_storage_transition
 FOR EACH ROW EXECUTE FUNCTION storage.enforce_versioning_status_transition();
INSERT INTO c02_storage_transition VALUES('DISABLED');
UPDATE c02_storage_transition SET versioning_status='DISABLED';
UPDATE c02_storage_transition SET versioning_status='ENABLED';
UPDATE c02_storage_transition SET versioning_status='SUSPENDED';
UPDATE c02_storage_transition SET versioning_status='ENABLED';
DO $$ BEGIN
 BEGIN
  UPDATE c02_storage_transition SET versioning_status='DISABLED';
  RAISE EXCEPTION 'c02_missing_transition_rejection';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'Cannot transition bucket versioning status from %' THEN RAISE;END IF;
 END;
 UPDATE c02_storage_transition SET versioning_status='SUSPENDED';
 -- A separate row represents a newly disabled bucket.
 INSERT INTO c02_storage_transition VALUES('DISABLED');
 BEGIN
  UPDATE c02_storage_transition SET versioning_status='SUSPENDED' WHERE versioning_status='DISABLED';
  RAISE EXCEPTION 'c02_missing_disabled_transition_rejection';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'Cannot transition bucket versioning status from %' THEN RAISE;END IF;
 END;
END $$;
SELECT 'PASS: reviewed invoker transition behavior; only temporary rows affected';
ROLLBACK;
