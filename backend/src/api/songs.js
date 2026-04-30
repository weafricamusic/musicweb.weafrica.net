const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const { authenticate } = require('../middleware/auth');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// POST /api/songs/create - Create a draft song entry (returns song_id)
// This is the first step in the two-step upload flow
router.post('/create', authenticate, async (req, res) => {
  try {
    const {
      title,
      caption,
      artist,
      genre,
      country,
      language,
      category,
      album_id,
      audio_url,
      audio_bucket,
      audio_path,
      artwork_url,
      artwork_bucket,
      artwork_path,
      thumbnail_url,
      thumbnail_bucket,
      thumbnail_path,
      video_url,
      video_bucket,
      video_path,
      file_path,
      publish = false
    } = req.body;

    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

    // Determine if this is a song or video based on presence of audio_url or video_url
    const isSong = !!audio_url;

    const songData = {
      title: title.trim(),
      artist: artist?.trim() || null,
      artist_id: req.body.artist_id || null,
      genre: genre?.trim() || null,
      country: country?.trim() || null,
      language: language?.trim() || null,
      caption: caption?.trim() || null,
      category: category?.trim() || null,
      album_id: album_id?.trim() || null,
      audio_url: audio_url || null,
      artwork_url: artwork_url || thumbnail_url || null,
      video_url: video_url || null,
      user_id: req.user.id,
      is_public: publish || false,
      is_active: true,
      approved: false, // Needs moderation before public
      is_published: publish || false,
      status: 'draft',
      audio_bucket: audio_bucket || null,
      audio_path: audio_path || file_path || null,
      artwork_bucket: artwork_bucket || thumbnail_bucket || null,
      artwork_path: artwork_path || thumbnail_path || null,
      video_bucket: video_bucket || null,
      video_path: video_path || null,
    };

    const { data, error } = await supabase
      .from('songs')
      .insert(songData)
      .select('id')
      .single();

    if (error) throw error;

    res.status(201).json({
      song_id: data.id,
      message: 'Draft created successfully'
    });
  } catch (error) {
    console.error('Error creating song draft:', error);
    res.status(400).json({ error: error.message });
  }
});

// POST /api/songs/finalize - Finalize and publish a song after upload completes
// This is the second step in the two-step upload flow
router.post('/finalize', authenticate, async (req, res) => {
  try {
    const {
      song_id,
      audio_url,
      artwork_url,
      thumbnail_url,
      file_path,
      audio_bucket,
      audio_path,
      artwork_bucket,
      artwork_path,
      video_url,
      video_bucket,
      video_path
    } = req.body;

    if (!song_id) {
      return res.status(400).json({ error: 'song_id is required' });
    }

    // Check if user owns this song
    const { data: existingSong, error: fetchError } = await supabase
      .from('songs')
      .select('user_id, id')
      .eq('id', song_id)
      .single();

    if (fetchError) throw fetchError;
    if (!existingSong) {
      return res.status(404).json({ error: 'Song not found' });
    }
    if (existingSong.user_id !== req.user.id) {
      return res.status(403).json({ error: 'You can only finalize your own songs' });
    }

    // Update the song with final URLs and mark as published
    const updateData = {
      audio_url: audio_url || null,
      artwork_url: artwork_url || thumbnail_url || null,
      video_url: video_url || null,
      audio_bucket: audio_bucket || null,
      audio_path: audio_path || file_path || null,
      artwork_bucket: artwork_bucket || null,
      artwork_path: artwork_path || null,
      video_bucket: video_bucket || null,
      video_path: video_path || null,
      is_public: true,
      is_active: true,
      is_published: true,
      status: 'active',
      approved: false, // Still needs moderation
      updated_at: new Date().toISOString()
    };

    const { data, error } = await supabase
      .from('songs')
      .update(updateData)
      .eq('id', song_id)
      .select('id')
      .single();

    if (error) throw error;

    res.json({
      song_id: data.id,
      message: 'Song finalized successfully'
    });
  } catch (error) {
    console.error('Error finalizing song:', error);
    res.status(400).json({ error: error.message });
  }
});

// POST /api/videos/create - Create a draft video entry (returns video_id)
router.post('/videos/create', authenticate, async (req, res) => {
  // Delegate to songs/create - they use the same table
  // Just redirect the response format
  try {
    const {
      title,
      caption,
      category,
      album_id,
      video_url,
      video_bucket,
      video_path,
      thumbnail_url,
      thumbnail_bucket,
      thumbnail_path,
      file_path,
      publish = false
    } = req.body;

    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

    const songData = {
      title: title.trim(),
      caption: caption?.trim() || null,
      category: category?.trim() || null,
      album_id: album_id?.trim() || null,
      video_url: video_url || null,
      artwork_url: thumbnail_url || null,
      user_id: req.user.id,
      is_public: publish || false,
      is_active: true,
      approved: false,
      is_published: publish || false,
      status: 'draft',
      video_bucket: video_bucket || null,
      video_path: video_path || file_path || null,
      artwork_bucket: thumbnail_bucket || null,
      artwork_path: thumbnail_path || null,
    };

    const { data, error } = await supabase
      .from('songs')
      .insert(songData)
      .select('id')
      .single();

    if (error) throw error;

    res.status(201).json({
      video_id: data.id,
      song_id: data.id, // Also return as song_id for compatibility
      message: 'Video draft created successfully'
    });
  } catch (error) {
    console.error('Error creating video draft:', error);
    res.status(400).json({ error: error.message });
  }
});

