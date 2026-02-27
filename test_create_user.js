import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://hoxmscslxmbdfyyfkhrt.supabase.co';
const supabaseServiceKey = process.env.VITE_SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

// If we don't have the service role key, I can't use admin API easily in this script unless I find it in .env or somewhere.
// Let's check if we have it.
console.log(!!supabaseServiceKey);
