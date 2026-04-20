// Load environment variables
require('dotenv').config();

const express = require('express');
const { createClient } = require('@supabase/supabase-js');

const app = express();
try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_KEY;

    // Verify Supabase credentials
    if (!supabaseUrl || !supabaseKey) {
        console.error('Error: Supabase URL and Key are required. Check your .env file.');
        process.exit(1);
    }

    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log('Supabase client initialized successfully');

    // Endpoint to fetch hot videos
    app.get('/api/feed/global', async (req, res) => {
        try {
            console.log('Fetching videos from Supabase...');
            const { data, error } = await supabase
                .from('videos')
                .select('id, title, user_id, thumbnail_url, views, likes_count, created_at, status')
                .eq('status', 'active')
                .order('views', { ascending: false })
                .limit(10);

            if (error) {
                console.error('Supabase error:', error);
                return res.status(500).json({ error: error.message });
            }

            console.log('Videos fetched successfully:', data.length, 'videos found');
            res.json(data);
        } catch (err) {
            console.error('Server error:', err);
            res.status(500).json({ error: 'Internal server error' });
        }
    });

    const PORT = process.env.PORT || 3000;
    app.listen(PORT, () => {
        console.log(`Server running on port ${PORT}`);
    });
} catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
}
