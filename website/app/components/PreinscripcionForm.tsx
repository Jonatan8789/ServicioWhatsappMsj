"use client";

import { FormEvent, useState } from "react";
import { enviarPreinscripcion } from "@/lib/data";
import { DEPORTES_INTERES } from "@/lib/types";
import Reveal from "./Reveal";

type Estado = "idle" | "enviando" | "ok" | "faltan_datos" | "error";

export default function PreinscripcionForm() {
  const [estado, setEstado] = useState<Estado>("idle");

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const el = (name: string) =>
      (form.elements.namedItem(name) as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement)
        ?.value.trim() ?? "";

    const datos = {
      nombre: el("nombre"),
      apellido: el("apellido"),
      dni: el("dni"),
      fechaNacimiento: el("fechaNacimiento"),
      telefono: el("telefono"),
      email: el("email"),
      deporteInteres: el("deporteInteres"),
      comentarios: el("comentarios"),
    };

    if (!datos.nombre || !datos.apellido || !datos.dni || !datos.telefono) {
      setEstado("faltan_datos");
      return;
    }

    setEstado("enviando");
    try {
      await enviarPreinscripcion(datos);
      setEstado("ok");
      form.reset();
    } catch {
      setEstado("error");
    }
  }

  return (
    <section id="asociarme" className="bg-oqua-mist py-20">
      <Reveal className="mx-auto max-w-3xl px-6">
        <h2 className="text-center text-3xl font-extrabold text-oqua-ink sm:text-4xl">
          Pre-inscribite como socio
        </h2>
        <p className="mx-auto mt-3 max-w-xl text-center text-oqua-ink-soft">
          Completá tus datos y los de recepción te contactan para terminar el
          alta — así ganás tiempo cuando vengas al club.
        </p>

        <form
          onSubmit={onSubmit}
          className="mt-10 grid gap-4 rounded-2xl border border-oqua-ink/10 bg-white p-6 shadow-sm sm:grid-cols-2"
        >
          <input
            name="nombre"
            placeholder="Nombre *"
            required
            className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <input
            name="apellido"
            placeholder="Apellido *"
            required
            className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <input
            name="dni"
            placeholder="DNI *"
            required
            className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <label className="flex flex-col gap-1 text-sm text-oqua-ink-soft">
            Fecha de nacimiento
            <input
              name="fechaNacimiento"
              type="date"
              className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
            />
          </label>
          <input
            name="telefono"
            placeholder="Teléfono *"
            required
            className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <input
            name="email"
            type="email"
            placeholder="Email"
            className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
          />
          <label className="flex flex-col gap-1 text-sm text-oqua-ink-soft sm:col-span-2">
            ¿Qué te interesa?
            <select
              name="deporteInteres"
              defaultValue={DEPORTES_INTERES[0]}
              className="rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark"
            >
              {DEPORTES_INTERES.map((d) => (
                <option key={d} value={d}>
                  {d}
                </option>
              ))}
            </select>
          </label>
          <textarea
            name="comentarios"
            placeholder="Comentarios (horarios que te vienen bien, alguna consulta puntual...)"
            rows={3}
            className="resize-none rounded-lg border border-oqua-ink/20 px-4 py-3 outline-none focus:border-oqua-accent-dark sm:col-span-2"
          />

          <button
            type="submit"
            disabled={estado === "enviando"}
            className="rounded-full bg-oqua-accent px-6 py-3 font-bold text-oqua-ink transition hover:bg-oqua-accent-dark disabled:opacity-60 sm:col-span-2"
          >
            {estado === "enviando" ? "Enviando..." : "Quiero pre-inscribirme"}
          </button>

          {estado === "ok" && (
            <p className="text-sm font-medium text-oqua-accent-dark sm:col-span-2">
              ¡Listo! Recibimos tus datos, te contactamos a la brevedad para
              coordinar el alta.
            </p>
          )}
          {estado === "faltan_datos" && (
            <p className="text-sm font-medium text-red-600 sm:col-span-2">
              Completá al menos nombre, apellido, DNI y teléfono.
            </p>
          )}
          {estado === "error" && (
            <p className="text-sm font-medium text-red-600 sm:col-span-2">
              No pudimos guardar tu pre-inscripción. Probá de nuevo en un
              rato, o escribinos directo por WhatsApp.
            </p>
          )}
        </form>
      </Reveal>
    </section>
  );
}
