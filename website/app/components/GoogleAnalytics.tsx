"use client";

import Script from "next/script";

// 📊 Analytics: todavía no existe una cuenta de Google Analytics (GA4) para
// el club, así que esto queda apagado hasta que se cargue un ID real. Sin
// NEXT_PUBLIC_GA_MEASUREMENT_ID definido no se inyecta ningún script —
// cuando se cree la cuenta en analytics.google.com, sólo hace falta setear
// esa variable de entorno antes de `next build` (o en la config de deploy)
// y recompilar; no hace falta tocar este archivo.
const GA_MEASUREMENT_ID = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

export default function GoogleAnalytics() {
  if (!GA_MEASUREMENT_ID) return null;

  return (
    <>
      <Script
        src={`https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`}
        strategy="afterInteractive"
      />
      <Script id="ga-init" strategy="afterInteractive">
        {`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', '${GA_MEASUREMENT_ID}');
        `}
      </Script>
    </>
  );
}
