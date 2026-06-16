-- Drop the old resident update policy
DROP POLICY IF EXISTS "Residents can update visitor logs for their unit" ON visitor_logs;

-- Re-create the resident update policy to allow 'LEAVE_AT_GATE'
CREATE POLICY "Residents can update visitor logs for their unit" ON visitor_logs
    FOR UPDATE TO authenticated
    USING (user_is_resident_of_unit(unit_id))
    WITH CHECK (status IN ('APPROVED', 'REJECTED', 'LEAVE_AT_GATE'));
