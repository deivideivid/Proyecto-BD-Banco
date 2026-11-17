/* Banco Andino · Supervisor: ajustes pendientes, reversos e inactivación de cuentas.
   Desbloquear, cambiar límite y cerrar están en la ficha del cliente (Caja). */
(async function () {
  "use strict";
  const { el, dinero, entero, fecha, chip } = Banco;
  await Banco.iniciar({ perfiles: ["SUPERVISOR"], titulo: "Supervisión" });

  async function cargarPendientes() {
    const caja = document.getElementById("lista-pendientes");
    caja.classList.add("cargando");
    try {
      const filas = await BancoAPI.get("api/supervisor/ajustes");
      caja.replaceChildren(Banco.tabla([
        { titulo: "N.º", campo: "transaccion_id" },
        { titulo: "Cuenta", campo: "numero_cuenta" },
        { titulo: "Sentido", valor: (a) => chip(a.sentido === "C" ? "A favor" : "En contra", a.sentido === "C" ? "exito" : "alerta") },
        { titulo: "Monto", num: true, valor: (a) => dinero(a.monto) },
        { titulo: "Descripción", campo: "descripcion" },
        { titulo: "Solicitado", valor: (a) => fecha(a.fecha_solicitud) },
        { titulo: "", acciones: true, valor: (a) => a.es_mio
            ? el("span", { class: "chip neutro", text: "Lo creó usted: lo aprueba otro" })
            : el("div", { class: "fila fin" },
                el("button", { class: "boton primario chico", type: "button", text: "Aprobar", onclick: (e) => aprobar(a, e.currentTarget) }),
                el("button", { class: "boton secundario chico", type: "button", text: "Rechazar", onclick: (e) => rechazar(a, e.currentTarget) })) }
      ], filas, { vacio: "No hay ajustes pendientes en su oficina." }));
    } catch (e) { caja.replaceChildren(el("p", { class: "vacio", text: e.message })); }
    finally { caja.classList.remove("cargando"); }
  }
  async function aprobar(a, boton) {
    const ok = await Banco.confirmar({ titulo: "Aprobar el ajuste " + a.transaccion_id, texto: "Se aplica al saldo de la cuenta.",
      datos: [["Cuenta", a.numero_cuenta], ["Sentido", a.sentido === "C" ? "A favor del cliente" : "En contra del cliente"], ["Monto", dinero(a.monto)], ["Descripción", a.descripcion]], boton: "Aprobar" });
    if (!ok) return;
    const r = await Banco.enviar(boton, () => BancoAPI.post("api/supervisor/ajustes/" + a.transaccion_id + "/aprobar"));
    if (r) { await Banco.exito({ titulo: "Ajuste aprobado", numero: r.transaccion_id }); cargarPendientes(); }
  }
  async function rechazar(a, boton) {
    const d = await Banco.pedirDatos({ titulo: "Rechazar el ajuste " + a.transaccion_id, campos: [{ nombre: "motivo", etiqueta: "Motivo", tipo: "textarea", requerido: true, minimo: 3 }], boton: "Rechazar", peligro: true });
    if (!d) return;
    const r = await Banco.enviar(boton, () => BancoAPI.post("api/supervisor/ajustes/" + a.transaccion_id + "/rechazar", { motivo: d.motivo }));
    if (r) { Banco.aviso("Ajuste " + a.transaccion_id + " rechazado.", "exito"); cargarPendientes(); }
  }
  document.getElementById("recargar").addEventListener("click", cargarPendientes);

  // Reversar
  document.getElementById("form-tx").addEventListener("submit", async (e) => {
    e.preventDefault();
    const id = Banco.datosDe(e.currentTarget).id;
    const error = document.getElementById("tx-error");
    const caja = document.getElementById("tx-detalle");
    if (!/^\d+$/.test(id || "")) { error.textContent = "Escriba el número de la transacción."; return; }
    const t = await Banco.enviar(e.submitter, () => BancoAPI.get("api/supervisor/transacciones/" + id), { errorEn: error });
    if (!t) { caja.hidden = true; return; }
    const reversable = t.estado_codigo === "POSTED" && !t.ya_reversada && t.tipo_codigo !== "REVERSO";
    const boton = el("button", { class: "boton peligro", type: "button", text: "Reversar", disabled: !reversable });
    boton.addEventListener("click", async () => {
      const d = await Banco.pedirDatos({ titulo: "Reversar la transacción " + t.transaccion_id, campos: [{ nombre: "motivo", etiqueta: "Motivo", tipo: "textarea", requerido: true, minimo: 3, max: 140 }], boton: "Revisar", peligro: true });
      if (!d) return;
      const ok = await Banco.confirmar({ titulo: "Confirme el reverso", datos: [["Transacción", String(t.transaccion_id)], ["Tipo", Banco.tipoTexto(t.tipo_codigo)], ["Monto", dinero(t.monto)], ["Motivo", d.motivo]], boton: "Reversar", peligro: true });
      if (!ok) return;
      const r = await Banco.enviar(boton, () => BancoAPI.post("api/supervisor/transacciones/" + t.transaccion_id + "/reversar", { motivo: d.motivo, clave: Banco.clave() }));
      if (r) { await Banco.exito({ titulo: "Transacción reversada", numero: r.reverso_id }); caja.hidden = true; }
    });
    const fila = (k, v) => [el("dt", { text: k }), el("dd", { text: v })];
    // replaceChildren escribe "null" si le llega un null: por eso filtramos lo vacío (lo vimos en la evaluación de B8)
    caja.replaceChildren(...[
      el("div", { class: "fila" }, el("h2", { text: "Transacción " + t.transaccion_id }), Banco.chipEstado(t.estado_codigo)),
      el("dl", { class: "detalle" }, fila("Tipo", Banco.tipoTexto(t.tipo_codigo)), fila("Monto", dinero(t.monto)), fila("Origen", t.cuenta_origen || "—"),
        fila("Destino", t.cuenta_destino || "—"), fila("Descripción", t.descripcion || "—"), fila("Fecha", fecha(t.fecha_contabilizacion || t.fecha_solicitud))),
      reversable ? null : el("p", { class: "suave", text: t.ya_reversada ? "Esta transacción ya fue reversada." : "Solo se pueden reversar transacciones aplicadas que no sean reversos." }),
      el("div", { class: "fila" }, boton)].filter(Boolean));
    caja.hidden = false;
  });

  // Inactivar
  document.getElementById("form-inactivar").addEventListener("submit", async (e) => {
    e.preventDefault();
    const dias = Number(Banco.datosDe(e.currentTarget).dias);
    const caja = document.getElementById("inactivar-resultado");
    const v = await Banco.enviar(e.submitter, () => BancoAPI.get("api/supervisor/inactivar?dias=" + dias));
    if (!v) return;
    const n = v.cuentas_que_se_inactivarian;
    const boton = el("button", { class: "boton peligro", type: "button", text: "Inactivar " + entero(n) + " cuentas", disabled: n === 0 });
    boton.addEventListener("click", async () => {
      const ok = await Banco.confirmar({ titulo: "Inactivar cuentas", texto: "Cada cuenta queda con su evento INACTIVACION. Es un proceso de todo el banco.", datos: [["Días sin movimiento", String(dias)], ["Cuentas", entero(n)]], boton: "Inactivar", peligro: true });
      if (!ok) return;
      const r = await Banco.enviar(boton, () => BancoAPI.post("api/supervisor/inactivar", { dias, confirmar: true }));
      if (r) { await Banco.exito({ titulo: "Proceso terminado", texto: entero(r.cuentas_inactivadas) + " cuentas quedaron inactivas." }); caja.hidden = true; }
    });
    caja.replaceChildren(el("p", {}, "Con ", el("b", { text: String(dias) }), " días sin movimiento quedarían inactivas ", el("span", { class: "cifra grande", text: entero(n) }), " cuentas."), boton);
    caja.hidden = false;
  });

  Banco.secciones((s) => { if (s === "pendientes") cargarPendientes(); });
})();
