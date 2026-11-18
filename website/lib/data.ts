import {
  addDoc,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  where,
} from "firebase/firestore";
import { db } from "./firebase";
import {
  ContactoFormulario,
  ItemGaleria,
  PreinscripcionFormulario,
  SeccionSitio,
  SitioConfig,
  configPorDefecto,
} from "./types";

export async function obtenerConfig(): Promise<SitioConfig> {
  try {
    const snap = await getDoc(doc(db, "sitio_web", "config"));
    if (!snap.exists()) return configPorDefecto;
    return { ...configPorDefecto, ...(snap.data() as Partial<SitioConfig>) };
  } catch {
    return configPorDefecto;
  }
}

export async function obtenerSecciones(): Promise<SeccionSitio[]> {
  try {
    const snap = await getDocs(
      query(collection(db, "sitio_web_secciones"), where("activa", "==", true)),
    );
    return snap.docs
      .map((d) => ({ id: d.id, ...(d.data() as Omit<SeccionSitio, "id">) }))
      .sort((a, b) => a.orden - b.orden);
  } catch {
    return [];
  }
}

export async function obtenerSeccion(id: string): Promise<SeccionSitio | null> {
  try {
    const snap = await getDoc(doc(db, "sitio_web_secciones", id));
    if (!snap.exists()) return null;
    return { id: snap.id, ...(snap.data() as Omit<SeccionSitio, "id">) };
  } catch {
    return null;
  }
}

export async function obtenerGaleriaDestacada(): Promise<ItemGaleria[]> {
  try {
    const snap = await getDocs(
      query(collection(db, "sitio_web_galeria"), where("destacado", "==", true)),
    );
    return snap.docs
      .map((d) => ({ id: d.id, ...(d.data() as Omit<ItemGaleria, "id">) }))
      .sort((a, b) => a.orden - b.orden);
  } catch {
    return [];
  }
}

export async function obtenerGaleriaPorCategoria(categoria: string): Promise<ItemGaleria[]> {
  try {
    const snap = await getDocs(
      query(collection(db, "sitio_web_galeria"), where("categoria", "==", categoria)),
    );
    return snap.docs
      .map((d) => ({ id: d.id, ...(d.data() as Omit<ItemGaleria, "id">) }))
      .sort((a, b) => a.orden - b.orden);
  } catch {
    return [];
  }
}

export async function enviarContacto(datos: ContactoFormulario) {
  await addDoc(collection(db, "sitio_web_contactos"), {
    ...datos,
    estado: "Nuevo",
    origen: "sitio_web",
    fecha: serverTimestamp(),
  });
}

export async function enviarPreinscripcion(datos: PreinscripcionFormulario) {
  await addDoc(collection(db, "sitio_web_preinscripciones"), {
    ...datos,
    estado: "Nueva",
    origen: "sitio_web",
    fecha: serverTimestamp(),
  });
}
