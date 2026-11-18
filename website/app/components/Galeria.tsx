import Image from "next/image";
import { ItemGaleria } from "@/lib/types";
import Reveal from "./Reveal";

export default function Galeria({ items }: { items: ItemGaleria[] }) {
  if (items.length === 0) return null;

  return (
    <section className="bg-oqua-mist py-20">
      <div className="mx-auto max-w-6xl px-6">
        <Reveal>
          <h2 className="text-center text-3xl font-extrabold text-oqua-ink sm:text-4xl">
            Así se vive OQUA
          </h2>
        </Reveal>
        <div className="mt-10 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          {items.map((item, i) => (
            <Reveal key={item.id} delay={(i % 8) * 60}>
              <div className="relative aspect-square overflow-hidden rounded-xl bg-oqua-ink/10">
                {item.tipo === "video" ? (
                  <video
                    src={item.url}
                    className="h-full w-full object-cover transition duration-500 hover:scale-105"
                    muted
                    loop
                    playsInline
                    autoPlay
                  />
                ) : (
                  <Image
                    src={item.url}
                    alt={item.categoria}
                    fill
                    className="object-cover transition duration-500 hover:scale-110"
                  />
                )}
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
