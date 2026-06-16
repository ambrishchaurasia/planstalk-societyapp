-- Insert buckets
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);
INSERT INTO storage.buckets (id, name, public) VALUES ('kyc_documents', 'kyc_documents', false);
INSERT INTO storage.buckets (id, name, public) VALUES ('visitor_photos', 'visitor_photos', false);

-- Setup RLS for storage.objects
-- Avatars: Anyone can read, but users can only upload/update their own (assuming path is user_id/filename)
CREATE POLICY "Avatar images are publicly accessible."
  ON storage.objects FOR SELECT
  USING ( bucket_id = 'avatars' );

CREATE POLICY "Users can upload their own avatars."
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK ( bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1] );

CREATE POLICY "Users can update their own avatars."
  ON storage.objects FOR UPDATE TO authenticated
  USING ( bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1] );

CREATE POLICY "Users can delete their own avatars."
  ON storage.objects FOR DELETE TO authenticated
  USING ( bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1] );

-- KYC Documents: Only the user and admins can read, user can upload
CREATE POLICY "Users can read own kyc docs"
  ON storage.objects FOR SELECT TO authenticated
  USING ( bucket_id = 'kyc_documents' AND auth.uid()::text = (storage.foldername(name))[1] );

CREATE POLICY "Admins can read kyc docs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'kyc_documents' AND
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid() AND role = 'ADMIN'
    )
  );

CREATE POLICY "Users can upload own kyc docs"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK ( bucket_id = 'kyc_documents' AND auth.uid()::text = (storage.foldername(name))[1] );

-- Visitor Photos
CREATE POLICY "Guards and Admins can manage visitor photos"
  ON storage.objects FOR ALL TO authenticated
  USING (
    bucket_id = 'visitor_photos' AND
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid() AND role IN ('ADMIN', 'GUARD')
    )
  );

CREATE POLICY "Residents can view visitor photos"
  ON storage.objects FOR SELECT TO authenticated
  USING (
      bucket_id = 'visitor_photos' AND
      EXISTS (
        SELECT 1 FROM user_roles
        WHERE user_id = auth.uid() AND role = 'RESIDENT'
      )
  );
