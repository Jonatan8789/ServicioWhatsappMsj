"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import Navbar from "../../components/Navbar";
import Footer from "../../components/Footer";
import Galeria from "../../components/Galeria";
import Reveal from "../../components/Reveal";
import {
  obtenerConfig,
  obtenerGaleriaPorCategoria,
  obtenerSeccion,
} from "@/lib/data";
import { ItemGaleria, SeccionSitio, SitioConfig, configPorDefecto } from "@/lib/types";

const TITULOS_POR_DEFECTO: Record<string, { titulo: string; descripcion: string }> = {
  natatorio: {
    titulo: "Natatorio",
    descripcion:
      "Andariveles para nado libre, escuela de natación y rehabilitación, con control sanitario al día. Reservá tu turno desde la app de socios.",
  },
  padel: {
    titulo: "Pádel",
    descripcion:
      "Canchas de cristal y de muro, turnos online y modo Partido Abierto para sumarte con otros socios y dividir el pago de la cancha.",
  },
  gimnasio: {
    titulo: "Gimnasio",
    descripcion:
      "Rutinas personalizadas armadas por nuestros profesores y clases grupales con cupo — si está completo, entrás a la lista de espera.",
  },
  buffet: {
    titulo: "Buffet",
    descripcion:
      "Para recargar energías después de entrenar: menú del día, snacks y bebidas, con pago en caja o a cuenta corriente.",
  },
};

export default function SeccionDetalleClient({ slug }: { slug: string }) {
  const [config, setConfig] = useState<SitioConfig>(configPorDefecto);
  const [seccion, setSeccion] = useState<SeccionSitio | null>(null);
  const [galeria, setGaleria] = useState<ItemGaleria[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    obtenerConfig().then(setConfig);
    obtenerSeccion(slug).then(async (s) => {
      setSeccion(s);
      const tituloParaGaleria = s?.titulo || TITULOS_POR_DEFECTO[slug]?.titulo;
      if (tituloParaGaleria) {
        setGaleria(await obtenerGaleriaPorCategoria(tituloParaGaleria));
      }
      setCargando(false);
    });
  }, [slug]);

  const porDefecto = TITULOS_POR_DEFECTO[slug];
  const titulo = seccion?.titulo || porDefecto?.titulo || slug;
  const descripcion = seccion?.descripcion || porDefecto?.descripcion || "";
  const detalle = seccion?.detalleTexto || "";
  const imagenUrl = seccion?.imagenUrl || "";

  if (!cargando && !porDefecto && !seccion) {
    return (
      <>
        <Navbar urlPortalSocios={config.urlPortalSocios} />
        <main className="flex min-h-[60vh] flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
          <h1 className="text-3xl font-bold text-oqua-ink">
            No encontramos esa sección
          </h1>
          <Link href="/" className="font-semibold text-oqua-accent-dark">
            ← Volver al inicio
          </Link>
        </main>
        <Footer config={config} />
      </>
    );
  }

  return (
    <>
      <Navbar urlPortalSocios={config.urlPortalSocios} />
      <main className="flex-1">
        <section className="relative overflow-hidden bg-gradient-to-br from-oqua-ink via-oqua-ink-light to-oqua-ink-soft">
          {imagenUrl && (
            <Image
              src={imagenUrl}
              alt={titulo}
              fill
              className="object-cover opacity-30"
            />
          )}
          <div className="relative mx-auto max-w-4xl px-6 py-24 text-center">
            <Link
              href="/"
              prefetch={false}
              className="mb-4 inline-block text-sm font-medium text-white/70 hover:text-white"
            >
              ← Volver al inicio
            </Link>
            <h1 className="text-4xl font-extrabold text-white sm:text-5xl">
              {titulo}
            </h1>
            <p className="mx-auto mt-4 max-w-2xl text-lg text-white/85">
              {descripcion}
            </p>
          </div>
        </section>

        {detalle && (
          <section className="mx-auto max-w-3xl px-6 py-16">
            <Reveal>
              <div className="whitespace-pre-line text-lg leading-relaxed text-oqua-ink-soft">
                {detalle}
              </div>
            </Reveal>
          </section>
        )}

        <Galeria items={galeria} />

        <section className="mx-auto max-w-3xl px-6 pb-20 text-center">
          <Reveal>
            <div className="flex flex-wrap items-center justify-center gap-4">
              <Link
                href="/#asociarme"
                className="rounded-full bg-oqua-accent px-7 py-3 text-base font-bold text-oqua-ink shadow-lg transition hover:scale-105 hover:bg-oqua-accent-dark"
              >
                Quiero ser socio
              </Link>
              {config.urlPortalSocios && (
                <a
                  href={config.urlPortalSocios}
                  className="rounded-full border-2 border-oqua-ink/30 px-7 py-3 text-base font-semibold text-oqua-ink transition hover:border-oqua-ink"
                >
                  Reservar / Portal de Socios
                </a>
              )}
            </div>
          </Reveal>
        </section>
      </main>
      <Footer config={config} />
    </>
  );
}
