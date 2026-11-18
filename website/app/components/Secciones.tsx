import Image from "next/image";
import Link from "next/link";
import { SeccionSitio } from "@/lib/types";
import Reveal from "./Reveal";

const SECCIONES_POR_DEFECTO: SeccionSitio[] = [
  {
    id: "natatorio",
    titulo: "Natatorio",
    descripcion:
      "Andariveles para nado libre, escuela de natación y rehabilitación, con control sanitario al día. Reservá tu turno desde la app de socios.",
    detalleTexto: "",
    imagenUrl: "",
    orden: 1,
    activa: true,
  },
  {
    id: "padel",
    titulo: "Pádel",
    descripcion:
      "Canchas de cristal y de muro, turnos online y modo Partido Abierto para sumarte con otros socios y dividir el pago de la cancha.",
    detalleTexto: "",
    imagenUrl: "",
    orden: 2,
    activa: true,
  },
  {
    id: "gimnasio",
    titulo: "Gimnasio",
    descripcion:
      "Rutinas personalizadas armadas por nuestros profesores y clases grupales con cupo — si está completo, entrás a la lista de espera.",
    detalleTexto: "",
    imagenUrl: "",
    orden: 3,
    activa: true,
  },
  {
    id: "buffet",
    titulo: "Buffet",
    descripcion:
      "Para recargar energías después de entrenar: menú del día, snacks y bebidas, con pago en caja o a cuenta corriente.",
    detalleTexto: "",
    imagenUrl: "",
    orden: 4,
    activa: true,
  },
];

export default function Secciones({ secciones }: { secciones: SeccionSitio[] }) {
  const lista = secciones.length > 0 ? secciones : SECCIONES_POR_DEFECTO;

  return (
    <section className="mx-auto max-w-6xl px-6 py-20">
      <Reveal>
        <h2 className="text-center text-3xl font-extrabold text-oqua-ink sm:text-4xl">
          Todo lo que necesitás, en un solo club
        </h2>
        <p className="mx-auto mt-3 max-w-2xl text-center text-oqua-ink-soft">
          Natación, pádel, gimnasio y buffet — pensado para toda la familia.
          Tocá cada uno para ver el detalle.
        </p>
      </Reveal>

      <div className="mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
        {lista.map((s, i) => (
          <Reveal key={s.id} delay={i * 90}>
            <Link
              href={`/secciones/${s.id}`}
              prefetch={false}
              className="group flex h-full flex-col overflow-hidden rounded-2xl border border-oqua-ink/10 bg-white shadow-sm transition duration-300 hover:-translate-y-2 hover:shadow-2xl hover:shadow-oqua-ink/10"
            >
              <div className="relative h-44 w-full overflow-hidden bg-oqua-mist">
                {s.imagenUrl ? (
                  <Image
                    src={s.imagenUrl}
                    alt={s.titulo}
                    fill
                    className="object-cover transition duration-500 group-hover:scale-110"
                  />
                ) : (
                  <div className="flex h-full w-full items-center justify-center text-oqua-ink/20 transition group-hover:text-oqua-accent/60">
                    <WaveIcon />
                  </div>
                )}
                <div className="absolute inset-0 bg-gradient-to-t from-oqua-ink/40 via-transparent to-transparent opacity-0 transition group-hover:opacity-100" />
              </div>
              <div className="flex flex-1 flex-col gap-2 p-5">
                <h3 className="text-xl font-bold text-oqua-ink">{s.titulo}</h3>
                <p className="flex-1 text-sm text-oqua-ink-soft">{s.descripcion}</p>
                <span className="mt-1 inline-flex items-center gap-1 text-sm font-bold text-oqua-accent-dark">
                  Ver más
                  <span className="transition group-hover:translate-x-1">→</span>
                </span>
              </div>
            </Link>
          </Reveal>
        ))}
      </div>
    </section>
  );
}

function WaveIcon() {
  return (
    <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M2 17c1.5-1.5 3-1.5 4.5 0s3 1.5 4.5 0 3-1.5 4.5 0 3 1.5 4.5 0" strokeLinecap="round" />
      <path d="M2 12c1.5-1.5 3-1.5 4.5 0s3 1.5 4.5 0 3-1.5 4.5 0 3 1.5 4.5 0" strokeLinecap="round" opacity="0.5" />
    </svg>
  );
}