// POST /api/videos/finalize - Finalize and publish a video after upload completes
router.post('/videos/finalize', authenticate, async (req, res) => {
  try {
    const {
      video_id,
      song_id,
      video_url,
      thumbnail_url,
      file_path,
      video_bucket,
      video_path,
      thumbnail_bucket,
      thumbnail_path
    } = req.body;

    const id = video_id || song_id;
    if (!id) {
      return res.status(400).json({ error: 'video_id or song_id is required' });
    }

    // Check if user owns this video
    const { data: existingSong, error: fetchError } = await supabase
      .from('songs')
      .select('user_id, id')
      .eq('id', id)
      .single();

    if (fetchError) throw fetchError;
    if (!existingSong) {
      return res.status(404).json({ error: 'Video not found' });
    }
    if (existingSong.user_id !== req.user.id) {
      return res.status(403).json({ error: 'You can only finalize your own videos' });
    }

    const updateData = {
      video_url: video_url || null,
      artwork_url: thumbnail_url || null,
      video_bucket: video_bucket || null,
      video_path: video_path || file_path || null,
      artwork_bucket: thumbnail_bucket || null,
      artwork_path: thumbnail_path || null,
      is_public: true,
      is_active: true,
      is_published: true,
      status: 'active',
      approved: false,
      updated_at: new Date().toISOString()
    };

    const { data, error } = await supabase
      .from('songs')
      .update(updateData)
      .eq('id', id)
      .select('id')
      .single();

    if (error) throw error;

    res.json({
      video_id: data.id,
      song_id: data.id,
      message: 'Video finalized successfully'
    });
  } catch (error) {
    console.error('Error finalizing video:', error);
    res.status(400).json({ error: error.message });
  }
});

// Get all songs (public)
router.get('/', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('songs')
      .select('*')
      .eq('is_public', true)
      .eq('is_active', true)
      .eq('status', 'active')
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get songs by artist
router.get('/artist/:artistId', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('songs')
      .select('*')
      .eq('artist_id', req.params.artistId)
      .eq('is_public', true)
      .eq('is_active', true)
      .eq('status', 'active')
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get songs by user (authenticated)
router.get('/my-songs', authenticate, async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('songs')
      .select('*')
      .eq('user_id', req.user.id)
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get song by ID
router.get('/:songId', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('songs')
      .select('*')
      .eq('id', req.params.songId)
      .eq('is_public', true)
      .eq('is_active', true)
      .eq('status', 'active')
      .maybeSingle();

    if (error) throw error;
    if (!data) {
      return res.status(404).json({ error: 'Song not found' });
    }
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create a new song (authenticated)
router.post('/', authenticate, async (req, res) => {
  try {
    const songData = {
      title: req.body.title,
      artist: req.body.artist,
      artist_id: req.body.artist_id,
      genre: req.body.genre,
      country: req.body.country,
      language: req.body.language,
      audio_url: req.body.audio_url,
      artwork_url: req.body.artwork_url,
      user_id: req.user.id,
      album_id: req.body.album_id,
      is_public: req.body.is_public || false,
      is_active: req.body.is_active || true,
      approved: req.body.approved || false,
      is_published: req.body.is_published || false,
      status: req.body.status || 'active'
    };

    const { data, error } = await supabase
      .from('songs')
      .insert(songData)
      .select()
      .single();

    if (error) throw error;
    res.status(201).json(data);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Update a song (authenticated)
router.put('/:songId', authenticate, async (req, res) => {
  try {
    // Check if user owns the song
    const { data: existingSong, error: fetchError } = await supabase
      .from('songs')
      .select('user_id')
      .eq('id', req.params.songId)
      .maybeSingle();

    if (fetchError) throw fetchError;
    if (!existingSong) {
      return res.status(404).json({ error: 'Song not found' });
    }
    if (existingSong.user_id !== req.user.id) {
      return res.status(403).json({ error: 'You can only update your own songs' });
    }

    const updateData = {
      title: req.body.title,
      artist: req.body.artist,
      artist_id: req.body.artist_id,
      genre: req.body.genre,
      country: req.body.country,
      language: req.body.language,
      audio_url: req.body.audio_url,
      artwork_url: req.body.artwork_url,
      album_id: req.body.album_id,
      is_public: req.body.is_public,
      is_active: req.body.is_active,
      approved: req.body.approved,
      is_published: req.body.is_published,
      status: req.body.status,
      updated_at: new Date().toISOString()
    };

    const { data, error } = await supabase
      .from('songs')
      .update(updateData)
      .eq('id', req.params.songId)
      .select()
      .single();

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Delete a song (authenticated)
router.delete('/:songId', authenticate, async (req, res) => {
  try {
    // Check if user owns the song
    const { data: existingSong, error: fetchError } = await supabase
      .from('songs')
      .select('user_id')
      .eq('id', req.params.songId)
      .maybeSingle();

    if (fetchError) throw fetchError;
    if (!existingSong) {
      return res.status(404).json({ error: 'Song not found' });
    }
    if (existingSong.user_id !== req.user.id) {
      return res.status(403).json({ error: 'You can only delete your own songs' });
    }

    const { error } = await supabase
      .from('songs')
      .delete()
      .eq('id', req.params.songId);

    if (error) throw error;
    res.json({ success: true });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Search songs
router.get('/search/:query', async (req, res) => {
  try {
    const searchQuery = req.params.query;
    const { data, error } = await supabase
      .from('songs')
      .select('*')
      .eq('is_public', true)
      .eq('is_active', true)
      .eq('status', 'active')
      .or(`title.ilike.%${searchQuery}%,artist.ilike.%${searchQuery}%`)
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;