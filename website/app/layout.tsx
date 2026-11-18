import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { obtenerConfig } from "@/lib/data";
import { SITE_URL } from "@/lib/seo-config";
import GoogleAnalytics from "./components/GoogleAnalytics";
import WhatsAppButton from "./components/WhatsAppButton";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const TITULO_POR_DEFECTO = "OQUA Club Deportivo";
const DESCRIPCION_POR_DEFECTO =
  "Natación, pádel, gimnasio y buffet en OQUA Club Deportivo. Reservá turnos, sumate a un Partido Abierto o consultá por asociarte.";

// 🔍 SEO: antes sólo había title/description/icon — sin esto Google no
// tenía nada para indexar más allá de esos dos textos fijos, y compartir el
// link en WhatsApp/redes no mostraba ninguna vista previa (Open Graph).
// generateMetadata corre en build time (output:'export' no tiene servidor
// en producción), así que sí puede traer la config real del admin desde
// Firestore y quedar horneado en el HTML estático.
export async function generateMetadata(): Promise<Metadata> {
  const config = await obtenerConfig();
  const titulo = config.nombreClub || TITULO_POR_DEFECTO;
  const descripcion = config.eslogan || DESCRIPCION_POR_DEFECTO;
  const imagen = config.heroImagenUrl || "/logo-oqua.png";

  return {
    metadataBase: new URL(SITE_URL),
    title: { default: titulo, template: `%s | ${titulo}` },
    description: descripcion,
    keywords: [
      "club deportivo",
      "natación",
      "pádel",
      "gimnasio",
      "buffet",
      config.nombreClub,
    ].filter(Boolean),
    icons: { icon: "/logo-oqua.png" },
    openGraph: {
      title: titulo,
      description: descripcion,
      url: SITE_URL,
      siteName: titulo,
      images: [{ url: imagen }],
      locale: "es_AR",
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: titulo,
      description: descripcion,
      images: [imagen],
    },
  };
}

export default async function RootLayout({ children }: LayoutProps<"/">) {
  const config = await obtenerConfig();

  // 📍 Datos estructurados (JSON-LD) para que buscadores entiendan que esto
  // es un club deportivo real, con los mismos datos que el admin ya carga
  // en el panel (sin inventar dirección/teléfono que no tenemos).
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "SportsActivityLocation",
    name: config.nombreClub || TITULO_POR_DEFECTO,
    description: config.eslogan || DESCRIPCION_POR_DEFECTO,
    url: SITE_URL,
    image: config.heroImagenUrl || `${SITE_URL}/logo-oqua.png`,
    ...(config.telefono ? { telephone: config.telefono } : {}),
    ...(config.email ? { email: config.email } : {}),
    ...(config.direccion ? { address: config.direccion } : {}),
    sameAs: [config.instagram, config.facebook].filter(Boolean),
  };

  return (
    <html
      lang="es"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <head>
        <script
          type="application/ld+json"
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </head>
      <body className="min-h-full flex flex-col">
        <GoogleAnalytics />
        {children}
        <WhatsAppButton config={config} />
      </body>
    </html>
  );
}
