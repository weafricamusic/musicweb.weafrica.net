/**
 * Test script for Agora Token API endpoint
 * 
 * This script tests the new /api/agora/token endpoint
 * to ensure artists can create live streams and consumers can join.
 */

const axios = require('axios');

const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3000';

// Test configuration
const TEST_CONFIG = {
    channel_id: 'test_live_channel_123',
    artist_uid: 1001,
    consumer_uid: 2001,
};

async function testArtistToken() {
    console.log('\n🎤 Testing Artist (Broadcaster) Token Generation...');

    try {
        const response = await axios.post(`${BASE_URL}/agora/token`, {
            channel_id: TEST_CONFIG.channel_id,
            role: 'broadcaster',
            uid: TEST_CONFIG.artist_uid,
            ttl_seconds: 3600,
        });

        console.log('✅ Artist token generated successfully!');
        console.log('   Token:', response.data.token.substring(0, 50) + '...');
        console.log('   App ID:', response.data.app_id);
        console.log('   Channel:', response.data.channel_id);
        console.log('   UID:', response.data.uid);
        console.log('   Role:', response.data.role);
        console.log('   Expires In:', response.data.expires_in, 'seconds');

        return response.data;
    } catch (error) {
        console.log('❌ Failed to generate artist token');
        if (error.response) {
            console.log('   Status:', error.response.status);
            console.log('   Data:', JSON.stringify(error.response.data, null, 2));
        } else {
            console.log('   Error:', error.message);
        }
        return null;
    }
}

async function testConsumerToken() {
    console.log('\n👥 Testing Consumer (Audience) Token Generation...');

    try {
        const response = await axios.post(`${BASE_URL}/agora/token`, {
            channel_id: TEST_CONFIG.channel_id,
            role: 'audience',
            uid: TEST_CONFIG.consumer_uid,
            ttl_seconds: 3600,
        });

        console.log('✅ Consumer token generated successfully!');
        console.log('   Token:', response.data.token.substring(0, 50) + '...');
        console.log('   App ID:', response.data.app_id);
        console.log('   Channel:', response.data.channel_id);
        console.log('   UID:', response.data.uid);
        console.log('   Role:', response.data.role);
        console.log('   Expires In:', response.data.expires_in, 'seconds');

        return response.data;
    } catch (error) {
        console.log('❌ Failed to generate consumer token');
        if (error.response) {
            console.log('   Status:', error.response.status);
            console.log('   Data:', JSON.stringify(error.response.data, null, 2));
        } else {
            console.log('   Error:', error.message);
        }
        return null;
    }
}

async function testValidationErrors() {
    console.log('\n🔍 Testing Input Validation...');

    const testCases = [
        {
            name: 'Missing channel_id',
            data: { role: 'audience', uid: 123 },
            expectedStatus: 400,
        },
        {
            name: 'Missing role',
            data: { channel_id: 'test', uid: 123 },
            expectedStatus: 400,
        },
        {
            name: 'Invalid role',
            data: { channel_id: 'test', role: 'invalid', uid: 123 },
            expectedStatus: 400,
        },
        {
            name: 'Missing uid',
            data: { channel_id: 'test', role: 'audience' },
            expectedStatus: 400,
        },
    ];

    let passed = 0;
    let failed = 0;

    for (const testCase of testCases) {
        try {
            await axios.post(`${BASE_URL}/agora/token`, testCase.data);
            console.log(`❌ ${testCase.name}: Expected error but got success`);
            failed++;
        } catch (error) {
            if (error.response && error.response.status === testCase.expectedStatus) {
                console.log(`✅ ${testCase.name}: Correctly rejected with ${testCase.expectedStatus}`);
                passed++;
            } else {
                console.log(`❌ ${testCase.name}: Expected ${testCase.expectedStatus} but got ${error.response?.status || error.message}`);
                failed++;
            }
        }
    }

    console.log(`\n   Validation tests: ${passed} passed, ${failed} failed`);
}

async function testConfigEndpoint() {
    console.log('\n⚙️ Testing Config Endpoint...');

    try {
        const response = await axios.post(`${BASE_URL}/agora/config`);
        console.log('✅ Config endpoint responding');
        console.log('   App ID:', response.data.app_id ? 'Configured' : 'Not configured');
        console.log('   Configured:', response.data.configured);

        return response.data;
    } catch (error) {
        console.log('❌ Failed to get config');
        if (error.response) {
            console.log('   Status:', error.response.status);
        } else {
            console.log('   Error:', error.message);
        }
        return null;
    }
}

async function runAllTests() {
    console.log('🚀 Starting Agora Token API Tests...');
    console.log('   Base URL:', BASE_URL);

    // Test config first
    const config = await testConfigEndpoint();

    if (!config?.configured) {
        console.log('\n⚠️  WARNING: Agora is not configured. Token generation will fail.');
        console.log('   Set AGORA_APP_ID and AGORA_APP_CERTIFICATE environment variables.');
        return;
    }

    // Test token generation
    const artistToken = await testArtistToken();
    const consumerToken = await testConsumerToken();

    // Test validation
    await testValidationErrors();

    // Summary
    console.log('\n' + '='.repeat(50));
    console.log('📊 Test Summary');
    console.log('='.repeat(50));

    if (artistToken && consumerToken) {
        console.log('✅ All token generation tests passed!');
        console.log('\n🎯 Next Steps:');
        console.log('   1. Start Flutter app: flutter run');
        console.log('   2. Login as artist and go live');
        console.log('   3. Login as consumer and join live stream');
        console.log('   4. Verify video/audio is working');
    } else {
        console.log('❌ Some tests failed. Check the errors above.');
    }

    console.log('\n📝 Test Channel ID:', TEST_CONFIG.channel_id);
    console.log('   Artist UID:', TEST_CONFIG.artist_uid);
    console.log('   Consumer UID:', TEST_CONFIG.consumer_uid);
}

// Run tests
runAllTests().catch(console.error);