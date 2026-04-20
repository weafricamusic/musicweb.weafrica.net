/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

async function loadFirebaseConfig() {
  const candidates = [
    '/assets/config/supabase.env.json',
    'assets/config/supabase.env.json',
    // Flutter web assets are served under /assets/<asset-key>
    // so assets/config/... becomes /assets/assets/config/...
    '/assets/assets/config/supabase.env.json',
    'assets/assets/config/supabase.env.json',
  ];

  for (const path of candidates) {
    try {
      const response = await fetch(path, { cache: 'no-store' });
      if (!response.ok) continue;

      const contentType = (response.headers.get('content-type') || '').toLowerCase();
      if (contentType && !contentType.includes('application/json')) continue;

      const env = await response.json();
      if (!env) continue;

      const apiKey = (env.FIREBASE_WEB_API_KEY || '').trim();
      const authDomain = (env.FIREBASE_WEB_AUTH_DOMAIN || '').trim();
      const projectId = (env.FIREBASE_WEB_PROJECT_ID || '').trim();
      const storageBucket = (env.FIREBASE_WEB_STORAGE_BUCKET || '').trim();
      const messagingSenderId = (env.FIREBASE_WEB_MESSAGING_SENDER_ID || '').trim();
      const appId = (env.FIREBASE_WEB_APP_ID || '').trim();
      const measurementId = (env.FIREBASE_WEB_MEASUREMENT_ID || '').trim();

      if (!apiKey || !projectId || !messagingSenderId || !appId) return null;

      return {
        apiKey,
        authDomain,
        projectId,
        storageBucket,
        messagingSenderId,
        appId,
        measurementId,
      };
    } catch (_) {
      // Try next candidate.
    }
  }

  return null;
}

(async () => {
  const config = await loadFirebaseConfig();
  if (!config) return;

  if (!firebase.apps.length) {
    firebase.initializeApp(config);
  }

  const messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    const notification = payload.notification || {};
    const title = notification.title || 'WeAfrica Music';

    const fcmOptions = payload.fcmOptions || {};
    const data = payload.data || {};
    const link = (
      fcmOptions.link ||
      data.deep_link ||
      data.link ||
      data.url ||
      data.click_action ||
      notification.click_action ||
      ''
    ).toString();

    const options = {
      body: notification.body || '',
      icon: '/icons/Icon-192.png',
      data: {
        ...data,
        link,
      },
    };

    self.registration.showNotification(title, options);
  });
})();

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = (event.notification && event.notification.data) ? event.notification.data : {};
  const requestedTarget =
    (typeof data.deep_link === 'string' && data.deep_link.trim()) ||
    (typeof data.link === 'string' && data.link.trim()) ||
    (typeof data.url === 'string' && data.url.trim()) ||
    (typeof data.click_action === 'string' && data.click_action.trim()) ||
    '/';

  const targetUrl = new URL(requestedTarget, self.location.origin).toString();

  event.waitUntil((async () => {
    try {
      const windowClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of windowClients) {
        if (!('focus' in client)) continue;
        try {
          if ('navigate' in client) {
            await client.navigate(targetUrl);
          }
          await client.focus();
          return;
        } catch (_) {
          // Best-effort; fall through to openWindow.
        }
      }

      if (clients.openWindow) {
        await clients.openWindow(targetUrl);
      }
    } catch (_) {
      // Ignore.
    }
  })());
});
