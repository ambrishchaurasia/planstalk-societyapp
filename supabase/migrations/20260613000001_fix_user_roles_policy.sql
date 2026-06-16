-- Drop the recursive policy on user_roles
DROP POLICY IF EXISTS "Admins can manage roles in their society" ON user_roles;

-- Create user_has_role_in_society helper function if it doesn't exist (with SECURITY DEFINER to bypass RLS recursion)
CREATE OR REPLACE FUNCTION public.user_has_role_in_society(check_society_id UUID, required_role app_role)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid()
        AND society_id = check_society_id
        AND role = required_role
        AND status = 'APPROVED'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-create the policy using the helper function
CREATE POLICY "Admins can manage roles in their society" ON user_roles
    FOR ALL TO authenticated
    USING (public.user_has_role_in_society(society_id, 'ADMIN'::app_role));
