const { createClient } = require('@supabase/supabase-js');
const path = require('path');
const fs = require('fs');

// Try to load environment from supabase directory
try {
  const envPath = path.join(__dirname, 'supabase', '.env.local');
  if (fs.existsSync(envPath)) {
    require('dotenv').config({ path: envPath });
    console.log('✅ Loaded environment from supabase/.env.local');
  }
} catch (e) {
  console.log('ℹ️ Could not load supabase/.env.local directly');
}

// Also try backend .env
try {
  const envPath = path.join(__dirname, 'backend', '.env');
  if (fs.existsSync(envPath)) {
    require('dotenv').config({ path: envPath });
    console.log('✅ Loaded environment from backend/.env');
  }
} catch (e) {
  console.log('ℹ️ Could not load backend/.env');
}

// Try root .env
try {
  require('dotenv').config();
  console.log('✅ Loaded environment from root .env');
} catch (e) {
  console.log('ℹ️ Could not load root .env');
}

const supabaseUrl = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

console.log('\n🔍 Supabase Configuration:');
console.log('SUPABASE_URL:', supabaseUrl ? '✅ Set' : '❌ Not set');
console.log('SUPABASE_SERVICE_KEY:', supabaseKey ? '✅ Set' : '❌ Not set');

if (!supabaseUrl || !supabaseKey) {
  console.error('\n❌ Cannot test without Supabase credentials');
  console.error('💡 Solution: Make sure your environment variables are properly set');
  console.error('   - Check supabase/.env.local');
  console.error('   - Check backend/.env');
  console.error('   - Or set environment variables directly');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testSongs() {
  console.log('\n🎵 Testing Songs Connection...');
  
  try {
    // Test 1: Basic connectivity
    console.log('\n1️⃣ Testing basic database connectivity...');
    const { data: health, error: healthError } = await supabase
      .from('songs')
      .select('count', { head: true, count: 'exact' });
    
    if (healthError) {
      console.error('❌ Database connection failed:', healthError.message);
      return;
    }
    
    console.log('✅ Database connection successful!');
    console.log('📊 Total songs in database:', health?.count || 0);
    
    // Test 2: Get sample songs with different filters
    console.log('\n2️⃣ Testing song retrieval with different filters...');
    
    const filterTests = [
      { name: 'All songs', filter: {} },
      { name: 'Public songs', filter: { is_public: true } },
      { name: 'Active songs', filter: { is_active: true } },
      { name: 'Active status', filter: { status: 'active' } },
      { name: 'Approved songs', filter: { approved: true } },
      { name: 'Published songs', filter: { is_published: true } },
    ];
    
    for (const { name, filter } of filterTests) {
      try {
        let query = supabase.from('songs').select('*', { count: 'exact', head: true });
        
        for (const [key, value] of Object.entries(filter)) {
          query = query.eq(key, value);
        }
        
        const { count, error } = await query;
        
        if (error) {
          console.log(`  ⚠️  ${name}: ${error.message}`);
        } else {
          console.log(`  ✅ ${name}: ${count || 0} songs`);
        }
      } catch (error) {
        console.log(`  ❌ ${name}: ${error.message}`);
      }
    }
    
    // Test 3: Get actual song data
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
        console.log(`    Created: ${song.created_at || 'Unknown'}`);
      });
    } else {
      console.log('ℹ️ No songs found in database');
    }
    
    // Test 4: Check if songs meet feed requirements
    console.log('\n4️⃣ Checking feed compatibility...');
    
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
      
      if (feedSongs && feedSongs.length === 0) {
        console.log('\n💡 If you have songs but none are feed-compatible:');
        console.log('   1. Set is_public = true');
        console.log('   2. Set is_active = true');
        console.log('   3. Set status = "active"');
        console.log('   4. Ensure audio_url is not null');
      }
    }
    
    console.log('\n✅ Test completed!');
    
  } catch (error) {
    console.error('❌ Unexpected error:', error.message);
    console.error(error.stack);
  }
}

testSongs();