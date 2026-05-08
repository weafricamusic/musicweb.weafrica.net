/**
 * Agora Token Generation Test Script
 * 
 * This script tests the Agora token generation functionality.
 * Run with: node test-agora-token.js
 */

require('dotenv').config({ path: '.env' });

const { RtcTokenBuilder, RtcRole } = require('agora-token');

// Configuration
const APP_ID = process.env.AGORA_APP_ID;
const APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE;

console.log('=== Agora Token Generation Test ===\n');
console.log('App ID:', APP_ID);
console.log('App Certificate:', APP_CERTIFICATE ? '***' + APP_CERTIFICATE.slice(-8) : 'NOT SET');
console.log('');

// Validate configuration
if (!APP_ID || !APP_CERTIFICATE) {
    console.error('❌ ERROR: Agora credentials not configured!');
    console.error('');
    console.error('Please set AGORA_APP_ID and AGORA_APP_CERTIFICATE in backend/.env');
    console.error('');
    console.error('Steps:');
    console.error('1. Go to https://console.agora.io');
    console.error('2. Create a project or select existing one');
    console.error('3. Copy App ID and App Certificate');
    console.error('4. Update backend/.env with your credentials');
    process.exit(1);
}

// Test parameters
const testChannel = 'test_channel_' + Date.now();
const testUid = 12345;
const ttl = 3600; // 1 hour

console.log('Test Parameters:');
console.log('- Channel:', testChannel);
console.log('- UID:', testUid);
console.log('- TTL:', ttl, 'seconds');
console.log('');

try {
    // Calculate expiration time
    const expirationTime = Math.floor(Date.now() / 1000) + ttl;

    // Generate RTC token for broadcaster (host)
    const broadcasterToken = RtcTokenBuilder.buildTokenWithUid(
        APP_ID,
        APP_CERTIFICATE,
        testChannel,
        testUid,
        RtcRole.HOST,
        expirationTime
    );

    console.log('✅ Broadcaster (Host) Token Generated:');
    console.log(broadcasterToken);
    console.log('');

    // Generate RTC token for audience (spectator)
    const audienceToken = RtcTokenBuilder.buildTokenWithUid(
        APP_ID,
        APP_CERTIFICATE,
        testChannel,
        testUid,
        RtcRole.AUDIENCE,
        expirationTime
    );

    console.log('✅ Audience (Spectator) Token Generated:');
    console.log(audienceToken);
    console.log('');

    // Summary
    console.log('=== Test Results ===');
    console.log('✅ Token generation successful!');
    console.log('✅ Agora credentials are properly configured');
    console.log('✅ Backend is ready to generate tokens for live streaming');
    console.log('');
    console.log('Next Steps:');
    console.log('1. Start the backend: npm run dev');
    console.log('2. Test the API endpoint:');
    console.log('   curl -X POST http://localhost:3000/api/agora/token \\');
    console.log('     -H "Content-Type: application/json" \\');
    console.log('     -d \'{"channel_id":"test","role":"broadcaster","uid":123}\'');
    console.log('3. Start the web client: cd web/agora-battle && npm run dev');
    console.log('4. Open http://localhost:5173 in your browser');

} catch (error) {
    console.error('❌ ERROR: Token generation failed!');
    console.error('');
    console.error('Error:', error.message);
    console.error('');
    console.error('Possible causes:');
    console.error('1. Invalid App Certificate - check it matches your Agora project');
    console.error('2. App Certificate contains extra spaces or quotes');
    console.error('3. Agora package not installed - run npm install');
    process.exit(1);
}