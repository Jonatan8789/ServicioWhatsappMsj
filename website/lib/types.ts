export interface SitioConfig {
  nombreClub: string;
  eslogan: string;
  heroTitulo: string;
  heroSubtitulo: string;
  heroImagenUrl: string;
  telefono: string;
  whatsapp: string;
  email: string;
  direccion: string;
  horarioAtencion: string;
  instagram: string;
  facebook: string;
  urlPortalSocios: string;
}

export const configPorDefecto: SitioConfig = {
  nombreClub: "OQUA Club Deportivo",
  eslogan: "Natación, pádel, buffet y gimnasio en un solo lugar.",
  heroTitulo: "Vení a moverte con nosotros",
  heroSubtitulo:
    "Pileta, canchas de pádel, gimnasio y buffet para toda la familia.",
  heroImagenUrl: "",
  telefono: "",
  whatsapp: "",
  email: "",
  direccion: "",
  horarioAtencion: "Lunes a sábados de 8 a 22 hs",
  instagram: "",
  facebook: "",
  urlPortalSocios: "https://oqua-235c1.web.app",
};

export interface SeccionSitio {
  id: string;
  titulo: string;
  descripcion: string;
  detalleTexto: string;
  imagenUrl: string;
  orden: number;
  activa: boolean;
}

export const SECCIONES_IDS = ["natatorio", "padel", "gimnasio", "buffet"] as const;

export type TipoGaleria = "foto" | "video";

export interface ItemGaleria {
  id: string;
  tipo: TipoGaleria;
  categoria: string;
  url: string;
  orden: number;
  destacado: boolean;
}

export interface ContactoFormulario {
  nombre: string;
  email: string;
  telefono: string;
  mensaje: string;
}

export const DEPORTES_INTERES = [
  "Natatorio",
  "Pádel",
  "Gimnasio",
  "Pase completo",
  "Todavía no sé",
] as const;

export interface PreinscripcionFormulario {
  nombre: string;
  apellido: string;
  dni: string;
  fechaNacimiento: string; // yyyy-mm-dd, tal cual lo da <input type="date">
  telefono: string;
  email: string;
  deporteInteres: string;
  comentarios: string;
}
