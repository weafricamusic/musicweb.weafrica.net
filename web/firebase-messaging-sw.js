importScripts('https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.8.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyBy7DgF8Vk39ek75gO7iIi_f8spwDJbgLY",
  authDomain: "weafrica-music-85cdc.firebaseapp.com",
  projectId: "weafrica-music-85cdc",
  messagingSenderId: "985705961084",
  appId: "1:985705961084:web:b494fce32e4a41b8c45bf9"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/favicon.png'
  };
  self.registration.showNotification(notificationTitle, notificationOptions);
});
