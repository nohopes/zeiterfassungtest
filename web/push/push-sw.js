// Eigenständiger, von Hand geschriebener Service-Worker NUR für
// Push-Benachrichtigungen. Bewusst getrennt von Flutters
// `flutter_service_worker.js` (das bei jedem `flutter build web` neu
// generiert wird und PWA-Asset-Caching übernimmt) - diese Datei hier wird
// vom Flutter-Build nicht angefasst und bleibt stabil.
//
// Registriert wird sie mit eigenem Scope "/push/" (siehe
// zeiterfassungSubscribePush() in index.html), dadurch stört sie Flutters
// eigene Service-Worker-Registrierung an Scope "/" nicht - push- und
// notificationclick-Events feuern trotzdem zuverlässig, unabhängig vom
// Scope.

self.addEventListener('push', (event) => {
  let data = { title: 'Stunden Logbuch', body: 'Du hast eine neue Benachrichtigung.' };
  try {
    if (event.data) {
      data = event.data.json();
    }
  } catch (e) {
    // Falls die Nutzlast aus irgendeinem Grund kein JSON ist, bei den
    // Standardwerten oben bleiben statt den Service-Worker abstürzen zu
    // lassen.
  }

  event.waitUntil(
    self.registration.showNotification(data.title || 'Stunden Logbuch', {
      body: data.body || '',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: 'zeiterfassung-reminder',
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const allClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of allClients) {
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })()
  );
});
