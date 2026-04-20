const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { createClient } = require('@supabase/supabase-js');
const { authenticate } = require('../middleware/auth');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Register user
router.post('/register', async (req, res) => {
  try {
    const { email, password, username, displayName } = req.body;

    // Hash password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    // Create user in Supabase Auth
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email,
      password,
    });

    if (authError) throw authError;

    // Create user profile
    const { data: userData, error: userError } = await supabase
      .from('users')
      .insert({
        id: authData.user.id,
        email,
        username,
        display_name: displayName,
        created_at: new Date()
      })
      .select()
      .single();

    if (userError) throw userError;

    // Create wallet
    await supabase
      .from('wallets')
      .insert({
        user_id: authData.user.id,
        coin_balance: 0
      });

    // Generate JWT
    const token = jwt.sign(
      { userId: authData.user.id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.json({
      user: userData,
      token
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Login user
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    // Sign in with Supabase Auth
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (authError) throw authError;

    // Get user profile
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('*')
      .eq('id', authData.user.id)
      .single();

    if (userError) throw userError;

    // Generate JWT
    const token = jwt.sign(
      { userId: authData.user.id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.json({
      user: userData,
      token
    });
  } catch (error) {
    res.status(401).json({ error: 'Invalid credentials' });
  }
});

// Get current user
router.get('/me', authenticate, async (req, res) => {
  try {
    const { data: user, error } = await supabase
      .from('users')
      .select(`
        *,
        wallets(*)
      `)
      .eq('id', req.user.id)
      .single();

    if (error) throw error;
    res.json(user);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Refresh token
router.post('/refresh', authenticate, async (req, res) => {
  try {
    const token = jwt.sign(
      { userId: req.user.id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.json({ token });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Logout
router.post('/logout', authenticate, async (req, res) => {
  try {
    await supabase.auth.signOut();
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Request password reset
router.post('/reset-password', async (req, res) => {
  try {
    const { email } = req.body;

    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${process.env.FRONTEND_URL}/reset-password`,
    });

    if (error) throw error;
    res.json({ message: 'Password reset email sent' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;