"use client";

import { useEffect, useState } from "react";

// Cloud Function pública (sin auth, CORS abierto) — devuelve sólo conteos
// agregados, nunca datos de socios. Ver obtenerDisponibilidadPublicaPadel
// en functions/index.js.
const ENDPOINT =
  "https://us-central1-oqua-235c1.cloudfunctions.net/obtenerDisponibilidadPublicaPadel";

interface DisponibilidadDia {
  fecha: string;
  libres: number;
  capacidadTotal: number;
}

interface Disponibilidad {
  hoy: DisponibilidadDia;
  manana: DisponibilidadDia;
}

// 🎾 Mostrar disponibilidad REAL (no un mensaje genérico) antes del login
// convierte mejor que "cupos limitados" — pero sólo para pádel: en
// natatorio el cupo de un horario recién se fija con la primera reserva,
// así que no hay una capacidad conocida de antemano para mostrar ahí.
export default function DisponibilidadPadel() {
  const [datos, setDatos] = useState<Disponibilidad | null>(null);

  useEffect(() => {
    fetch(ENDPOINT)
      .then((r) => (r.ok ? r.json() : null))
      .then(setDatos)
      .catch(() => setDatos(null));
  }, []);

  if (!datos || datos.hoy.capacidadTotal === 0) return null;

  return (
    <div className="flex flex-wrap items-center justify-center gap-3">
      <span className="rounded-full bg-white/15 px-4 py-2 text-sm font-semibold text-white backdrop-blur">
        🎾 Hoy quedan <strong>{datos.hoy.libres}</strong> turno/s de pádel
        libres
      </span>
      <span className="rounded-full bg-white/15 px-4 py-2 text-sm font-semibold text-white backdrop-blur">
        Mañana: <strong>{datos.manana.libres}</strong> libre/s
      </span>
    </div>
  );
}
