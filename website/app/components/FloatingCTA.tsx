"use client";

import { useEffect, useState } from "react";

export default function FloatingCTA() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const onScroll = () => setVisible(window.scrollY > 500);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <a
      href="/#asociarme"
      className={`fixed bottom-6 right-6 z-50 rounded-full bg-oqua-accent px-5 py-3 text-sm font-bold text-oqua-ink shadow-xl transition-all duration-300 hover:scale-105 hover:bg-oqua-accent-dark ${
        visible
          ? "translate-y-0 opacity-100"
          : "pointer-events-none translate-y-4 opacity-0"
      }`}
    >
      Quiero ser socio
    </a>
  );
}
