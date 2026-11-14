/* Banco Andino · llamadas al servidor (las usan todas las páginas).
   - Manda la cabecera X-Banco-App en las operaciones (el servidor las rechaza sin ella).
   - Si la sesión no existe o se venció (401), lleva a la página de ingreso. */
(function () {
  "use strict";
  async function llamar(metodo, url, cuerpo, senal) {
    const opciones = { method: metodo, signal: senal, credentials: "same-origin",
                       headers: { Accept: "application/json", "X-Banco-App": "1" } };
    if (cuerpo !== undefined) {
      opciones.headers["Content-Type"] = "application/json";
      opciones.body = JSON.stringify(cuerpo);
    }
    const r = await fetch(url, opciones);
    let datos = null;
    try { datos = await r.json(); } catch (_) { /* sin cuerpo */ }
    if (r.status === 401 && !url.includes("sesion/ingresar") && !/ingresar\.html$/.test(location.pathname)) {
      const volver = encodeURIComponent(location.pathname.replace(/^\//, "") + location.hash);
      location.href = "ingresar.html?volver=" + volver;
      throw Object.assign(new Error("Sesión vencida"), { name: "AbortError" });
    }
    if (!r.ok) {
      const d = datos && datos.detail;
      const mensaje = (d && (d.mensaje || (typeof d === "string" ? d : null))) || ("El servidor respondió " + r.status);
      throw Object.assign(new Error(mensaje), { estado: r.status, detalle: d });
    }
    return datos;
  }
  window.BancoAPI = {
    get: (url, senal) => llamar("GET", url, undefined, senal),
    post: (url, cuerpo) => llamar("POST", url, cuerpo || {}),
    salir: async () => { try { await llamar("POST", "api/sesion/salir", {}); } finally { location.href = "ingresar.html"; } }
  };
})();
