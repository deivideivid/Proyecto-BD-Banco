/* Banco Andino · Auditor de datos: solo consulta (calidad, cuadres, bitácora e ingresos). */
(async function () {
  "use strict";
  const { el, entero, fecha, chip, numero } = Banco;
  await Banco.iniciar({ perfiles: ["AUDITOR"], titulo: "Auditoría de datos" });
  const cargadas = new Set();

  async function cargarCalidad() {
    const d = await BancoAPI.get("api/auditor/calidad");
    const nombres = { OVERALL: "Puntaje general", Auditability: "Auditabilidad", Integrity: "Integridad", "Database Design": "Diseño de la base", "Data Quality": "Calidad de datos" };
    document.getElementById("calidad-puntajes").replaceChildren(...d.puntaje.map((p) => {
      const c = el("span", { class: "cifra grande" });
      Banco.contar(c, p.puntaje, (v) => numero(v, 1));
      return el("article", { class: "tarjeta" }, el("p", { class: "suave chico", text: nombres[p.dimension] || p.dimension }), c,
        el("span", { class: "raya-acento" }),
        el("p", { class: "suave chico", text: p.pass + " PASS · " + p.warning + " WARNING · " + p.fail + " FAIL de " + p.pruebas }));
    }));
    document.getElementById("calidad-pruebas").replaceChildren(Banco.tabla([
      { titulo: "ID", campo: "test_id" }, { titulo: "Dimensión", campo: "dimension" }, { titulo: "Regla", campo: "regla" },
      { titulo: "Severidad", campo: "severidad" }, { titulo: "Resultado", valor: (p) => chip(p.resultado) }, { titulo: "Obtenido", campo: "obtenido" }
    ], d.pruebas));
  }
  async function cargarCuadres() {
    const caja = document.getElementById("lista-cuadres");
    caja.replaceChildren(...[1, 2, 3].map(() => el("article", { class: "tarjeta" }, el("div", { class: "esqueleto" }))));
    const filas = await BancoAPI.get("api/auditor/cuadres");
    caja.replaceChildren(...filas.map((c) => el("article", { class: "tarjeta" },
      el("p", { class: "suave chico", text: c.control }),
      el("span", { class: "cifra grande", text: entero(c.diferencias) }),
      el("p", {}, Number(c.diferencias) === 0 ? chip("PASS") : chip("FAIL")))));
  }
  async function cargarBitacora() {
    const f = Banco.datosDe(document.getElementById("form-bitacora"));
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) if (v) q.set(k, v);
    const caja = document.getElementById("lista-bitacora");
    caja.classList.add("cargando");
    try {
      const filas = await BancoAPI.get("api/auditor/bitacora?" + q);
      caja.replaceChildren(Banco.tabla([
        { titulo: "N.º", campo: "auditoria_id" }, { titulo: "Cuándo", valor: (b) => fecha(b.ocurrido_en) },
        { titulo: "Empleado", valor: (b) => b.login || "—" }, { titulo: "Conexión", campo: "usuario_bd" },
        { titulo: "Tabla", campo: "tabla" }, { titulo: "Operación", valor: (b) => chip(b.operacion, "neutro") },
        { titulo: "Registro", valor: registroTexto },
        { titulo: "Cambios", valor: cambiosTexto }
      ], filas, { vacio: "No hay registros con esos filtros." }));
    } catch (e) { caja.replaceChildren(el("p", { class: "vacio", text: e.message })); }
    finally { caja.classList.remove("cargando"); }
  }
  /* B8 (sugerencia de Miguel): el registro con nombres y, en los UPDATE, qué cambió */
  function registroTexto(b) {
    return Object.entries(b.registro || {}).filter(([k]) => k !== "vigente_desde").map(([k, v]) =>
      k === "usuario_id" && b.usuario_afectado ? "usuario " + b.usuario_afectado + " (n.º " + v + ")"
      : k === "rol_id" && b.rol_afectado ? "rol " + b.rol_afectado
      : k === "cuenta_id" && b.cuenta_afectada ? "cuenta " + b.cuenta_afectada
      : k + " " + v).join(" · ");
  }
  function valorCorto(v) {
    if (v === null || v === undefined) return "vacío";
    const t = typeof v === "object" ? JSON.stringify(v) : String(v);
    return t.length > 40 ? t.slice(0, 39) + "…" : t;
  }
  function cambiosTexto(b) {
    if (!b.cambios) return "—";
    const lista = Object.entries(b.cambios).map(([k, [antes, despues]]) => k + ": " + valorCorto(antes) + " → " + valorCorto(despues));
    return lista.length ? lista.join(" · ") : "Sin cambios de valor";
  }
  async function cargarIngresos() {
    const filas = await BancoAPI.get("api/auditor/ingresos?limite=100");
    document.getElementById("lista-ingresos").replaceChildren(Banco.tabla([
      { titulo: "Cuándo", valor: (i) => fecha(i.momento) }, { titulo: "Usuario", campo: "login" },
      { titulo: "Perfil", valor: (i) => i.perfil ? Banco.NOMBRE_PERFIL[i.perfil] : "—" },
      { titulo: "Resultado", valor: (i) => i.exitoso ? chip("Entró", "exito") : chip("Falló", "peligro") }, { titulo: "Desde", campo: "origen" }
    ], filas, { vacio: "Todavía no hay ingresos." }));
  }
  document.getElementById("form-bitacora").addEventListener("submit", (e) => { e.preventDefault(); cargarBitacora(); });
  document.getElementById("revisar-cuadres").addEventListener("click", () => cargarCuadres().catch((e) => Banco.aviso(e.message, "error")));
  document.getElementById("recargar-ingresos").addEventListener("click", () => cargarIngresos().catch((e) => Banco.aviso(e.message, "error")));

  const cargar = { calidad: cargarCalidad, cuadres: cargarCuadres, bitacora: cargarBitacora, ingresos: cargarIngresos };
  Banco.secciones((s) => {
    if (cargadas.has(s) || !cargar[s]) return;
    cargadas.add(s);
    cargar[s]().catch((e) => Banco.aviso(e.message, "error"));
  });
})();
