const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres:-u94B%3F2%24HqPQg3N@db.nbzdufwopaktdqkxugrt.supabase.co:5432/postgres'
});

async function run() {
  await client.connect();
  console.log('Connected to PG!');

  console.log('Applying policy updates directly to visitor_logs...');
  
  // 1. Drop existing policy
  await client.query(`
    DROP POLICY IF EXISTS "Residents can update visitor logs for their unit" ON public.visitor_logs;
  `);
  console.log('Dropped old policy.');

  // 2. Create updated policy
  await client.query(`
    CREATE POLICY "Residents can update visitor logs for their unit" ON public.visitor_logs
        FOR UPDATE TO authenticated
        USING (public.user_is_resident_of_unit(unit_id))
        WITH CHECK (status IN ('APPROVED', 'REJECTED', 'LEAVE_AT_GATE'));
  `);
  console.log('Created new policy with LEAVE_AT_GATE.');

  // 3. Mark migration as applied in Supabase tracking table
  await client.query(`
    INSERT INTO supabase_migrations.schema_migrations (version) 
    VALUES ('20260616000001') 
    ON CONFLICT (version) DO NOTHING;
  `);
  console.log('Registered migration 20260616000001 in schema_migrations.');

  // 4. Double check by printing policies again
  const policiesRes = await client.query(`
    SELECT policyname, cmd, qual, with_check
    FROM pg_policies
    WHERE tablename = 'visitor_logs';
  `);
  console.log('\nUpdated visitor_logs policies:');
  policiesRes.rows.forEach(p => {
    console.log(`- Policy Name: ${p.policyname}`);
    console.log(`  Command: ${p.cmd}`);
    console.log(`  USING: ${p.qual}`);
    console.log(`  WITH CHECK: ${p.with_check}`);
  });

  await client.end();
}

run().catch(console.error);
