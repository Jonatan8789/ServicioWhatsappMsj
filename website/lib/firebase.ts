import { initializeApp, getApps, getApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";

// Mismo proyecto Firebase/GCP que usa la app de socios (oqua-235c1) — el
// sitio público y el "portal de socios" (app Flutter Web) viven en el mismo
// backend, así que cuenta corriente/reservas/etc. son siempre la misma
// fuente de verdad. Esta config (apiKey, etc.) es pública por diseño en
// cualquier app cliente de Firebase: la seguridad real la dan las reglas de
// Firestore, no ocultar estos valores.
const firebaseConfig = {
  apiKey: "AIzaSyAMuXW3-rXtigeGmSFVYeKupPEqZkQQ2Lc",
  authDomain: "oqua-235c1.firebaseapp.com",
  projectId: "oqua-235c1",
  storageBucket: "oqua-235c1.firebasestorage.app",
  messagingSenderId: "1033148419273",
  appId: "1:1033148419273:web:1508dc9ffdea9a2e771118",
  measurementId: "G-JDHBF3CTPH",
};

export const firebaseApp = getApps().length
  ? getApp()
  : initializeApp(firebaseConfig);

export const db = getFirestore(firebaseApp);
