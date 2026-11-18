import type { Metadata } from "next";
import { obtenerSeccion } from "@/lib/data";
import { SECCIONES_IDS } from "@/lib/types";
import SeccionDetalleClient from "./SeccionDetalleClient";

// Exportación estática: Next necesita saber de antemano qué slugs existen.
// Son las 4 secciones fijas del club — si el día de mañana se agrega una
// quinta desde el panel admin, hay que sumarla acá también (y en
// lib/features/admin/sitio_web_page.dart, donde vive la lista equivalente).
export function generateStaticParams() {
  return SECCIONES_IDS.map((slug) => ({ slug }));
}

// 🔍 Antes cada sección (Natatorio, Pádel, Gimnasio, Buffet) compartía el
// título/descripción genérico del sitio entero — ahora usa el texto real
// que el admin cargó para esa sección puntual, mejor para SEO y para la
// vista previa al compartir el link.
export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const seccion = await obtenerSeccion(slug);
  if (!seccion) return {};
  return {
    title: seccion.titulo,
    description: seccion.descripcion,
    openGraph: { title: seccion.titulo, description: seccion.descripcion },
  };
}

export default async function SeccionDetallePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  return <SeccionDetalleClient slug={slug} />;
}
