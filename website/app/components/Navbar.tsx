"use client";

import Image from "next/image";
import { useState } from "react";

const ENLACES = [
  { href: "#natatorio", label: "Natatorio" },
  { href: "#padel", label: "Pádel" },
  { href: "#gimnasio", label: "Gimnasio" },
  { href: "#buffet", label: "Buffet" },
  { href: "#contacto", label: "Contacto" },
];

export default function Navbar({ urlPortalSocios }: { urlPortalSocios: string }) {
  const [abierto, setAbierto] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-oqua-ink/95 backdrop-blur">
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3 sm:px-6">
        <a href="#inicio" className="flex items-center gap-2">
          <Image
            src="/logo-oqua.png"
            alt="OQUA Club Deportivo"
            width={40}
            height={40}
            className="rounded-md"
          />
          <span className="hidden text-lg font-bold tracking-wide text-white sm:inline">
            OQUA
          </span>
        </a>

        <div className="hidden items-center gap-6 md:flex">
          {ENLACES.map((e) => (
            <a
              key={e.href}
              href={e.href}
              className="text-sm font-medium text-white/80 transition hover:text-oqua-accent"
            >
              {e.label}
            </a>
          ))}
          {urlPortalSocios ? (
            <a
              href={urlPortalSocios}
              className="rounded-full bg-oqua-accent px-4 py-2 text-sm font-bold text-oqua-ink transition hover:bg-oqua-accent-dark"
            >
              Portal de Socios
            </a>
          ) : (
            <span className="rounded-full border border-white/20 px-4 py-2 text-sm font-semibold text-white/50">
              Portal de Socios (próximamente)
            </span>
          )}
        </div>

        <button
          aria-label="Abrir menú"
          className="rounded-md p-2 text-white md:hidden"
          onClick={() => setAbierto((v) => !v)}
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path strokeLinecap="round" d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>
      </nav>

      {abierto && (
        <div className="flex flex-col gap-1 border-t border-white/10 bg-oqua-ink px-4 pb-4 md:hidden">
          {ENLACES.map((e) => (
            <a
              key={e.href}
              href={e.href}
              onClick={() => setAbierto(false)}
              className="rounded-md px-2 py-2 text-white/90 hover:bg-white/10"
            >
              {e.label}
            </a>
          ))}
          {urlPortalSocios && (
            <a
              href={urlPortalSocios}
              className="mt-1 rounded-md bg-oqua-accent px-2 py-2 text-center font-bold text-oqua-ink"
            >
              Portal de Socios
            </a>
          )}
        </div>
      )}
    </header>
  );
}
