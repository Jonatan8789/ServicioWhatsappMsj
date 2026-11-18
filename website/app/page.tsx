"use client";

import { useEffect, useState } from "react";
import Navbar from "./components/Navbar";
import Hero from "./components/Hero";
import Secciones from "./components/Secciones";
import Galeria from "./components/Galeria";
import PreinscripcionForm from "./components/PreinscripcionForm";
import ContactoForm from "./components/ContactoForm";
import Footer from "./components/Footer";
import FloatingCTA from "./components/FloatingCTA";
import { obtenerConfig, obtenerGaleriaDestacada, obtenerSecciones } from "@/lib/data";
import { ItemGaleria, SeccionSitio, SitioConfig, configPorDefecto } from "@/lib/types";

export default function Home() {
  const [config, setConfig] = useState<SitioConfig>(configPorDefecto);
  const [secciones, setSecciones] = useState<SeccionSitio[]>([]);
  const [galeria, setGaleria] = useState<ItemGaleria[]>([]);

  useEffect(() => {
    obtenerConfig().then(setConfig);
    obtenerSecciones().then(setSecciones);
    obtenerGaleriaDestacada().then(setGaleria);
  }, []);

  return (
    <>
      <Navbar urlPortalSocios={config.urlPortalSocios} />
      <main className="flex-1">
        <Hero config={config} />
        <Secciones secciones={secciones} />
        <Galeria items={galeria} />
        <PreinscripcionForm />
        <ContactoForm config={config} />
      </main>
      <Footer config={config} />
      <FloatingCTA />
    </>
  );
}
