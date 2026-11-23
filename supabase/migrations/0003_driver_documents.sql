-- KHERJA — driver documents & verification workflow.
-- Drivers upload private files (Storage bucket `driver-documents`, folder = their user id)
-- and register them with submit_driver_document(). Admins review each document;
-- a driver can only be approved once every required document is approved.

-- ==================== table ====================
CREATE TABLE IF NOT EXISTS public.driver_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  doc_type text NOT NULL CHECK (doc_type IN ('id_card','license','registration','insurance','vehicle_photo')),
  storage_path text NOT NULL,
  mime_type text NOT NULL DEFAULT 'image/jpeg',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reason text,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),
  UNIQUE (driver_id, doc_type)
);

CREATE INDEX IF NOT EXISTS idx_driver_documents_status ON public.driver_documents (status, uploaded_at DESC);

ALTER TABLE public.driver_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Drivers read own documents" ON public.driver_documents;
CREATE POLICY "Drivers read own documents" ON public.driver_documents FOR SELECT
  USING (driver_id = auth.uid() OR public.has_perm('drivers.read'));
-- Writes only through SECURITY DEFINER functions below.

-- Required documents for approval (vehicle_photo is required too).
CREATE OR REPLACE FUNCTION public.required_driver_documents() RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['id_card','license','registration','insurance','vehicle_photo']::text[];
$$;

-- ==================== storage ====================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('driver-documents', 'driver-documents', false, 10485760,
        ARRAY['image/jpeg','image/png','image/heic','application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Drivers upload own documents" ON storage.objects;
CREATE POLICY "Drivers upload own documents" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'driver-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Drivers replace own documents" ON storage.objects;
CREATE POLICY "Drivers replace own documents" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'driver-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'driver-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Drivers and reviewers read documents" ON storage.objects;
CREATE POLICY "Drivers and reviewers read documents" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'driver-documents'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.has_perm('drivers.read')));

-- ==================== driver RPC ====================
CREATE OR REPLACE FUNCTION public.submit_driver_document(p_type text, p_path text, p_mime text DEFAULT 'image/jpeg')
RETURNS public.driver_documents
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me profiles;
  v_doc driver_documents;
BEGIN
  v_me := public.assert_active_user();
  IF v_me.role <> 'driver' THEN RAISE EXCEPTION 'Only drivers can upload documents'; END IF;
  IF NOT (p_type = ANY (public.required_driver_documents())) THEN RAISE EXCEPTION 'Invalid document type'; END IF;
  IF split_part(p_path, '/', 1) <> v_me.id::text THEN RAISE EXCEPTION 'Invalid document path'; END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'driver-documents' AND name = p_path) THEN
    RAISE EXCEPTION 'Document file not found';
  END IF;
  -- An approved document can only be replaced while the driver is not approved.
  IF v_me.driver_status = 'approved' AND EXISTS (
    SELECT 1 FROM driver_documents WHERE driver_id = v_me.id AND doc_type = p_type AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Document already approved';
  END IF;

  INSERT INTO driver_documents (driver_id, doc_type, storage_path, mime_type, status, reason, uploaded_at, reviewed_at, reviewed_by)
  VALUES (v_me.id, p_type, p_path, coalesce(p_mime, 'image/jpeg'), 'pending', NULL, now(), NULL, NULL)
  ON CONFLICT (driver_id, doc_type) DO UPDATE SET
    storage_path = EXCLUDED.storage_path, mime_type = EXCLUDED.mime_type, status = 'pending',
    reason = NULL, uploaded_at = now(), reviewed_at = NULL, reviewed_by = NULL
  RETURNING * INTO v_doc;

  -- A rejected driver who sends new documents goes back to the review queue.
  IF v_me.driver_status = 'rejected' THEN
    UPDATE profiles SET driver_status = 'pending', status_reason = NULL WHERE id = v_me.id;
  END IF;
  RETURN v_doc;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_driver_document(text, text, text) TO authenticated;

-- ==================== admin RPC ====================
CREATE OR REPLACE FUNCTION public.admin_review_document(p_id uuid, p_status text, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_before driver_documents;
BEGIN
  PERFORM public.require_perm('drivers.approve');
  IF p_status NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  IF p_status = 'rejected' AND coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  SELECT * INTO v_before FROM driver_documents WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Document not found'; END IF;

  UPDATE driver_documents SET status = p_status, reason = CASE WHEN p_status = 'rejected' THEN p_reason ELSE NULL END,
    reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = p_id;

  PERFORM public.write_audit('document.' || p_status, 'driver_document', p_id::text,
    jsonb_build_object('driver_id', v_before.driver_id, 'doc_type', v_before.doc_type, 'status', v_before.status),
    jsonb_build_object('driver_id', v_before.driver_id, 'doc_type', v_before.doc_type, 'status', p_status),
    p_reason);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_review_document(uuid, text, text) TO authenticated;

-- Approval now requires every required document to be approved.
CREATE OR REPLACE FUNCTION public.admin_set_driver_status(p_user uuid, p_status text, p_reason text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_before profiles;
  v_missing int;
BEGIN
  PERFORM public.require_perm('drivers.approve');
  IF p_status NOT IN ('approved','rejected','pending') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  SELECT * INTO v_before FROM profiles WHERE id = p_user FOR UPDATE;
  IF v_before.id IS NULL OR v_before.role <> 'driver' THEN RAISE EXCEPTION 'Driver not found'; END IF;
  IF p_status = 'rejected' AND coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  IF p_status = 'approved' THEN
    SELECT count(*) INTO v_missing FROM unnest(public.required_driver_documents()) t(doc)
    WHERE NOT EXISTS (SELECT 1 FROM driver_documents d WHERE d.driver_id = p_user AND d.doc_type = t.doc AND d.status = 'approved');
    IF v_missing > 0 THEN RAISE EXCEPTION 'All required documents must be approved first'; END IF;
  END IF;
  UPDATE profiles SET driver_status = p_status, status_reason = p_reason,
    is_online = CASE WHEN p_status = 'approved' THEN is_online ELSE false END
  WHERE id = p_user;
  PERFORM public.write_audit('driver.' || p_status, 'profile', p_user::text,
    jsonb_build_object('driver_status', v_before.driver_status), jsonb_build_object('driver_status', p_status), p_reason);
END;
$$;

-- Realtime for live status updates in the apps.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_documents;
EXCEPTION WHEN duplicate_object OR undefined_object THEN NULL;
END $$;
