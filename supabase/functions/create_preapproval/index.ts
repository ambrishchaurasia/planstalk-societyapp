import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Verify caller
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const userClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json()
    const {
      society_id,
      unit_id,
      guest_name,
      guest_phone,
      guest_vehicle_number,
      visitor_type,
      valid_from,
      valid_until,
      max_uses,
      notes,
      guest_photo_url,
    } = body

    // Validate required fields
    if (!society_id || !unit_id || !guest_name || !valid_until) {
      return new Response(JSON.stringify({
        error: 'society_id, unit_id, guest_name, and valid_until are required'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Verify the user is a resident of this unit
    const { data: residentRole } = await supabaseClient
      .from('user_roles')
      .select('id')
      .eq('user_id', user.id)
      .eq('unit_id', unit_id)
      .eq('role', 'RESIDENT')
      .eq('status', 'APPROVED')
      .single()

    if (!residentRole) {
      return new Response(JSON.stringify({ error: 'You are not a resident of this unit' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Generate a unique passcode
    const { data: passcode, error: codeError } = await supabaseClient.rpc(
      'generate_visitor_passcode',
      { p_society_id: society_id }
    )
    if (codeError) throw codeError

    // Insert the pre-approval
    const { data: preapproval, error: insertError } = await supabaseClient
      .from('preapproved_visitors')
      .insert({
        society_id,
        unit_id,
        created_by: user.id,
        guest_name,
        guest_phone: guest_phone || null,
        guest_vehicle_number: guest_vehicle_number || null,
        visitor_type: visitor_type || 'GUEST',
        passcode,
        valid_from: valid_from || new Date().toISOString(),
        valid_until,
        max_uses: max_uses ?? 1,
        notes: notes || null,
        guest_photo_url: guest_photo_url || null,
      })
      .select()
      .single()

    if (insertError) throw insertError

    return new Response(JSON.stringify({
      success: true,
      preapproval: {
        id: preapproval.id,
        guest_name: preapproval.guest_name,
        passcode: preapproval.passcode,
        valid_from: preapproval.valid_from,
        valid_until: preapproval.valid_until,
        max_uses: preapproval.max_uses,
        status: preapproval.status,
        guest_photo_url: preapproval.guest_photo_url,
      },
      message: `Share this passcode with your guest: ${passcode}`,
    }), {
      status: 201,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: err?.message ?? String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
