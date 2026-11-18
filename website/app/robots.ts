import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/seo-config";

// output:'export' genera esto como un robots.txt estático en build time —
// Next exige marcarlo force-static explícitamente para esta ruta especial.
export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
