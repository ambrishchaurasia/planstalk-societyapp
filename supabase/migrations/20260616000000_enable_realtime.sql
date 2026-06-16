-- Add 'LEAVE_AT_GATE' to visitor_status enum if not exists
-- Note: ALTER TYPE ... ADD VALUE cannot be executed inside a transaction block in some Postgres versions.
-- Supabase executes migrations in separate statements, which handles this perfectly.
ALTER TYPE visitor_status ADD VALUE IF NOT EXISTS 'LEAVE_AT_GATE';

-- Add columns to visitor_logs for the "Leave at Gate" and package retrieval workflow
ALTER TABLE visitor_logs ADD COLUMN IF NOT EXISTS collection_code VARCHAR(6) NULL;
ALTER TABLE visitor_logs ADD COLUMN IF NOT EXISTS collected_at TIMESTAMPTZ NULL;

-- Enable Realtime replication for the visitor_logs table
-- Check if the table is already in the publication first, or add it directly
ALTER PUBLICATION supabase_realtime ADD TABLE visitor_logs;
