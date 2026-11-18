import Image from "next/image";
import { SitioConfig } from "@/lib/types";
import DisponibilidadPadel from "./DisponibilidadPadel";

export default function Hero({ config }: { config: SitioConfig }) {
  return (
    <section
      id="inicio"
      className="relative overflow-hidden bg-gradient-to-br from-oqua-ink via-oqua-ink-light to-oqua-ink-soft"
    >
      {/* Ondas decorativas con leve movimiento, sin depender de ninguna
          imagen externa ni librería de animación. */}
      <svg
        className="oqua-flotar pointer-events-none absolute inset-x-0 bottom-0 text-oqua-white/5"
        viewBox="0 0 1440 220"
        fill="currentColor"
        aria-hidden
      >
        <path d="M0,96L80,112C160,128,320,160,480,154.7C640,149,800,107,960,101.3C1120,96,1280,128,1360,144L1440,160L1440,220L0,220Z" />
      </svg>
      <svg
        className="pointer-events-none absolute inset-x-0 bottom-0 text-oqua-accent/10"
        viewBox="0 0 1440 180"
        fill="currentColor"
        aria-hidden
      >
        <path d="M0,64L120,80C240,96,480,128,720,122.7C960,117,1200,75,1320,53.3L1440,32L1440,180L0,180Z" />
      </svg>

      {/* Resplandor detrás del logo, apenas perceptible */}
      <div
        aria-hidden
        className="oqua-brillo pointer-events-none absolute left-1/2 top-24 h-64 w-64 -translate-x-1/2 rounded-full bg-oqua-accent/30 blur-3xl"
      />

      <div className="relative mx-auto flex max-w-6xl flex-col items-center gap-8 px-6 py-24 text-center sm:py-32">
        <Image
          src="/logo-oqua.png"
          alt="OQUA Club Deportivo"
          width={150}
          height={150}
          priority
          className="oqua-animar-entrada rounded-2xl shadow-2xl"
        />
        <div className="oqua-animar-entrada" style={{ animationDelay: "120ms" }}>
          <h1 className="text-4xl font-extrabold tracking-tight text-white sm:text-6xl lg:text-7xl">
            {config.heroTitulo}
          </h1>
          <p className="mx-auto mt-5 max-w-2xl text-lg text-white/80 sm:text-xl">
            {config.heroSubtitulo}
          </p>
        </div>
        <div
          className="oqua-animar-entrada flex flex-wrap items-center justify-center gap-4"
          style={{ animationDelay: "240ms" }}
        >
          <a
            href="#asociarme"
            className="rounded-full bg-oqua-accent px-8 py-3.5 text-base font-bold text-oqua-ink shadow-lg shadow-oqua-accent/30 transition hover:scale-105 hover:bg-oqua-accent-dark"
          >
            Quiero ser socio
          </a>
          <a
            href="#natatorio"
            className="rounded-full border-2 border-white/40 px-8 py-3.5 text-base font-semibold text-white transition hover:border-white hover:bg-white/10"
          >
            Conocé el club
          </a>
        </div>
        <div
          className="oqua-animar-entrada"
          style={{ animationDelay: "320ms" }}
        >
          <DisponibilidadPadel />
        </div>
      </div>
    </section>
  );
}
