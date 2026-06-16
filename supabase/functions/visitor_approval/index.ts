import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

console.log("Visitor Approval function started!")

serve(async (req) => {
  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    // Example webhook payload when a new visitor_log is inserted
    const payload = await req.json()
    const record = payload.record

    if (payload.type === 'INSERT' && record.status === 'PENDING') {
      // 1. Fetch the resident's push token (Assuming we have it in a separate table or profile)
      const { data: unitData, error: unitError } = await supabaseClient
        .from('units')
        .select('*, user_roles(*)')
        .eq('id', record.unit_id)
        .single()
      
      if (unitError) throw unitError

      // 2. Trigger Expo Push Notifications
      console.log(`Simulating push notification to residents of unit ${unitData.unit_number}`)
      
      const pushMessage = {
        to: 'ExponentPushToken[mock]', 
        sound: 'default',
        title: 'New Visitor',
        body: `You have a new visitor. Please approve or reject via the app.`,
        data: { visitorLogId: record.id },
      };

      // Simulate sending push notification
      console.log('Push message sent:', pushMessage)
    }

    return new Response(
      JSON.stringify({ message: 'Success' }),
      { headers: { "Content-Type": "application/json" } },
    )
  } catch (err) {
    return new Response(String(err?.message ?? err), { status: 500 })
  }
})
