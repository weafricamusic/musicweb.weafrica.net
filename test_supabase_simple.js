const { createClient } = require('@supabase/supabase-js');

// Try to load from backend directory
try {
  require('dotenv').config({ path: './backend/.env' });
} catch (e) {
  console.log('No backend .env file found, trying other locations...');
}

// Try multiple possible locations for env files
try {
  require('dotenv').config({ path: '.env' });
} catch (e) {
  console.log('No root .env file found');
}

try {
  require('dotenv').config({ path: 'supabase/.env.local' });
} catch (e) {
  console.log('No supabase .env.local file found');
}

const supabaseUrl = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

console.log('Environment variables loaded:');
console.log('SUPABASE_URL:', supabaseUrl ? '✅ Set' : '❌ Not set');
console.log('PUBLIC_SUPABASE_URL:', process.env.PUBLIC_SUPABASE_URL ? '✅ Set' : '❌ Not set');
console.log('SUPABASE_SERVICE_KEY:', supabaseKey ? '✅ Set' : '❌ Not set');
console.log('SUPABASE_SERVICE_ROLE_KEY:', process.env.SUPABASE_SERVICE_ROLE_KEY ? '✅ Set' : '❌ Not set');

if (!supabaseUrl || !supabaseKey) {
  console.error('\n❌ Missing required Supabase credentials');
  console.error('Please set SUPABASE_URL and SUPABASE_SERVICE_KEY in your environment');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testConnection() {
  console.log('\n🔍 Testing Supabase connection...');

  try {
    // Simple test - check if we can access any table
    console.log('1️⃣ Testing basic connectivity...');
    
    const { data, error } = await supabase
      .from('songs')
      .select('count', { head: true });

    if (error) {
      console.error('❌ Connection failed:', error.message);
      console.error('Error details:', JSON.stringify(error, null, 2));
    } else {
      console.log('✅ Connection successful!');
      console.log('📊 Songs count:', data?.count || 0);
    }

    // If no songs, try other tables
    if (!data?.count || data.count === 0) {
      console.log('\n2️⃣ Checking other tables...');
      
      const tablesToCheck = ['artists', 'profiles', 'live_sessions', 'live_battles'];
      
      for (const table of tablesToCheck) {
        try {
          const { count, error: tableError } = await supabase
            .from(table)
            .select('*', { count: 'exact', head: true });
          
          if (!tableError) {
            console.log(`  ✅ ${table}: ${count || 0} records`);
          }
        } catch (tableError) {
          console.log(`  ⚠️  ${table}: ${tableError.message}`);
        }
      }
    }

  } catch (error) {
    console.error('❌ Unexpected error:', error.message);
    console.error(error.stack);
  }
}

testConnection();