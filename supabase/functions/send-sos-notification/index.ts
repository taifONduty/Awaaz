// supabase/functions/send-sos-notification/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

console.log("Function is starting...");

serve(async (req) => {
  try {
    console.log("Received request");

    // Parse the request body
    const body = await req.json();
    console.log("Request body:", body);

    // Log environment variables (safely)
    console.log("Environment check:");
    console.log("- SUPABASE_URL exists:", !!Deno.env.get("SUPABASE_URL"));
    console.log("- SUPABASE_SERVICE_ROLE_KEY exists:", !!Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    console.log("- GOOGLE_CLOUD_PROJECT_ID exists:", !!Deno.env.get("GOOGLE_CLOUD_PROJECT_ID"));
    console.log("- GOOGLE_SERVICE_ACCOUNT exists:", !!Deno.env.get("GOOGLE_SERVICE_ACCOUNT"));

    // Just echo back the request for now
    return new Response(
      JSON.stringify({
        success: true,
        message: "Function is working",
        receivedData: body
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 200
      }
    );

  } catch (error) {
    console.error("Error:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 400
      }
    );
  }
});