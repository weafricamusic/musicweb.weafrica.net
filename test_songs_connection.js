const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

// Load environment variables
const supabaseUrl = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing Supabase environment variables');
  console.error('SUPABASE_URL:', process.env.SUPABASE_URL);
  console.error('PUBLIC_SUPABASE_URL:', process.env.PUBLIC_SUPABASE_URL);
  console.error('SUPABASE_SERVICE_KEY:', process.env.SUPABASE_SERVICE_KEY);
  console.error('SUPABASE_SERVICE_ROLE_KEY:', process.env.SUPABASE_SERVICE_ROLE_KEY);
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testSongsConnection() {
  console.log('🔍 Testing Supabase songs connection...');
  console.log('📊 URL:', supabaseUrl);
  console.log('🔑 Key:', supabaseKey.substring(0, 10) + '...');

  try {
    // Test 1: Check if songs table exists
    console.log('\n1️⃣ Testing songs table existence...');
    const { data: songs, error: songsError } = await supabase
      .from('songs')
      .select('*', { count: 'exact', head: true });

    if (songsError) {
      console.error('❌ Error accessing songs table:', songsError.message);
      return;
    }

    console.log('✅ Songs table accessible');
    console.log('📊 Total songs count:', songs?.length || 0);

    // Test 2: Try to get some songs with different filter combinations
    console.log('\n2️⃣ Testing different query combinations...');

    const queries = [
      { name: 'All songs', query: supabase.from('songs').select('*').order('created_at', { ascending: false }).limit(5) },
      { name: 'Public songs', query: supabase.from('songs').select('*').eq('is_public', true).limit(5) },
      { name: 'Active songs', query: supabase.from('songs').select('*').eq('is_active', true).limit(5) },
      { name: 'Active status songs', query: supabase.from('songs').select('*').eq('status', 'active').limit(5) },
      { name: 'Approved songs', query: supabase.from('songs').select('*').eq('approved', true).limit(5) },
      { name: 'Published songs', query: supabase.from('songs').select('*').eq('is_published', true).limit(5) },
    ];

    for (const { name, query } of queries) {
      try {
        const { data, error } = await query;
        if (error) {
          console.log(`  ⚠️  ${name}: ${error.message}`);
        } else {
          console.log(`  ✅ ${name}: ${data?.length || 0} songs found`);
          if (data && data.length > 0) {
            console.log(`     Sample: ${data[0].title || 'Untitled'} by ${data[0].artist || 'Unknown'}`);
          }
        }
      } catch (error) {
        console.log(`  ❌ ${name}: ${error.message}`);
      }
    }

    // Test 3: Check table structure
    console.log('\n3️⃣ Checking songs table structure...');
    try {
      const { data: sampleSong, error: sampleError } = await supabase
        .from('songs')
        .select('*')
        .limit(1)
        .maybeSingle();

      if (sampleError) {
        console.log('  ⚠️  Could not get sample song:', sampleError.message);
      } else if (sampleSong) {
        console.log('  ✅ Sample song structure:');
        const keys = Object.keys(sampleSong);
        console.log('     Columns:', keys.join(', '));
        console.log('     Sample data:', JSON.stringify(sampleSong, null, 2).substring(0, 200) + '...');
      } else {
        console.log('  ℹ️  No songs found in database');
      }
    } catch (error) {
      console.log('  ❌ Error checking table structure:', error.message);
    }

    console.log('\n✅ Test completed successfully!');
    console.log('💡 If you see songs in the database but not in the app:');
    console.log('   1. Check that songs have is_public=true, is_active=true, status="active"');
    console.log('   2. Check that songs have valid audio_url values');
    console.log('   3. Verify the feed service is running and cache is cleared');

  } catch (error) {
    console.error('❌ Unexpected error:', error.message);
    console.error(error.stack);
  }
}

testSongsConnection();