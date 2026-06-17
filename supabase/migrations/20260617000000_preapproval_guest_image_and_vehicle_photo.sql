-- Migration: Add guest pre-approval photo and vehicle photo fields, and allow residents to upload photos to visitor_photos bucket

-- 1. Add column for guest photo in pre-approvals
ALTER TABLE preapproved_visitors ADD COLUMN IF NOT EXISTS guest_photo_url TEXT;

-- 2. Add column for vehicle photo in visitor logs
ALTER TABLE visitor_logs ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT;

-- 3. Update verify_visitor_passcode function to copy guest_photo_url to visitors.photo_url
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

    -- Create or find the visitor record, copying the guest_photo_url to photo_url
    INSERT INTO visitors (society_id, name, phone_number, vehicle_number, photo_url)
    VALUES (
        p_society_id,
        v_preapproval.guest_name,
        v_preapproval.guest_phone,
        v_preapproval.guest_vehicle_number,
        v_preapproval.guest_photo_url
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
        'guest_photo_url', v_preapproval.guest_photo_url,
        'message', 'Visitor pre-approved. Entry granted.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Add RLS policy to allow residents to upload photos in visitor_photos storage bucket
-- Check if policy exists first, if not, create it
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'objects' 
        AND schemaname = 'storage' 
        AND policyname = 'Residents can upload visitor photos'
    ) THEN
        CREATE POLICY "Residents can upload visitor photos"
        ON storage.objects FOR INSERT TO authenticated
        WITH CHECK (
            bucket_id = 'visitor_photos' AND
            EXISTS (
                SELECT 1 FROM user_roles
                WHERE user_id = auth.uid() 
                AND role = 'RESIDENT' 
                AND status = 'APPROVED'
            )
        );
    END IF;
END
$$;
