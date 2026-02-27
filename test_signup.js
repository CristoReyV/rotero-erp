import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
    'https://hoxmscslxmbdfyyfkhrt.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhveG1zY3NseG1iZGZ5eWZraHJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5NjI5NDMsImV4cCI6MjA4NzUzODk0M30.Q9wHSrKBsfGixiN4c4XUUWgeWsTYFrDfqeQ_dN59FN0'
);

async function test() {
    const { data, error } = await supabase.auth.signUp({
        email: 'new_user@rotero.com',
        password: 'Password123!'
    });
    console.log('Error:', error);
    console.log('Data:', data);
}

test();
