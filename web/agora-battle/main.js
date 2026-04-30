/**
 * WeAfrica Music Battle - Agora RTC Web SDK NG Integration
 * 
 * This module handles real-time audio/video communication for interactive battles.
 * Uses Agora Web SDK NG (agora-rtc-sdk-ng) in live mode for broadcast-style communication.
 * 
 * Architecture:
 * - Players (hosts): Publish audio/video, can interact
 * - Spectators (audience): Subscribe only, watch the battle
 * - RTM: Used for game events, chat, and reliable signaling
 */

import AgoraRTC from 'agora-rtc-sdk-ng';

// ============================================================================
// Configuration
// ============================================================================

// API base URL - adjust based on your deployment
const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000';

// Agora App ID (safe to expose client-side)
const AGORA_APP_ID = import.meta.env.VITE_AGORA_APP_ID || '21a9549ec323484ca5983aadbd3839af';

// ============================================================================
// State Management
// ============================================================================

const state = {
    // Agora clients
    rtcClient: null,
    rtmClient: null,
    rtmChannel: null,

    // Local tracks
    localAudioTrack: null,
    localVideoTrack: null,

    // Connection state
    isConnected: false,
    currentChannel: null,
    currentRole: 'host', // 'host' or 'audience'
    uid: null,

    // Participants tracking
    participants: new Map(),

    // Remote video elements tracking
    remoteContainers: new Map(),
};

// ============================================================================
// UI Helper Functions
// ============================================================================

function updateStatus(connected, message = '') {
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');
    if (!statusDot || !statusText) return;

    if (connected) {
        statusDot.className = 'status-dot connected';
        statusText.textContent = message || 'Connected';
    } else {
        statusDot.className = 'status-dot disconnected';
        statusText.textContent = message || 'Disconnected';
    }
}

function addChatMessage(sender, message, type = 'chat') {
    const chatMessages = document.getElementById('chatMessages');
    if (!chatMessages) {
        console.log(`[${sender}] ${message}`);
        return;
    }

    const messageEl = document.createElement('div');
    messageEl.className = 'chat-message';

    const time = new Date().toLocaleTimeString();
    const senderClass = type === 'system' ? 'system' : 'sender';
    const senderLabel = type === 'system' ? '🔔 System' : sender;

    messageEl.innerHTML = `
    <span class="${senderClass}">${senderLabel}:</span>
    <span class="text">${message}</span>
    <span class="time">${time}</span>
  `;

    chatMessages.appendChild(messageEl);
    chatMessages.scrollTop = chatMessages.scrollHeight;
}

function updateParticipantCount(count) {
    const el = document.getElementById('participantCount');
    if (el) el.textContent = count;
}

function updateBattleStatus(status) {
    const el = document.getElementById('battleStatus');
    if (el) el.textContent = status;
}

function addParticipant(uid, role = 'audience') {
    state.participants.set(uid, { role, joinedAt: Date.now() });

    const list = document.getElementById('participantsList');
    if (!list) return;

    const participantEl = document.createElement('div');
    participantEl.className = `participant ${role}`;
    participantEl.id = `participant-${uid}`;
    participantEl.innerHTML = `
    <span class="role-icon">${role === 'host' ? '🎤' : '👁'}</span>
    <span class="name">User ${uid}</span>
    <span class="role-label">${role === 'host' ? 'Player' : 'Spectator'}</span>
  `;
    list.appendChild(participantEl);
    updateParticipantCount(state.participants.size);
}

function removeParticipant(uid) {
    state.participants.delete(uid);
    const el = document.getElementById(`participant-${uid}`);
    if (el) el.remove();
    updateParticipantCount(state.participants.size);
}

function clearParticipants() {
    state.participants.clear();
    const list = document.getElementById('participantsList');
    if (list) list.innerHTML = '';
    updateParticipantCount(0);
}

// ============================================================================
// Role Management
// ============================================================================

function setRole(role) {
    state.currentRole = role;

    // Update UI
    document.querySelectorAll('.role-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.role === role);
    });

    addChatMessage('System', `Role changed to: ${role === 'host' ? 'Player (Host)' : 'Spectator'}`, 'system');
}

