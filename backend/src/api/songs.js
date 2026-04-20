const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const { authenticate } = require('../middleware/auth');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

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