const admin = require('firebase-admin');

// Si no tenés la clave de servicio descargada, usá las credenciales por defecto o inicializá con tu projectId:
admin.initializeApp({
  projectId: 'oqua-235c1',
  storageBucket: 'oqua-235c1.appspot.com'
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
  console.log('✅ Configuración CORS aplicada con éxito en gs://oqua-235c1.appspot.com');
}

setCors().catch(console.error);