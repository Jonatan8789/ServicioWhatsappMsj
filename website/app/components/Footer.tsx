import Image from "next/image";
import { SitioConfig } from "@/lib/types";

export default function Footer({ config }: { config: SitioConfig }) {
  const año = new Date().getFullYear();
  return (
    <footer className="bg-oqua-ink py-10 text-white/70">
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-4 px-6 text-center sm:flex-row sm:justify-between sm:text-left">
        <div className="flex items-center gap-3">
          <Image
            src="/logo-oqua.png"
            alt={config.nombreClub}
            width={36}
            height={36}
            className="rounded-md"
          />
          <div>
            <p className="font-bold text-white">{config.nombreClub}</p>
            <p className="text-xs">{config.eslogan}</p>
          </div>
        </div>
        <div className="flex gap-4 text-sm">
          {config.instagram && (
            <a href={config.instagram} className="hover:text-oqua-accent">
              Instagram
            </a>
          )}
          {config.facebook && (
            <a href={config.facebook} className="hover:text-oqua-accent">
              Facebook
            </a>
          )}
        </div>
        <p className="text-xs">
          © {año} {config.nombreClub}. Todos los derechos reservados.
        </p>
      </div>
    </footer>
  );
}
