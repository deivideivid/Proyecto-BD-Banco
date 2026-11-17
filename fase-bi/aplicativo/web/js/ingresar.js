/* Banco Andino · Ingreso. Al entrar, lleva a la sección que le toca a cada perfil. */
(async function () {
  "use strict";
  const sesion = await Banco.iniciar({ titulo: "Ingresar" });
  const volver = new URLSearchParams(location.search).get("volver");
  // Solo páginas propias (sin "//" ni esquemas), para no redirigir a otro sitio
  const destino = (perfil) => (volver && /^[a-z_]+\.html(#[\w?=&.-]*)?$/i.test(volver)) ? volver : Banco.INICIO[perfil];
  if (sesion) { location.replace(destino(sesion.perfil)); return; }

  const form = document.getElementById("form-ingreso");
  const boton = document.getElementById("entrar");
  const caja = document.getElementById("caja");
  document.getElementById("login").focus();

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const s = await Banco.enviar(boton, () => BancoAPI.post("api/sesion/ingresar", {
      login: document.getElementById("login").value, clave: document.getElementById("clave").value }),
      { errorEn: document.getElementById("mensaje"), sacudir: caja });
    if (!s) return;
    caja.classList.add("saliendo");
    setTimeout(() => { location.href = destino(s.perfil); }, window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 280);
  });
})();
