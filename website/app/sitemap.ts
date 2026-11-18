import type { MetadataRoute } from "next";
import { SECCIONES_IDS } from "@/lib/types";
import { SITE_URL } from "@/lib/seo-config";

// output:'export' genera esto como un sitemap.xml estático en build time —
// Next exige marcarlo force-static explícitamente para esta ruta especial.
export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: SITE_URL,
      changeFrequency: "weekly",
      priority: 1,
    },
    ...SECCIONES_IDS.map((slug) => ({
      url: `${SITE_URL}/secciones/${slug}`,
      changeFrequency: "monthly" as const,
      priority: 0.7,
    })),
  ];
}
