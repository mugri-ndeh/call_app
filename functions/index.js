const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

admin.initializeApp();

exports.sendCallNotification = onDocumentCreated(
  "notification_requests/{requestId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const request = snapshot.data();
    const token = request.toFcmToken;

    if (!token) {
      await snapshot.ref.set(
        {
          error: "Missing destination FCM token",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return;
    }

    const rawData = request.data || {};
    const data = Object.fromEntries(
      Object.entries(rawData).map(([key, value]) => [key, String(value)]),
    );

    await admin.messaging().send({
      token,
      notification: {
        title: request.title || "Incoming call",
        body: request.body || "You have an incoming call",
      },
      data,
      android: {
        priority: "high",
        notification: {
          channelId: "Incoming Call",
          priority: "max",
          sound: "default",
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: "default",
            contentAvailable: true,
          },
        },
      },
    });

    await snapshot.ref.set(
      {
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  },
);
