CREATE TYPE ticket_category AS ENUM ('PLUMBING', 'ELECTRICAL', 'CARPENTRY', 'CLEANING', 'OTHER');
CREATE TYPE ticket_status AS ENUM ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED');
CREATE TYPE ticket_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT');
CREATE TYPE invoice_status AS ENUM ('PENDING', 'PAID', 'OVERDUE', 'CANCELLED');

-- Tickets Table
CREATE TABLE tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES units(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES profiles(id) ON DELETE SET NULL,
    category ticket_category NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status ticket_status DEFAULT 'OPEN'::ticket_status,
    priority ticket_priority DEFAULT 'LOW'::ticket_priority,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Invoices Table
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    society_id UUID NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    unit_id UUID NOT NULL REFERENCES units(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    status invoice_status DEFAULT 'PENDING'::invoice_status,
    due_date DATE NOT NULL,
    billing_month DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Payments Table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    amount_paid NUMERIC(10, 2) NOT NULL,
    payment_method TEXT,
    transaction_id TEXT,
    payment_date TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_tickets_society_id ON tickets(society_id);
CREATE INDEX idx_tickets_unit_id ON tickets(unit_id);
CREATE INDEX idx_tickets_status ON tickets(status);

CREATE INDEX idx_invoices_society_id ON invoices(society_id);
CREATE INDEX idx_invoices_unit_id ON invoices(unit_id);
CREATE INDEX idx_invoices_status ON invoices(status);

ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER set_tickets_updated_at
BEFORE UPDATE ON tickets
FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_invoices_updated_at
BEFORE UPDATE ON invoices
FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- RLS Policies for Tickets
-- Residents can view/create tickets for their unit
CREATE POLICY "Residents can view tickets for their unit" ON tickets
    FOR SELECT TO authenticated
    USING (user_is_resident_of_unit(unit_id));

CREATE POLICY "Residents can create tickets for their unit" ON tickets
    FOR INSERT TO authenticated
    WITH CHECK (user_is_resident_of_unit(unit_id));

-- Admins can view and manage all tickets
CREATE POLICY "Admins can view all tickets" ON tickets
    FOR SELECT TO authenticated
    USING (user_has_role_in_society(society_id, 'ADMIN'));

CREATE POLICY "Admins can update all tickets" ON tickets
    FOR UPDATE TO authenticated
    USING (user_has_role_in_society(society_id, 'ADMIN'));

-- Maintenance Staff can view and update assigned tickets
CREATE POLICY "Staff can view assigned tickets" ON tickets
    FOR SELECT TO authenticated
    USING (assigned_to = auth.uid());

CREATE POLICY "Staff can update assigned tickets" ON tickets
    FOR UPDATE TO authenticated
    USING (assigned_to = auth.uid());

-- RLS Policies for Invoices
CREATE POLICY "Residents can view invoices for their unit" ON invoices
    FOR SELECT TO authenticated
    USING (user_is_resident_of_unit(unit_id));

CREATE POLICY "Admins can manage invoices" ON invoices
    FOR ALL TO authenticated
    USING (user_has_role_in_society(society_id, 'ADMIN'));

-- RLS Policies for Payments
CREATE POLICY "Residents can view their payments" ON payments
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM invoices
            WHERE invoices.id = payments.invoice_id
            AND user_is_resident_of_unit(invoices.unit_id)
        )
    );

CREATE POLICY "Admins can manage payments" ON payments
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM invoices
            WHERE invoices.id = payments.invoice_id
            AND user_has_role_in_society(invoices.society_id, 'ADMIN')
        )
    );
