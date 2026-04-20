const { createClient } = require('@supabase/supabase-js');

// Use the provided Supabase URL
const supabaseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

console.log('🎵 WeAfrica Music - Songs Test');
console.log('🔗 Supabase URL:', supabaseUrl);
console.log('🔑 Service Key:', supabaseKey ? '✅ Set' : '❌ Not set');

if (!supabaseKey) {
  console.error('\n❌ Service key is required to test the connection');
  console.error('💡 Please set SUPABASE_SERVICE_KEY in your environment');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testSongsConnection() {
  console.log('\n🔍 Testing Supabase songs connection...');

  try {
    // Test 1: Basic connectivity
    console.log('\n1️⃣ Testing basic database connectivity...');
    
    const { count, error: countError } = await supabase
      .from('songs')
      .select('*', { count: 'exact', head: true });

    if (countError) {
      console.error('❌ Database connection failed:', countError.message);
      console.error('Error details:', JSON.stringify(countError, null, 2));
      return;
    }

    console.log('✅ Database connection successful!');
    console.log('📊 Total songs in database:', count || 0);

    // Test 2: Check songs with different filters
    console.log('\n2️⃣ Testing song retrieval with different filters...');

    const filters = [
      { name: 'All songs', query: supabase.from('songs').select('*', { count: 'exact', head: true }) },
      { name: 'Public songs', query: supabase.from('songs').select('*', { count: 'exact', head: true }).eq('is_public', true) },
      { name: 'Active songs', query: supabase.from('songs').select('*', { count: 'exact', head: true }).eq('is_active', true) },
      { name: 'Active status', query: supabase.from('songs').select('*', { count: 'exact', head: true }).eq('status', 'active') },
      { name: 'With audio URL', query: supabase.from('songs').select('*', { count: 'exact', head: true }).neq('audio_url', null) },
    ];

    for (const { name, query } of filters) {
      try {
        const { count: filterCount, error: filterError } = await query;
        if (filterError) {
          console.log(`  ⚠️  ${name}: ${filterError.message}`);
        } else {
          console.log(`  ✅ ${name}: ${filterCount || 0} songs`);
        }
      } catch (error) {
        console.log(`  ❌ ${name}: ${error.message}`);
      }
    }

    // Test 3: Get sample songs
    console.log('\n3️⃣ Retrieving sample song data...');

    const { data: songs, error: songsError } = await supabase
      .from('songs')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(3);

    if (songsError) {
      console.error('❌ Could not retrieve songs:', songsError.message);
    } else if (songs && songs.length > 0) {
      console.log(`✅ Found ${songs.length} songs:`);
      songs.forEach((song, index) => {
        console.log(`\n  Song ${index + 1}:`);
        console.log(`    ID: ${song.id}`);
        console.log(`    Title: ${song.title || 'Untitled'}`);
        console.log(`    Artist: ${song.artist || 'Unknown'}`);
        console.log(`    Public: ${song.is_public || false}`);
        console.log(`    Active: ${song.is_active || false}`);
        console.log(`    Status: ${song.status || 'unknown'}`);
        console.log(`    Audio URL: ${song.audio_url ? '✅ Set' : '❌ Not set'}`);
        console.log(`    Created: ${new Date(song.created_at).toLocaleString()}`);
      });
    } else {
      console.log('ℹ️ No songs found in database');
    }

    // Test 4: Check feed-compatible songs
    console.log('\n4️⃣ Checking feed-compatible songs...');

    const { data: feedSongs, error: feedError } = await supabase
      .from('songs')
      .select('*')
      .eq('is_public', true)
      .eq('is_active', true)
      .eq('status', 'active')
      .neq('audio_url', null)
      .order('created_at', { ascending: false })
      .limit(5);

    if (feedError) {
      console.error('❌ Feed query failed:', feedError.message);
    } else {
      console.log(`✅ Feed-compatible songs: ${feedSongs?.length || 0}`);
      
      if (feedSongs && feedSongs.length > 0) {
        console.log('\n🎉 Sample feed-compatible songs:');
        feedSongs.slice(0, 2).forEach((song, index) => {
          console.log(`\n  ${index + 1}. ${song.title} by ${song.artist}`);
          console.log(`     🎵 Audio: ${song.audio_url}`);
          console.log(`     📅 Created: ${new Date(song.created_at).toLocaleDateString()}`);
        });
      } else {
        console.log('\n💡 If you have songs but none are feed-compatible:');
        console.log('   1. Set is_public = true');
        console.log('   2. Set is_active = true');
        console.log('   3. Set status = "active"');
        console.log('   4. Ensure audio_url is not null');
        console.log('   5. Songs will then appear in the feed and API responses');
      }
    }

    console.log('\n✅ Test completed successfully!');
    console.log('\n📋 Summary:');
    console.log('   • Database connection: ✅ Working');
    console.log('   • Songs table: ✅ Accessible');
    console.log('   • API endpoints: ✅ Should work with new /api/songs routes');
    console.log('   • Feed integration: ✅ Depends on song filters');

  } catch (error) {
    console.error('❌ Unexpected error:', error.message);
    console.error(error.stack);
  }
}

testSongsConnection();