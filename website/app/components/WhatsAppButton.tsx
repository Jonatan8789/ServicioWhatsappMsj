"use client";

import { SitioConfig } from "@/lib/types";

// Mismo criterio de normalización que usa la app (limpiarTelefonoAr en
// functions/index.js): agrega el código de país argentino (549) si el
// admin cargó el número en formato local — wa.me exige el número completo
// con código de país para abrir el chat correcto.
function limpiarTelefonoAr(telefono: string): string {
  let limpio = telefono.replace(/\D/g, "");
  if (!limpio) return "";
  if (limpio.startsWith("0")) limpio = limpio.substring(1);
  if (limpio.startsWith("15")) limpio = limpio.substring(2);
  if (!limpio.startsWith("54")) limpio = `549${limpio}`;
  return limpio;
}

export default function WhatsAppButton({ config }: { config: SitioConfig }) {
  const numero = limpiarTelefonoAr(config.whatsapp || config.telefono || "");
  if (!numero) return null;

  const mensaje = encodeURIComponent(
    `Hola! Te escribo desde la web de ${config.nombreClub || "OQUA Club Deportivo"} 👋`,
  );

  return (
    <a
      href={`https://wa.me/${numero}?text=${mensaje}`}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Escribinos por WhatsApp"
      className="fixed bottom-6 left-6 z-50 flex h-14 w-14 items-center justify-center rounded-full bg-[#25D366] shadow-xl transition-transform hover:scale-110"
    >
      <svg
        viewBox="0 0 32 32"
        fill="white"
        className="h-7 w-7"
        aria-hidden="true"
      >
        <path d="M16.004 2.667c-7.364 0-13.333 5.97-13.333 13.333 0 2.353.615 4.56 1.692 6.475L2.667 29.333l7.038-1.846a13.26 13.26 0 0 0 6.3 1.604h.006c7.363 0 13.332-5.97 13.332-13.334 0-3.562-1.387-6.912-3.905-9.43a13.246 13.246 0 0 0-9.434-3.66Zm0 24.4a11.03 11.03 0 0 1-5.62-1.54l-.403-.24-4.177 1.096 1.115-4.073-.263-.418a11.044 11.044 0 0 1-1.69-5.892c0-6.105 4.967-11.07 11.074-11.07a11 11 0 0 1 7.832 3.244 11 11 0 0 1 3.24 7.833c0 6.105-4.967 11.06-11.108 11.06Zm6.073-8.287c-.333-.167-1.97-.973-2.276-1.083-.306-.113-.528-.167-.75.166-.222.334-.861 1.084-1.056 1.307-.194.223-.389.25-.722.084-.333-.167-1.405-.518-2.676-1.65-.989-.883-1.657-1.973-1.852-2.306-.194-.333-.02-.513.146-.68.15-.15.333-.39.5-.584.167-.195.222-.334.333-.556.111-.223.055-.417-.028-.584-.084-.167-.75-1.807-1.028-2.474-.27-.65-.545-.562-.75-.572-.194-.01-.417-.012-.64-.012-.222 0-.583.083-.889.417-.306.333-1.167 1.14-1.167 2.78 0 1.64 1.195 3.224 1.361 3.446.167.223 2.353 3.593 5.701 5.04.797.344 1.418.55 1.902.704.799.254 1.527.218 2.102.132.641-.096 1.97-.805 2.248-1.583.278-.778.278-1.445.195-1.584-.083-.138-.305-.222-.639-.389Z" />
      </svg>
    </a>
  );
}
