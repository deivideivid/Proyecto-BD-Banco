/* Banco Andino · Ingreso. Al entrar, lleva a la sección que le toca a cada perfil. */
(function () {
  "use strict";
  const DESTINO = {
    ADMINISTRADOR: "estadisticas.html",
    SUPERVISOR: "estadisticas.html",
    AUDITOR: "estadisticas.html#control",
    CAJERO: "panel.html",
    CLIENTE: "panel.html"
  };
  const form = document.getElementById("form-ingreso");
  const boton = document.getElementById("entrar");
  const mensaje = document.getElementById("mensaje");

  function destinoSeguro(perfil) {
    const volver = new URLSearchParams(location.search).get("volver");
    // Solo páginas propias (sin "//" ni esquemas), para no redirigir a otro sitio
    if (volver && /^[a-z_]+\.html(#[\w?=&.-]*)?$/i.test(volver)) return volver;
    return DESTINO[perfil] || "panel.html";
  }

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    mensaje.textContent = "";
    boton.disabled = true;
    boton.textContent = "Verificando…";
    try {
      const s = await BancoAPI.post("api/sesion/ingresar", {
        login: document.getElementById("login").value, clave: document.getElementById("clave").value });
      location.href = destinoSeguro(s.perfil);
    } catch (e) {
      mensaje.textContent = e.message;
      const caja = document.getElementById("caja");
      caja.classList.remove("sacudir"); void caja.offsetWidth; caja.classList.add("sacudir");
      boton.disabled = false;
      boton.textContent = "Ingresar";
    }
  });
})();