// Make setRole available globally for HTML onclick
window.setRole = setRole;

// ============================================================================
// Token Generation
// ============================================================================

async function getTokens(channelName, role = 'host') {
    try {
        const response = await fetch(`${API_BASE_URL}/agora/token`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                channel_id: channelName,
                role: role === 'host' ? 'broadcaster' : 'audience',
                uid: null, // Let backend generate UID
                ttl_seconds: 3600,
            }),
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Token request failed: ${response.status} ${response.statusText} - ${errorText}`);
        }

        const data = await response.json();
        if (!data.token) {
            throw new Error('Invalid token response from server');
        }
        return {
            rtcToken: data.token,
            rtmToken: data.token, // For simplicity, using same token
        };
    } catch (error) {
        console.error('Error fetching tokens:', error);
        addChatMessage('System', `Token error: ${error.message}`, 'system');
        throw error;
    }
}

// ============================================================================
// Agora RTC Client Management
// ============================================================================

async function initRTCClient() {
    if (state.rtcClient) {
        return state.rtcClient;
    }

    // Create client in live mode for broadcast-style communication
    state.rtcClient = AgoraRTC.createClient({
        mode: 'live',
        codec: 'vp8',
    });

    // Set up event handlers
    state.rtcClient.on('user-published', handleUserPublished);
    state.rtcClient.on('user-unpublished', handleUserUnpublished);
    state.rtcClient.on('user-joined', handleUserJoined);
    state.rtcClient.on('user-left', handleUserLeft);
    state.rtcClient.on('token-privilege-will-expire', handleTokenExpire);
    state.rtcClient.on('connection-state-changed', handleConnectionStateChange);

    return state.rtcClient;
}

async function handleJoin() {
    const channelInput = document.getElementById('channelInput');
    const channelName = channelInput.value.trim();

    if (!channelName) {
        addChatMessage('System', 'Please enter a channel name', 'system');
        return;
    }

    if (state.isConnected) {
        await handleLeave();
    }

    try {
        addChatMessage('System', `Joining channel: ${channelName} as ${state.currentRole}...`, 'system');
        updateStatus(false, 'Connecting...');

        // Get tokens from backend
        const tokens = await getTokens(channelName, state.currentRole);
        const rtcToken = tokens.rtcToken;
        const rtmToken = tokens.rtmToken;

        // Initialize RTC client
        await initRTCClient();

        // Join the channel
        state.uid = await state.rtcClient.join(
            AGORA_APP_ID,
            channelName,
            rtcToken,
            null // Let Agora assign UID
        );

        state.currentChannel = channelName;
        addChatMessage('System', `Joined channel as UID: ${state.uid}`, 'system');

        // Set client role
        await state.rtcClient.setClientRole(state.currentRole);

        if (state.currentRole === 'host') {
            // Create and publish local tracks
            await publishLocalTracks();
        }

        // Initialize RTM for chat and game events
        await initRTMClient(rtmToken, channelName);

        // Update UI
        state.isConnected = true;
        document.getElementById('joinBtn').disabled = true;
        document.getElementById('leaveBtn').disabled = false;
        document.getElementById('channelInput').disabled = true;
        updateStatus(true, `Channel: ${channelName}`);
        addChatMessage('System', 'Successfully connected!', 'system');

        // Add self to participants
        addParticipant(state.uid, state.currentRole);

    } catch (error) {
        console.error('Error joining channel:', error);
        addChatMessage('System', `Error: ${error.message}`, 'system');
        updateStatus(false, 'Connection failed');
        await cleanup();
    }
}

async function handleLeave() {
    if (!state.isConnected) return;

    try {
        addChatMessage('System', 'Leaving channel...', 'system');

        // Leave RTM channel
        if (state.rtmChannel) {
            await state.rtmChannel.leave();
        }

        // Leave RTC client
        if (state.rtcClient) {
            await state.rtcClient.leave();
        }

        // Clean up local tracks
        await cleanupTracks();

        // Reset state
        state.isConnected = false;
        state.currentChannel = null;
        state.uid = null;
        clearParticipants();
        clearRemoteVideos();

        // Update UI
        document.getElementById('joinBtn').disabled = false;
        document.getElementById('leaveBtn').disabled = true;
        document.getElementById('channelInput').disabled = false;
        updateStatus(false, 'Disconnected');
        addChatMessage('System', 'Disconnected from channel', 'system');

    } catch (error) {
        console.error('Error leaving channel:', error);
        addChatMessage('System', `Error leaving: ${error.message}`, 'system');
    }
}

async function publishLocalTracks() {
    try {
        // Create local audio and video tracks
        state.localAudioTrack = await AgoraRTC.createMicrophoneAudioTrack();
        state.localVideoTrack = await AgoraRTC.createCameraVideoTrack();

        // Display local video
        const localContainer = document.getElementById('local-player');
        // Clear any existing video
        const existingVideo = localContainer.querySelector('video');
        if (existingVideo) existingVideo.remove();

        const videoContainer = document.createElement('div');
        videoContainer.id = `local-video-${state.uid}`;
        videoContainer.style.cssText = 'width: 100%; height: 100%;';
        localContainer.appendChild(videoContainer);

        state.localVideoTrack.play(videoContainer);

        // Publish tracks
        await state.rtcClient.publish([state.localAudioTrack, state.localVideoTrack]);
        addChatMessage('System', 'Published audio and video', 'system');

    } catch (error) {
        console.error('Error publishing local tracks:', error);
        addChatMessage('System', `Error publishing: ${error.message}`, 'system');
        throw error;
    }
}

// ============================================================================
// RTC Event Handlers
// ============================================================================

async function handleUserPublished(user, mediaType) {
    console.log('User published:', user.uid, mediaType);

    try {
        await state.rtcClient.subscribe(user, mediaType);
        addChatMessage('System', `User ${user.uid} published ${mediaType}`, 'system');

        if (mediaType === 'video' && user.videoTrack) {
            displayRemoteVideo(user);
        }

        if (mediaType === 'audio' && user.audioTrack) {
            user.audioTrack.play();
        }
    } catch (error) {
        console.error('Error subscribing to user:', error);
    }
}

function handleUserUnpublished(user) {
    console.log('User unpublished:', user.uid);
    const container = state.remoteContainers.get(user.uid);
    if (container) {
        container.remove();
        state.remoteContainers.delete(user.uid);
    }
    addChatMessage('System', `User ${user.uid} stopped publishing`, 'system');
}

function handleUserJoined(uid) {
    console.log('User joined:', uid);
    addChatMessage('System', `User ${uid} joined the channel`, 'system');
    addParticipant(uid, 'audience'); // Default to audience until we know their role
}

function handleUserLeft(uid) {
    console.log('User left:', uid);
    removeParticipant(uid);

    const container = state.remoteContainers.get(uid);
    if (container) {
        container.remove();
        state.remoteContainers.delete(uid);
    }

    addChatMessage('System', `User ${uid} left the channel`, 'system');
}

async function handleTokenExpire() {
    console.log('Token about to expire, requesting new token...');
    try {
        const tokens = await getTokens(state.currentChannel, state.currentRole);
        await state.rtcClient.renewToken(tokens.rtcToken);
        addChatMessage('System', 'Token renewed successfully', 'system');
    } catch (error) {
        console.error('Error renewing token:', error);
        addChatMessage('System', `Token renewal failed: ${error.message}`, 'system');
    }
}

function handleConnectionStateChange(connectionState, reason) {
    console.log('Connection state changed:', connectionState, reason);
    if (connectionState === 'DISCONNECTED') {
        updateStatus(false, 'Disconnected');
        addChatMessage('System', 'Connection lost', 'system');
    } else if (connectionState === 'CONNECTED') {
        updateStatus(true, `Channel: ${state.currentChannel}`);
        addChatMessage('System', 'Connection restored', 'system');
    }
}

// ============================================================================
// Remote Video Display
// ============================================================================

function displayRemoteVideo(user) {
    const remoteList = document.getElementById('remote-playerlist');

    // Check if container already exists
    if (state.remoteContainers.has(user.uid)) {
        return;
    }

    const container = document.createElement('div');
    container.className = 'remote-video-container';
    container.id = `remote-${user.uid}`;

    const videoDiv = document.createElement('div');
    videoDiv.id = `video-${user.uid}`;
    videoDiv.style.cssText = 'width: 100%; height: 100%;';
    container.appendChild(videoDiv);

    const label = document.createElement('div');
    label.className = 'remote-label';
    label.textContent = `User ${user.uid}`;
    container.appendChild(label);

    remoteList.appendChild(container);
    state.remoteContainers.set(user.uid, container);

    // Play the video track
    if (user.videoTrack) {
        user.videoTrack.play(videoDiv);
    }
}

function clearRemoteVideos() {
    const remoteList = document.getElementById('remote-playerlist');
    remoteList.innerHTML = '';
    state.remoteContainers.clear();
}

// ============================================================================
// RTM Client (Chat & Game Events)
// ============================================================================

async function initRTMClient(token, channelName) {
    try {
        // Dynamically import RTM SDK
        let AgoraRTM;
        try {
            AgoraRTM = await import('agora-rtm-sdk');
        } catch (importError) {
            console.warn('RTM SDK not available, continuing without chat:', importError);
            addChatMessage('System', 'RTM SDK not loaded - chat disabled', 'system');
            return;
        }

        // Create RTM client - handle both default and named exports
        const RTMClient = AgoraRTM.default || AgoraRTM;
        if (!RTMClient.createInstance) {
            throw new Error('Invalid RTM SDK: createInstance method not found');
        }

        state.rtmClient = RTMClient.createInstance({
            appid: AGORA_APP_ID,
        });

        // Set up RTM event handlers
        state.rtmClient.on('ConnectionStateChanged', (newState, reason) => {
            console.log('RTM connection state:', newState, reason);
        });

        state.rtmClient.on('MessageFromPeer', (message, peerId) => {
            console.log('RTM message from peer:', peerId, message);
            handleRTMPeerMessage(peerId, message);
        });

        state.rtmClient.on('MessageFromChannel', (message, peerId) => {
            console.log('RTM message from channel:', peerId, message);
            handleRTMChannelMessage(peerId, message);
        });

        // Login to RTM
        await state.rtmClient.login(token, state.uid.toString());
        console.log('RTM logged in as:', state.uid);

        // Join RTM channel for group messaging
        state.rtmChannel = state.rtmClient.createChannel(channelName);

        state.rtmChannel.on('ChannelMessage', (message, peerId) => {
            handleRTMChannelMessage(peerId, message);
        });

        state.rtmChannel.on('MemberJoined', (memberId) => {
            addChatMessage('System', `User ${memberId} joined (RTM)`, 'system');
        });

        state.rtmChannel.on('MemberLeft', (memberId) => {
            addChatMessage('System', `User ${memberId} left (RTM)`, 'system');
        });

        await state.rtmChannel.join();
        console.log('RTM channel joined:', channelName);

        addChatMessage('System', 'Chat system connected', 'system');

    } catch (error) {
        console.error('Error initializing RTM:', error);
        addChatMessage('System', `RTM initialization failed: ${error.message}`, 'system');
        // Continue without RTM - RTC still works
    }
}

function handleRTMChannelMessage(peerId, message) {
    try {
        const data = JSON.parse(message.text);
        if (data.type === 'chat') {
            addChatMessage(`User ${peerId}`, data.message);
        } else if (data.type === 'game-event') {
            addChatMessage('🎮 Game', data.message, 'system');
        }
    } catch (e) {
        addChatMessage(`User ${peerId}`, message.text);
    }
}

function handleRTMPeerMessage(peerId, message) {
    console.log('Peer message:', peerId, message);
}

async function sendMessage() {
    const chatInput = document.getElementById('chatInput');
    const message = chatInput.value.trim();

    if (!message || !state.rtmChannel) return;

    try {
        await state.rtmChannel.send({ text: JSON.stringify({ type: 'chat', message }) });
        addChatMessage('You', message);
        chatInput.value = '';
    } catch (error) {
        console.error('Error sending message:', error);
    }
}

// Make sendMessage available globally
window.sendMessage = sendMessage;

// ============================================================================
// Cleanup
// ============================================================================

async function cleanupTracks() {
    if (state.localAudioTrack) {
        state.localAudioTrack.close();
        state.localAudioTrack = null;
    }
    if (state.localVideoTrack) {
        state.localVideoTrack.close();
        state.localVideoTrack = null;
    }
}

async function cleanup() {
    await cleanupTracks();

    if (state.rtmChannel) {
        await state.rtmChannel.leave();
        state.rtmChannel = null;
    }

    if (state.rtmClient) {
        await state.rtmClient.logout();
        state.rtmClient = null;
    }

    state.rtcClient = null;
    state.isConnected = false;
    state.currentChannel = null;
    state.uid = null;
    state.participants.clear();
    state.remoteContainers.clear();
}

// ============================================================================
// Game State Management (via RTM)
// ============================================================================

async function sendGameEvent(eventType, data = {}) {
    if (!state.rtmChannel) {
        console.warn('RTM channel not connected');
        return;
    }

    const message = {
        type: 'game-event',
        eventType,
        data,
        timestamp: Date.now(),
        sender: state.uid,
    };

    try {
        await state.rtmChannel.send({ text: JSON.stringify(message) });
        console.log('Game event sent:', message);
    } catch (error) {
        console.error('Error sending game event:', error);
    }
}

// Example game events
async function startBattle() {
    await sendGameEvent('battle-start', {
        startTime: Date.now(),
        duration: 180000, // 3 minutes
    });
    updateBattleStatus('Live');
}

async function endBattle() {
    await sendGameEvent('battle-end', {
        endTime: Date.now(),
    });
    updateBattleStatus('Ended');
}

async function sendVote(candidateId) {
    await sendGameEvent('vote', {
        candidateId,
        timestamp: Date.now(),
    });
}

// ============================================================================
// Device Management
// ============================================================================

async function getCameras() {
    try {
        const cameras = await AgoraRTC.getCameras();
        return cameras;
    } catch (error) {
        console.error('Error getting cameras:', error);
        return [];
    }
}

async function getMicrophones() {
    try {
        const microphones = await AgoraRTC.getMicrophones();
        return microphones;
    } catch (error) {
        console.error('Error getting microphones:', error);
        return [];
    }
}

async function switchCamera(deviceId) {
    if (state.localVideoTrack) {
        await state.localVideoTrack.setDevice(deviceId);
        addChatMessage('System', 'Camera switched', 'system');
    }
}

async function switchMicrophone(deviceId) {
    if (state.localAudioTrack) {
        await state.localAudioTrack.setDevice(deviceId);
        addChatMessage('System', 'Microphone switched', 'system');
    }
}

// ============================================================================
// Make functions globally available
// ============================================================================

window.handleJoin = handleJoin;
window.handleLeave = handleLeave;
window.sendGameEvent = sendGameEvent;
window.startBattle = startBattle;
window.endBattle = endBattle;
window.sendVote = sendVote;

// ============================================================================
// Initialize
// ============================================================================

// Set up Enter key for chat input
document.addEventListener('DOMContentLoaded', () => {
    const chatInput = document.getElementById('chatInput');
    if (chatInput) {
        chatInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                sendMessage();
            }
        });
    }

    // Check for Agora App ID
    if (!AGORA_APP_ID) {
        addChatMessage('System', 'Warning: AGORA_APP_ID not configured. Set VITE_AGORA_APP_ID environment variable.', 'system');
    }

    console.log('WeAfrica Music Battle initialized');
    console.log('Agora App ID:', AGORA_APP_ID ? 'Configured' : 'Not configured');
    console.log('API Base URL:', API_BASE_URL);
});

// Export for module usage
export {
    state,
    handleJoin,
    handleLeave,
    setRole,
    sendGameEvent,
    startBattle,
    endBattle,
    sendVote,
};