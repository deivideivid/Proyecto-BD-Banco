/* Banco Andino · Caja (Cajero y Supervisor): buscar, ficha del cliente, operaciones, nuevo cliente.
   Cada operación pide confirmar, muestra "procesando" mientras la base responde y termina con
   el número de la transacción. El supervisor ve además desbloquear, cambiar límite y cerrar. */
(async function () {
  "use strict";
  const { el, dinero, entero, fecha, chip } = Banco;
  const sesion = await Banco.iniciar({ perfiles: ["CAJERO", "SUPERVISOR"], titulo: "Caja" });
  const esSupervisor = sesion.perfil === "SUPERVISOR";
  const params = () => new URLSearchParams(location.hash.split("?")[1] || "");
  let clienteActual = null;

  if (sesion.oficina) document.getElementById("oficina-texto").textContent =
    "Por número de cuenta, documento o nombre. Las cuentas que puede operar son las de " + sesion.oficina + ".";

  /* ---------- Buscar ---------- */
  async function buscar(q) {
    const caja = document.getElementById("resultados");
    caja.classList.add("cargando");
    try {
      const filas = await BancoAPI.get("api/caja/buscar?q=" + encodeURIComponent(q));
      caja.replaceChildren(Banco.tabla([
        { titulo: "Cliente", valor: (c) => el("a", { href: "#ficha?cliente=" + c.cliente_id, text: c.nombre }) },
        { titulo: "Tipo", valor: (c) => c.tipo_cliente === "NATURAL" ? "Persona natural" : "Empresa" },
        { titulo: "Documento", valor: (c) => c.tipo_documento + " " + c.numero_documento },
        { titulo: "Estado", valor: (c) => chip(c.estado_cliente) },
        { titulo: "Cuentas en su oficina", num: true, campo: "cuentas_en_oficina" },
        { titulo: "", acciones: true, valor: (c) => el("a", { class: "boton secundario chico", href: "#ficha?cliente=" + c.cliente_id, text: "Ver ficha" }) }
      ], filas, { vacio: "No encontramos clientes con ese dato en su oficina." }));
    } catch (e) {
      caja.replaceChildren(el("p", { class: "vacio", text: e.message }));
    } finally { caja.classList.remove("cargando"); }
  }
  document.getElementById("form-buscar").addEventListener("submit", (e) => {
    e.preventDefault();
    const q = document.getElementById("q").value.trim();
    if (q.length >= 3) { history.replaceState(null, "", "#buscar?q=" + encodeURIComponent(q)); buscar(q); }
  });

  /* ---------- Ficha ---------- */
  async function cargarFicha(id) {
    const c = await BancoAPI.get("api/caja/clientes/" + id);
    clienteActual = c;
    document.getElementById("ficha-nombre").textContent = c.nombre;
    document.getElementById("ficha-sub").textContent = (c.tipo_cliente === "NATURAL" ? "Persona natural" : "Empresa") + " · " + c.tipo_documento + " " + c.numero_documento;
    const dato = (t, v) => el("article", { class: "tarjeta" }, el("p", { class: "suave chico", text: t }), el("p", { class: "cifra", text: v || "—" }));
    document.getElementById("ficha-datos").replaceChildren(
      dato("Estado", c.estado_cliente), dato("Municipio", c.municipio), dato("Cliente desde", fecha(c.fecha_vinculacion, false)),
      dato("Correo", c.email), dato("Teléfono", c.telefono), dato("Cuentas", String(c.cuentas.length)));
    pintarCuentas();
  }
  function pintarCuentas() {
    const c = clienteActual;
    const acciones = (cu) => {
      if (!cu.de_mi_oficina) return el("span", { class: "chip neutro", text: "Otra oficina" });
      const b = (texto, fn, clase) => el("button", { class: "boton chico " + (clase || "secundario"), type: "button", text: texto, onclick: (e) => fn(cu, e.currentTarget) });
      const lista = [b("Movimientos", verMovimientos, "fantasma")];
      if (cu.estado_cuenta === "CREADA") lista.push(b("Activar", activar, "primario"));
      if (cu.estado_cuenta === "ACTIVA") lista.push(b("Consignar", consignar, "primario"), b("Retirar", retirar), b("Transferir", transferir), b("Bloquear", bloquear), b("Ajuste", ajuste));
      if (cu.estado_cuenta === "BLOQUEADA") lista.push(b("Consignar", consignar, "primario"), b("Ajuste", ajuste));
      if (esSupervisor) {
        if (cu.estado_cuenta === "BLOQUEADA") lista.push(b("Desbloquear", desbloquear, "destacado"));
        if (["ACTIVA", "BLOQUEADA", "INACTIVA"].includes(cu.estado_cuenta)) lista.push(b("Límite", limite));
        if (cu.estado_cuenta !== "CERRADA") lista.push(b("Cerrar", cerrar, "peligro"));
      }
      return el("div", { class: "fila fin" }, lista);
    };
    document.getElementById("ficha-cuentas").replaceChildren(Banco.tabla([
      { titulo: "Cuenta", valor: (cu) => cu.numero_cuenta },
      { titulo: "Producto", valor: (cu) => cu.producto_codigo + " · " + cu.moneda_codigo + (cu.rol_titular === "COTITULAR" ? " · cotitular" : "") },
      { titulo: "Estado", valor: (cu) => chip(cu.estado_cuenta) },
      { titulo: "Disponible", num: true, valor: (cu) => dinero(cu.saldo_disponible, cu.moneda_codigo) },
      { titulo: "Límite diario", num: true, valor: (cu) => dinero(cu.limite_retiro_diario, cu.moneda_codigo) },
      { titulo: "Acciones", acciones: true, valor: acciones }
    ], c.cuentas, { vacio: "Este cliente todavía no tiene cuentas." }));
  }
  async function refrescar() { if (clienteActual) await cargarFicha(clienteActual.cliente_id); }

  /* ---------- Operaciones ---------- */
  // Flujo común: pedir datos -> confirmar -> procesando -> éxito con número
  async function operar({ boton, titulo, datos, llamada, exitoTitulo, numero, texto }) {
    const ok = await Banco.confirmar({ titulo, datos });
    if (!ok) return null;
    const r = await Banco.enviar(boton, llamada);
    if (r) {
      await Banco.exito({ titulo: exitoTitulo, numero: numero ? numero(r) : undefined, texto: texto ? texto(r) : undefined });
      await refrescar().catch(() => {});
    }
    return r;
  }
  const montoCampo = { nombre: "monto", etiqueta: "Monto", requerido: true, monto: true, inputmode: "decimal" };
  const descCampo = { nombre: "descripcion", etiqueta: "Descripción (opcional)", max: 140 };

  async function consignar(cu, boton) {
    const d = await Banco.pedirDatos({ titulo: "Consignar en " + cu.numero_cuenta, campos: [montoCampo, descCampo], boton: "Revisar" });
    if (!d) return;
    return operar({ boton, titulo: "Confirme la consignación", datos: [["Cuenta", cu.numero_cuenta], ["Monto", dinero(d.monto, cu.moneda_codigo)]],
      llamada: () => BancoAPI.post("api/caja/consignar", { cuenta_id: cu.cuenta_id, monto: d.monto, descripcion: d.descripcion, clave: Banco.clave() }),
      exitoTitulo: "Consignación registrada", numero: (r) => r.transaccion_id, texto: (r) => "Nuevo saldo: " + dinero(r.saldo.saldo_disponible, cu.moneda_codigo) });
  }
  async function retirar(cu, boton) {
    const d = await Banco.pedirDatos({ titulo: "Retirar de " + cu.numero_cuenta, texto: "Disponible: " + dinero(cu.saldo_disponible, cu.moneda_codigo), campos: [montoCampo, descCampo], boton: "Revisar" });
    if (!d) return;
    return operar({ boton, titulo: "Confirme el retiro", datos: [["Cuenta", cu.numero_cuenta], ["Monto", dinero(d.monto, cu.moneda_codigo)]],
      llamada: () => BancoAPI.post("api/caja/retirar", { cuenta_id: cu.cuenta_id, monto: d.monto, descripcion: d.descripcion, clave: Banco.clave() }),
      exitoTitulo: "Retiro registrado", numero: (r) => r.transaccion_id, texto: (r) => "Nuevo saldo: " + dinero(r.saldo.saldo_disponible, cu.moneda_codigo) });
  }
  async function transferir(cu, boton) {
    const d = await Banco.pedirDatos({ titulo: "Transferir desde " + cu.numero_cuenta, campos: [
      { nombre: "numero_destino", etiqueta: "Cuenta destino", requerido: true, inputmode: "numeric", max: 11, patron: "[0-9]{11}", mensaje: "11 dígitos" },
      montoCampo, descCampo], boton: "Revisar" });
    if (!d) return;
    return operar({ boton, titulo: "Confirme la transferencia", datos: [["Desde", cu.numero_cuenta], ["Hacia", d.numero_destino], ["Monto", dinero(d.monto, cu.moneda_codigo)]],
      llamada: () => BancoAPI.post("api/caja/transferir", { cuenta_origen_id: cu.cuenta_id, numero_destino: d.numero_destino, monto: d.monto, descripcion: d.descripcion, clave: Banco.clave() }),
      exitoTitulo: "Transferencia registrada", numero: (r) => r.transaccion_id, texto: (r) => "Nuevo saldo de origen: " + dinero(r.saldo_origen.saldo_disponible, cu.moneda_codigo) });
  }
  async function bloquear(cu, boton) {
    const d = await Banco.pedirDatos({ titulo: "Bloquear " + cu.numero_cuenta, texto: "La cuenta no podrá originar débitos hasta que un supervisor la desbloquee.",
      campos: [{ nombre: "motivo", etiqueta: "Motivo", tipo: "textarea", requerido: true, minimo: 3, max: 200 }], boton: "Revisar", peligro: true });
    if (!d) return;
    return operar({ boton, titulo: "Confirme el bloqueo", datos: [["Cuenta", cu.numero_cuenta], ["Motivo", d.motivo]],
      llamada: () => BancoAPI.post("api/caja/cuentas/" + cu.cuenta_id + "/bloquear", { motivo: d.motivo }), exitoTitulo: "Cuenta bloqueada" });
  }
  async function ajuste(cu, boton) {
    const d = await Banco.pedirDatos({ titulo: "Crear ajuste en " + cu.numero_cuenta, texto: "Queda pendiente: no mueve el saldo hasta que otro supervisor lo apruebe.", campos: [
      { nombre: "sentido", etiqueta: "Sentido", tipo: "select", opciones: [["C", "A favor del cliente (crédito)"], ["D", "En contra del cliente (débito)"]] },
      montoCampo, { nombre: "descripcion", etiqueta: "Descripción", requerido: true, minimo: 3, max: 140 }], boton: "Revisar" });
    if (!d) return;
    return operar({ boton, titulo: "Confirme el ajuste", datos: [["Cuenta", cu.numero_cuenta], ["Sentido", d.sentido === "C" ? "A favor" : "En contra"], ["Monto", dinero(d.monto, cu.moneda_codigo)], ["Descripción", d.descripcion]],
      llamada: () => BancoAPI.post("api/caja/ajustes", { cuenta_id: cu.cuenta_id, monto: d.monto, sentido: d.sentido, descripcion: d.descripcion, clave: Banco.clave() }),
      exitoTitulo: "Ajuste creado (pendiente de aprobación)", numero: (r) => r.transaccion_id });
  }
  async function activar(cu, boton) {
    return operar({ boton, titulo: "Activar la cuenta " + cu.numero_cuenta, datos: [["Producto", cu.producto_codigo + " · " + cu.moneda_codigo]],
      llamada: () => BancoAPI.post("api/caja/cuentas/" + cu.cuenta_id + "/activar"), exitoTitulo: "Cuenta activada" });
  }
  async function desbloquear(cu, boton) {
    return operar({ boton, titulo: "Desbloquear " + cu.numero_cuenta, datos: [["Estado actual", cu.estado_cuenta]],
      llamada: () => BancoAPI.post("api/supervisor/cuentas/" + cu.cuenta_id + "/desbloquear"), exitoTitulo: "Cuenta desbloqueada" });
  }
  async function limite(cu, boton) {
    const d = await Banco.pedirDatos({ titulo: "Cambiar límite diario de " + cu.numero_cuenta, texto: "Límite actual: " + dinero(cu.limite_retiro_diario, cu.moneda_codigo),
      campos: [{ nombre: "nuevo_limite", etiqueta: "Nuevo límite diario", requerido: true, monto: true, inputmode: "decimal" }], boton: "Revisar" });
    if (!d) return;
    return operar({ boton, titulo: "Confirme el nuevo límite", datos: [["Cuenta", cu.numero_cuenta], ["Antes", dinero(cu.limite_retiro_diario, cu.moneda_codigo)], ["Ahora", dinero(d.nuevo_limite, cu.moneda_codigo)]],
      llamada: () => BancoAPI.post("api/supervisor/cuentas/" + cu.cuenta_id + "/limite", { nuevo_limite: d.nuevo_limite }), exitoTitulo: "Límite actualizado" });
  }
  async function cerrar(cu, boton) {
    const ok = await Banco.confirmar({ titulo: "Cerrar la cuenta " + cu.numero_cuenta, texto: "Solo se puede cerrar con saldo 0. No se puede deshacer.",
      datos: [["Saldo contable", dinero(cu.saldo_contable, cu.moneda_codigo)]], boton: "Cerrar cuenta", peligro: true });
    if (!ok) return;
    const r = await Banco.enviar(boton, () => BancoAPI.post("api/supervisor/cuentas/" + cu.cuenta_id + "/cerrar"));
    if (r) { await Banco.exito({ titulo: "Cuenta cerrada" }); await refrescar(); }
  }
  async function verMovimientos(cu) {
    try {
      const d = await BancoAPI.get("api/caja/cuentas/" + cu.cuenta_id);
      Banco.mostrar("Últimos movimientos de " + cu.numero_cuenta, Banco.tabla([
        { titulo: "N.º", campo: "transaccion_id" },
        { titulo: "Fecha", valor: (m) => fecha(m.fecha) },
        { titulo: "Tipo", valor: (m) => Banco.tipoTexto(m.tipo_codigo) },
        { titulo: "Estado", valor: (m) => Banco.chipEstado(m.estado_codigo) },
        { titulo: "Detalle", valor: (m) => m.motivo_rechazo || m.descripcion || "—" },
        { titulo: "Valor", num: true, valor: (m) => el("span", { class: m.sentido === "ENTRA" ? "positivo" : "negativo", text: (m.sentido === "ENTRA" ? "+" : "−") + dinero(m.monto, d.moneda_codigo) }) }
      ], d.movimientos, { vacio: "La cuenta no tiene movimientos." }));
    } catch (e) { Banco.aviso(e.message, "error"); }
  }

  /* ---------- Abrir cuenta ---------- */
  document.getElementById("abrir-cuenta").addEventListener("click", async (e) => {
    if (!clienteActual) return;
    const boton = e.currentTarget;
    const natural = clienteActual.tipo_cliente === "NATURAL";
    const d = await Banco.pedirDatos({ titulo: "Abrir cuenta a " + clienteActual.nombre, texto: "Queda en estado CREADA en su oficina; después se activa.", campos: [
      { nombre: "producto_codigo", etiqueta: "Producto", tipo: "select", opciones: [["AHORROS", "Cuenta de ahorros"], ["CORRIENTE", "Cuenta corriente"]].concat(natural ? [["NOMINA", "Cuenta de nómina"]] : [["EMPRESARIAL", "Cuenta empresarial"]]) },
      { nombre: "moneda_codigo", etiqueta: "Moneda", tipo: "select", opciones: [["COP", "Pesos (COP)"], ["USD", "Dólares (USD)"]] },
      { nombre: "limite_retiro_diario", etiqueta: "Límite de retiro diario", requerido: true, monto: true, inputmode: "decimal", valor: "2000000" },
      { nombre: "cupo_sobregiro", etiqueta: "Cupo de sobregiro (solo corriente)", inputmode: "decimal", valor: "0" }], boton: "Revisar" });
    if (!d) return;
    const cupo = Banco.montoTexto(d.cupo_sobregiro || "0");
    const r = await operar({ boton, titulo: "Confirme la apertura", datos: [["Cliente", clienteActual.nombre], ["Producto", d.producto_codigo + " · " + d.moneda_codigo], ["Límite diario", dinero(d.limite_retiro_diario, d.moneda_codigo)]],
      llamada: () => BancoAPI.post("api/caja/cuentas", { cliente_id: clienteActual.cliente_id, producto_codigo: d.producto_codigo, moneda_codigo: d.moneda_codigo,
                                                        limite_retiro_diario: d.limite_retiro_diario, cupo_sobregiro: cupo }),
      exitoTitulo: "Cuenta abierta", texto: (r) => "Número de cuenta " + r.numero_cuenta + ". Actívela para empezar a usarla." });
    return r;
  });

  /* ---------- Operación rápida por número de cuenta ---------- */
  const tipo = document.getElementById("op-tipo");
  tipo.addEventListener("change", () => { document.getElementById("op-destino").hidden = tipo.value !== "transferir"; });
  async function cuentaPorNumero(numero) {
    const clientes = await BancoAPI.get("api/caja/buscar?q=" + numero);
    if (!clientes.length) throw new Error("No encontramos la cuenta " + numero + " en su oficina.");
    const ficha = await BancoAPI.get("api/caja/clientes/" + clientes[0].cliente_id);
    const cu = ficha.cuentas.find((x) => x.numero_cuenta === numero);
    if (!cu) throw new Error("No encontramos la cuenta " + numero + ".");
    return { cu, ficha };
  }
  document.getElementById("form-operacion").addEventListener("submit", async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const error = document.getElementById("op-error");
    const boton = document.getElementById("op-enviar");
    const d = Banco.datosDe(form);
    error.textContent = "";
    d.monto = Banco.montoTexto(d.monto);
    if (!/^[0-9]{11}$/.test(d.numero || "")) { error.textContent = "El número de cuenta tiene 11 dígitos."; return; }
    if (d.tipo === "transferir" && !/^[0-9]{11}$/.test(d.numero_destino || "")) { error.textContent = "La cuenta destino tiene 11 dígitos."; return; }
    if (!/^\d+(\.\d{1,2})?$/.test(d.monto || "") || Number(d.monto) <= 0) { error.textContent = "Escriba un monto mayor que cero, con máximo dos decimales."; return; }
    const encontrada = await Banco.enviar(boton, () => cuentaPorNumero(d.numero), { errorEn: error });
    if (!encontrada) return;
    const { cu, ficha } = encontrada;
    const nombres = { consignar: "consignación", retirar: "retiro", transferir: "transferencia" };
    const datos = [["Cliente", ficha.nombre], ["Cuenta", cu.numero_cuenta + " · " + cu.estado_cuenta], ["Monto", dinero(d.monto, cu.moneda_codigo)]];
    if (d.tipo === "transferir") datos.push(["Hacia", d.numero_destino]);
    const ruta = { consignar: "api/caja/consignar", retirar: "api/caja/retirar", transferir: "api/caja/transferir" }[d.tipo];
    const cuerpo = d.tipo === "transferir"
      ? { cuenta_origen_id: cu.cuenta_id, numero_destino: d.numero_destino, monto: d.monto, descripcion: d.descripcion, clave: Banco.clave() }
      : { cuenta_id: cu.cuenta_id, monto: d.monto, descripcion: d.descripcion, clave: Banco.clave() };
    const ok = await Banco.confirmar({ titulo: "Confirme la " + nombres[d.tipo], datos });
    if (!ok) return;
    const r = await Banco.enviar(boton, () => BancoAPI.post(ruta, cuerpo), { errorEn: error });
    if (!r) return;
    form.reset();
    document.getElementById("op-destino").hidden = true;
    const saldo = r.saldo || r.saldo_origen;
    await Banco.exito({ titulo: "Operación registrada", numero: r.transaccion_id, texto: "Nuevo saldo: " + dinero(saldo.saldo_disponible, cu.moneda_codigo) });
  });

  /* ---------- Nuevo cliente ---------- */
  const municipios = new Map();
  let ultimoTexto = "";
  document.querySelectorAll('input[name="municipio"]').forEach((inp) => inp.addEventListener("input", async () => {
    const q = inp.value.trim();
    if (q.length < 2 || q === ultimoTexto || municipios.has(q)) return;
    ultimoTexto = q;
    try {
      const lista = await BancoAPI.get("api/caja/municipios?q=" + encodeURIComponent(q.split(" (")[0]));
      document.getElementById("municipios").replaceChildren(...lista.map((m) => {
        const texto = m.nombre + " (" + m.departamento + ")";
        municipios.set(texto, m.municipio_codigo);
        return el("option", { value: texto });
      }));
    } catch (_) { /* sin sugerencias */ }
  }));
  document.querySelectorAll('[data-tipo]').forEach((b) => b.addEventListener("click", () => {
    document.querySelectorAll('[data-tipo]').forEach((x) => x.setAttribute("aria-selected", String(x === b)));
    document.getElementById("form-natural").hidden = b.dataset.tipo !== "natural";
    document.getElementById("form-juridico").hidden = b.dataset.tipo !== "juridico";
  }));
  for (const [id, ruta] of [["form-natural", "api/caja/clientes/natural"], ["form-juridico", "api/caja/clientes/juridico"]]) {
    document.getElementById(id).addEventListener("submit", async (e) => {
      e.preventDefault();
      const form = e.currentTarget;
      const error = form.querySelector(".mensaje-error");
      const d = Banco.datosDe(form);
      d.municipio_codigo = municipios.get(d.municipio);
      delete d.municipio;
      if (!d.municipio_codigo) { error.textContent = "Escoja el municipio de la lista."; return; }
      if (d.numero_documento) d.numero_documento = d.numero_documento.toUpperCase();
      const nombre = d.nombres ? d.nombres + " " + d.apellidos : d.razon_social;
      const ok = await Banco.confirmar({ titulo: "Confirme el registro", datos: [["Cliente", nombre || "—"], ["Documento", d.numero_documento || ("NIT " + d.nit)]] });
      if (!ok) return;
      const r = await Banco.enviar(form.querySelector('button[type="submit"]'), () => BancoAPI.post(ruta, d), { errorEn: error });
      if (!r) return;
      form.reset();
      await Banco.exito({ titulo: "Cliente registrado", texto: "Ahora puede abrirle una cuenta." });
      location.hash = "#ficha?cliente=" + r.cliente_id;
    });
  }

  Banco.secciones((s) => {
    const p = params();
    if (s === "buscar" && p.get("q")) { document.getElementById("q").value = p.get("q"); buscar(p.get("q")); }
    if (s === "ficha") {
      if (p.get("cliente")) cargarFicha(p.get("cliente")).catch((e) => Banco.aviso(e.message, "error"));
      else location.hash = "#buscar";
    }
  });
})();
