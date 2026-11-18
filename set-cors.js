const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// 🚨 Antes apuntaba a 'oqua-235c1.appspot.com' (el nombre de bucket legacy):
// la app real usa 'oqua-235c1.firebasestorage.app' (ver storageBucket en
// lib/firebase_options.dart). El CORS se aplicaba a un bucket que la app
// nunca lee/escribe, así que nunca tuvo efecto — por eso las fotos de
// socios seguían sin mostrarse en el navegador después de "arreglar" esto.

// 🔑 Este entorno no tiene Application Default Credentials de Google Cloud
// configuradas (ni gcloud CLI ni GOOGLE_APPLICATION_CREDENTIALS), así que
// hace falta una clave de cuenta de servicio explícita. Se busca
// 'serviceAccountKey.json' junto a este script (nunca se commitea, ver
// .gitignore) — descargala desde Firebase Console → Configuración del
// Proyecto → Cuentas de servicio → "Generar nueva clave privada".
const rutaClave = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(rutaClave)) {
  console.error(
    `❌ No se encontró ${rutaClave}.\n` +
    'Descargá la clave desde Firebase Console → Configuración del Proyecto → ' +
    'Cuentas de servicio → "Generar nueva clave privada", y guardala con ' +
    'ese nombre exacto en la raíz del proyecto.'
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(rutaClave)),
  projectId: 'oqua-235c1',
  storageBucket: 'oqua-235c1.firebasestorage.app'
});

const bucket = admin.storage().bucket();

async function setCors() {
  await bucket.setCorsConfiguration([
    {
      origin: ['*'],
      method: ['GET', 'HEAD', 'PUT', 'POST', 'DELETE'],
      responseHeader: ['*'],
      maxAgeSeconds: 3600,
    },
  ]);
  console.log('✅ Configuración CORS aplicada con éxito en gs://oqua-235c1.firebasestorage.app');
}

setCors().catch(console.error);