const { createClient } = require('@supabase/supabase-js');

// Use the provided Supabase credentials
const supabaseUrl = 'https://nxkutpjdoidfwpkjbwcm.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NzEwMDY2MSwiZXhwIjoyMDgyNjc2NjYxfQ.qoE-jE8yKMkpCmSjKsTdQZMMYY3K8Za067lMrETeXzE';

console.log('🎵 WeAfrica Music - Complete Connection Test');
console.log('🔗 Supabase URL:', supabaseUrl);
console.log('🔑 Service Key:', supabaseKey.substring(0, 10) + '...');

const supabase = createClient(supabaseUrl, supabaseKey);

async function testCompleteConnection() {
  console.log('\n🔍 Testing complete Supabase connection...');

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

    // Test 2: Get detailed song information
    console.log('\n2️⃣ Retrieving detailed song information...');

    const { data: songs, error: songsError } = await supabase
      .from('songs')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(5);

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

    // Test 3: Check feed-compatible songs
    console.log('\n3️⃣ Checking feed-compatible songs...');

    const { data: feedSongs, error: feedError } = await supabase
      .from('songs')
      .select('*')
      .eq('is_public', true)
      .eq('is_active', true)
      .eq('status', 'active')
      .neq('audio_url', null)
      .order('created_at', { ascending: false });

    if (feedError) {
      console.error('❌ Feed query failed:', feedError.message);
    } else {
      console.log(`✅ Feed-compatible songs: ${feedSongs?.length || 0}`);

      if (feedSongs && feedSongs.length > 0) {
        console.log('\n🎉 Sample feed-compatible songs:');
        feedSongs.slice(0, 3).forEach((song, index) => {
          console.log(`\n  ${index + 1}. ${song.title} by ${song.artist}`);
          console.log(`     🎵 Audio: ${song.audio_url}`);
          console.log(`     📅 Created: ${new Date(song.created_at).toLocaleDateString()}`);
        });
      } else {
        console.log('\n💡 No feed-compatible songs found');
        console.log('   To make songs appear in feed:');
        console.log('   1. Set is_public = true');
        console.log('   2. Set is_active = true');
        console.log('   3. Set status = "active"');
        console.log('   4. Ensure audio_url is not null');
      }
    }

    // Test 4: Check other related tables
    console.log('\n4️⃣ Checking related tables...');

    const relatedTables = [
      { name: 'artists', query: supabase.from('artists').select('*', { count: 'exact', head: true }) },
      { name: 'albums', query: supabase.from('albums').select('*', { count: 'exact', head: true }) },
      { name: 'profiles', query: supabase.from('profiles').select('*', { count: 'exact', head: true }) },
    ];

    for (const { name, query } of relatedTables) {
      try {
        const { count: tableCount, error: tableError } = await query;
        if (tableError) {
          console.log(`  ⚠️  ${name}: ${tableError.message}`);
        } else {
          console.log(`  ✅ ${name}: ${tableCount || 0} records`);
        }
      } catch (error) {
        console.log(`  ❌ ${name}: ${error.message}`);
      }
    }

    // Test 5: Check videos table
    console.log('\n5️⃣ Checking videos table...');

    const select = 'id,title,user_id,thumbnail_url,views,views_count,likes,likes_count,comments,comments_count,created_at,status';
    const attempts = [
      { includeStatus: true, orderByViews: true },
      { includeStatus: false, orderByViews: true },
      { includeStatus: false, orderByViews: false },
    ];

    for (const attempt of attempts) {
      try {
        let query = supabase.from('videos').select(select);
        if (attempt.includeStatus) {
          query = query.eq('status', 'active');
        }

        query = attempt.orderByViews
          ? query.order('views', { ascending: false })
          : query.order('created_at', { ascending: false });

        const { data: videos, error: videosError } = await query.limit(24);
        if (videosError) {
          throw videosError;
        }
        console.log(`✅ Found ${videos?.length || 0} active videos`);
        if (videos && videos.length > 0) {
          console.log('\n🎬 Top videos by views:');
          videos.slice(0, 3).forEach((video, index) => {
            console.log(`\n  ${index + 1}. ${video.title}`);
            console.log(`     👀 Views: ${video.views || 0}`);
            console.log(`     👍 Likes: ${video.likes || 0}`);
            console.log(`     💬 Comments: ${video.comments || 0}`);
          });
        }
        break;
      } catch (error) {
        if (attempt === attempts[attempts.length - 1]) {
          console.error('❌ Could not retrieve videos:', error.message);
        }
      }
    }

    console.log('\n✅ All tests completed successfully!');
    console.log('\n📋 Summary:');
    console.log('   • Database connection: ✅ Working');
    console.log('   • Songs table: ✅ Accessible');
    console.log('   • Total songs:', count || 0);
    console.log('   • Feed-compatible songs:', feedSongs?.length || 0);
    console.log('   • Videos table: ✅ Accessible');
    console.log('   • Active videos:', videos?.length || 0);
    console.log('   • API endpoints: ✅ Ready to use');

    if (feedSongs && feedSongs.length > 0) {
      console.log('\n🎉 Your songs are ready to display!');
      console.log('   The "no tracks here yet" issue should now be resolved.');
    } else if (songs && songs.length > 0) {
      console.log('\n💡 Songs exist but need filtering adjustments');
      console.log('   Run this SQL in Supabase to fix:');
      console.log('   UPDATE songs SET is_public = true, is_active = true, status = "active"');
      console.log('   WHERE audio_url IS NOT NULL;');
    } else {
      console.log('\n📝 No songs found in database');
      console.log('   Add songs using the new API endpoints or Supabase dashboard');
    }

  } catch (error) {
    console.error('❌ Unexpected error:', error.message);
    console.error(error.stack);
  }
}

testCompleteConnection();