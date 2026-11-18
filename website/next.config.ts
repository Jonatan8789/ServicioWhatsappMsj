import type { NextConfig } from "next";

// Exportación estática: el sitio se publica como HTML/CSS/JS fijo en
// Firebase Hosting (mismo proyecto GCP que la app) y lee el contenido
// editable (textos, fotos, videos) directo de Firestore/Storage en el
// navegador — así una edición desde el panel admin se ve al instante, sin
// tener que recompilar ni redesplegar el sitio.
const nextConfig: NextConfig = {
  output: "export",
  images: {
    unoptimized: true,
  },
  turbopack: {
    root: __dirname,
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
