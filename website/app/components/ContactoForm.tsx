"use client";

import { FormEvent, useState } from "react";
import { enviarContacto } from "@/lib/data";
import { SitioConfig } from "@/lib/types";
import Reveal from "./Reveal";

type Estado = "idle" | "enviando" | "ok" | "faltan_datos" | "error";

export default function ContactoForm({ config }: { config: SitioConfig }) {
  const [estado, setEstado] = useState<Estado>("idle");

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const datos = {
      nombre: (form.elements.namedItem("nombre") as HTMLInputElement).value.trim(),
      email: (form.elements.namedItem("email") as HTMLInputElement).value.trim(),
      telefono: (form.elements.namedItem("telefono") as HTMLInputElement).value.trim(),
      mensaje: (form.elements.namedItem("mensaje") as HTMLTextAreaElement).value.trim(),
    };
    if (!datos.nombre || !datos.mensaje || (!datos.email && !datos.telefono)) {
      setEstado("faltan_datos");
      return;
    }

    setEstado("enviando");
    try {
      await enviarContacto(datos);
      setEstado("ok");
      form.reset();
    } catch {
      setEstado("error");
    }
  }

  return (
    <section id="contacto" className="mx-auto max-w-6xl px-6 py-20">
      <Reveal className="grid gap-10 lg:grid-cols-2">
        <div>
          <h2 className="text-3xl font-extrabold text-oqua-ink sm:text-4xl">
            ¿Tenés otra consulta?
          </h2>
          <p className="mt-3 text-oqua-ink-soft">
            Escribinos por acá para cualquier otra cosa que necesites, o
            contactanos directo:
          </p>
          <ul className="mt-6 space-y-2 text-oqua-ink">
            {config.telefono && <li>📞 {config.telefono}</li>}
            {config.whatsapp && <li>💬 WhatsApp: {config.whatsapp}</li>}
            {config.email && <li>✉️ {config.email}</li>}
            {config.direccion && <li>📍 {config.direccion}</li>}
            <li>🕒 {config.horarioAtencion}</li>
          </ul>
        </div>

        <form
          onSubmit={onSubmit}
          className="flex flex-col gap-4 rounded-2xl border border-oqua-ink/10 bg-white p-6 shadow-sm"
        >
          <input
            name="nombre"
            placeholder="Nombre y apellido"
            required
            className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <div className="grid gap-4 sm:grid-cols-2">
            <input
              name="email"
              type="email"
              placeholder="Email"
              className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
            />
            <input
              name="telefono"
              placeholder="Teléfono"
              className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
            />
          </div>
          <textarea
            name="mensaje"
            placeholder="Contanos qué te interesa (natación, pádel, gimnasio...)"
            required
            rows={4}
            className="resize-none rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <button
            type="submit"
            disabled={estado === "enviando"}
            className="rounded-full bg-oqua-ink px-6 py-3 font-bold text-white transition hover:bg-oqua-ink-light disabled:opacity-60"
          >
            {estado === "enviando" ? "Enviando..." : "Enviar consulta"}
          </button>

          {estado === "ok" && (
            <p className="text-sm font-medium text-oqua-accent-dark">
              ¡Gracias! Recibimos tu consulta, te vamos a contactar pronto.
            </p>
          )}
          {estado === "faltan_datos" && (
            <p className="text-sm font-medium text-red-600">
              Completá al menos nombre, mensaje y un email o teléfono.
            </p>
          )}
          {estado === "error" && (
            <p className="text-sm font-medium text-red-600">
              No pudimos enviar tu consulta. Probá de nuevo en un rato, o
              escribinos directo por WhatsApp.
            </p>
          )}
        </form>
      </Reveal>
    </section>
  );
}
