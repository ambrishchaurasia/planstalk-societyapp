-- Pre-approved Visitors feature
-- Residents can pre-register expected guests with a unique passcode.
-- When the guest arrives, the guard scans/enters the passcode and entry is auto-approved.

CREATE TYPE preapproval_status AS ENUM ('ACTIVE', 'USED', 'EXPIRED', 'CANCELLED');

-- Pre-approved visitors table
CREATE TABLE preapproved_visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES units(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    -- Guest details
    guest_name TEXT NOT NULL,
    guest_phone TEXT,
    guest_vehicle_number TEXT,
    visitor_type app_visitor_type DEFAULT 'GUEST'::app_visitor_type,

    -- Access control
    passcode TEXT NOT NULL,              -- 6-digit code or short alphanumeric
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ NOT NULL,    -- expiry time
    max_uses INT DEFAULT 1,             -- 1 = single-use, NULL = unlimited within validity
    current_uses INT DEFAULT 0,
    status preapproval_status DEFAULT 'ACTIVE'::preapproval_status,

    -- Metadata
    notes TEXT,                          -- e.g., "Plumber coming to fix kitchen sink"
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_preapproved_society_id ON preapproved_visitors(society_id);
CREATE INDEX idx_preapproved_unit_id ON preapproved_visitors(unit_id);
CREATE INDEX idx_preapproved_passcode ON preapproved_visitors(society_id, passcode);
CREATE INDEX idx_preapproved_status ON preapproved_visitors(status);
CREATE INDEX idx_preapproved_valid_until ON preapproved_visitors(valid_until);

-- Enable RLS
ALTER TABLE preapproved_visitors ENABLE ROW LEVEL SECURITY;

-- Auto-update timestamp
CREATE TRIGGER set_preapproved_visitors_updated_at
BEFORE UPDATE ON preapproved_visitors
FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- ============================================================
-- RLS POLICIES
-- ============================================================

-- Residents can view their own pre-approvals
CREATE POLICY "Residents can view own preapprovals" ON preapproved_visitors
    FOR SELECT TO authenticated
    USING (created_by = auth.uid());

-- Residents can create pre-approvals for their own unit
CREATE POLICY "Residents can create preapprovals" ON preapproved_visitors
    FOR INSERT TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND user_is_resident_of_unit(unit_id)
    );

-- Residents can update (cancel) their own pre-approvals
CREATE POLICY "Residents can update own preapprovals" ON preapproved_visitors
    FOR UPDATE TO authenticated
    USING (created_by = auth.uid())
    WITH CHECK (created_by = auth.uid());

-- Residents can delete their own pre-approvals
CREATE POLICY "Residents can delete own preapprovals" ON preapproved_visitors
    FOR DELETE TO authenticated
    USING (created_by = auth.uid());

-- Guards can view active pre-approvals in their society (to verify at gate)
CREATE POLICY "Guards can view preapprovals" ON preapproved_visitors
    FOR SELECT TO authenticated
    USING (user_has_role_in_society(society_id, 'GUARD'));

-- Guards can update pre-approvals (to mark as USED on entry)
CREATE POLICY "Guards can update preapprovals" ON preapproved_visitors
    FOR UPDATE TO authenticated
    USING (user_has_role_in_society(society_id, 'GUARD'));

-- Admins have full access
CREATE POLICY "Admins can manage preapprovals" ON preapproved_visitors
    FOR ALL TO authenticated
    USING (user_has_role_in_society(society_id, 'ADMIN'));

-- ============================================================
-- FUNCTIONS
-- ============================================================

-- Generate a unique 6-digit passcode for a society
CREATE OR REPLACE FUNCTION generate_visitor_passcode(p_society_id UUID)
RETURNS TEXT AS $$
DECLARE
    new_code TEXT;
    code_exists BOOLEAN;
BEGIN
    LOOP
        -- Generate a random 6-digit number
        new_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
        
        -- Check if this code is already active in the same society
        SELECT EXISTS (
            SELECT 1 FROM preapproved_visitors
            WHERE society_id = p_society_id
            AND passcode = new_code
            AND status = 'ACTIVE'
            AND valid_until > now()
        ) INTO code_exists;
        
        -- If unique, return it
        IF NOT code_exists THEN
            RETURN new_code;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Verify a passcode at the gate and auto-create a visitor log entry
-- Called by the guard when a visitor arrives with a code
CREATE OR REPLACE FUNCTION verify_visitor_passcode(
    p_society_id UUID,
    p_passcode TEXT,
    p_guard_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_preapproval preapproved_visitors%ROWTYPE;
    v_visitor_id UUID;
    v_log_id UUID;
    v_result JSONB;
BEGIN
    -- Find the active pre-approval
    SELECT * INTO v_preapproval
    FROM preapproved_visitors
    WHERE society_id = p_society_id
    AND passcode = p_passcode
    AND status = 'ACTIVE'
    AND valid_from <= now()
    AND valid_until > now()
    LIMIT 1;

    -- Not found or expired
    IF v_preapproval.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invalid or expired passcode'
        );
    END IF;

    -- Check max uses
    IF v_preapproval.max_uses IS NOT NULL AND v_preapproval.current_uses >= v_preapproval.max_uses THEN
        -- Mark as used
        UPDATE preapproved_visitors SET status = 'USED' WHERE id = v_preapproval.id;
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Passcode has already been used the maximum number of times'
        );
    END IF;

    -- Create or find the visitor record
    INSERT INTO visitors (society_id, name, phone_number, vehicle_number)
    VALUES (
        p_society_id,
        v_preapproval.guest_name,
        v_preapproval.guest_phone,
        v_preapproval.guest_vehicle_number
    )
    RETURNING id INTO v_visitor_id;

    -- Create an auto-approved visitor log
    INSERT INTO visitor_logs (
        visitor_id, society_id, unit_id, guard_id,
        approved_by, visitor_type, status, entry_time
    )
    VALUES (
        v_visitor_id,
        p_society_id,
        v_preapproval.unit_id,
        COALESCE(p_guard_id, auth.uid()),
        v_preapproval.created_by,       -- auto-approved by the resident who created it
        v_preapproval.visitor_type,
        'ENTERED'::visitor_status,       -- skip PENDING, go straight to ENTERED
        now()
    )
    RETURNING id INTO v_log_id;

    -- Increment use count
    UPDATE preapproved_visitors
    SET current_uses = current_uses + 1,
        status = CASE
            WHEN max_uses IS NOT NULL AND current_uses + 1 >= max_uses THEN 'USED'::preapproval_status
            ELSE 'ACTIVE'::preapproval_status
        END
    WHERE id = v_preapproval.id;

    RETURN jsonb_build_object(
        'success', true,
        'visitor_id', v_visitor_id,
        'visitor_log_id', v_log_id,
        'guest_name', v_preapproval.guest_name,
        'unit_id', v_preapproval.unit_id,
        'message', 'Visitor pre-approved. Entry granted.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Cron-friendly function to expire stale pre-approvals
-- Can be called by pg_cron or a Supabase scheduled function
CREATE OR REPLACE FUNCTION expire_preapprovals()
RETURNS INTEGER AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    UPDATE preapproved_visitors
    SET status = 'EXPIRED'
    WHERE status = 'ACTIVE'
    AND valid_until < now();

    GET DIAGNOSTICS expired_count = ROW_COUNT;
    RETURN expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
