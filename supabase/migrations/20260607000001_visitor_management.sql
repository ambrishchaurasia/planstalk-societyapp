CREATE TYPE app_visitor_type AS ENUM ('GUEST', 'DELIVERY', 'CAB', 'SERVICE');
CREATE TYPE visitor_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'ENTERED', 'EXITED');

CREATE TABLE visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone_number TEXT,
    photo_url TEXT,
    vehicle_number TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE visitor_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_id UUID NOT NULL REFERENCES visitors(id) ON DELETE CASCADE,
    society_id UUID NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES units(id) ON DELETE CASCADE,
    guard_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    visitor_type app_visitor_type NOT NULL,
    status visitor_status DEFAULT 'PENDING'::visitor_status,
    entry_time TIMESTAMPTZ,
    exit_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_visitors_society_id ON visitors(society_id);
CREATE INDEX idx_visitor_logs_society_id ON visitor_logs(society_id);
CREATE INDEX idx_visitor_logs_unit_id ON visitor_logs(unit_id);
CREATE INDEX idx_visitor_logs_status ON visitor_logs(status);

ALTER TABLE visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE visitor_logs ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER set_visitor_logs_updated_at
BEFORE UPDATE ON visitor_logs
FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- RLS Policies
-- Helper function to check if user has a specific role in a society
CREATE OR REPLACE FUNCTION user_has_role_in_society(check_society_id UUID, required_role app_role)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM user_roles
        WHERE user_id = auth.uid()
        AND society_id = check_society_id
        AND role = required_role
        AND status = 'APPROVED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to check if user is a resident of a specific unit
CREATE OR REPLACE FUNCTION user_is_resident_of_unit(check_unit_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM user_roles
        WHERE user_id = auth.uid()
        AND unit_id = check_unit_id
        AND role = 'RESIDENT'
        AND status = 'APPROVED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Visitors policies
CREATE POLICY "Guards and Admins can view visitors" ON visitors
    FOR SELECT TO authenticated
    USING (
        user_has_role_in_society(society_id, 'GUARD') OR
        user_has_role_in_society(society_id, 'ADMIN')
    );

CREATE POLICY "Guards and Admins can insert visitors" ON visitors
    FOR INSERT TO authenticated
    WITH CHECK (
        user_has_role_in_society(society_id, 'GUARD') OR
        user_has_role_in_society(society_id, 'ADMIN')
    );

CREATE POLICY "Guards and Admins can update visitors" ON visitors
    FOR UPDATE TO authenticated
    USING (
        user_has_role_in_society(society_id, 'GUARD') OR
        user_has_role_in_society(society_id, 'ADMIN')
    );

CREATE POLICY "Residents can view visitors for their unit" ON visitors
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM visitor_logs
            WHERE visitor_logs.visitor_id = visitors.id
            AND user_is_resident_of_unit(visitor_logs.unit_id)
        )
    );

-- Visitor Logs policies
CREATE POLICY "Guards and Admins can view visitor logs" ON visitor_logs
    FOR SELECT TO authenticated
    USING (
        user_has_role_in_society(society_id, 'GUARD') OR
        user_has_role_in_society(society_id, 'ADMIN')
    );

CREATE POLICY "Guards can insert visitor logs" ON visitor_logs
    FOR INSERT TO authenticated
    WITH CHECK (user_has_role_in_society(society_id, 'GUARD'));

CREATE POLICY "Guards and Admins can update visitor logs" ON visitor_logs
    FOR UPDATE TO authenticated
    USING (
        user_has_role_in_society(society_id, 'GUARD') OR
        user_has_role_in_society(society_id, 'ADMIN')
    );

CREATE POLICY "Residents can view visitor logs for their unit" ON visitor_logs
    FOR SELECT TO authenticated
    USING (user_is_resident_of_unit(unit_id));

CREATE POLICY "Residents can update visitor logs for their unit" ON visitor_logs
    FOR UPDATE TO authenticated
    USING (user_is_resident_of_unit(unit_id))
    WITH CHECK (status IN ('APPROVED', 'REJECTED'));
