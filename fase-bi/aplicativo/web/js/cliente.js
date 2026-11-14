/* Banco Andino · Cliente (banca en línea): mis cuentas, movimientos, transferir y mis estadísticas.
   Todo pasa por /api/cliente, que en la base revisa que cada cuenta sea del cliente. */
(async function () {
  "use strict";
  const { el, dinero, fecha, chip } = Banco;
  const sesion = await Banco.iniciar({ perfiles: ["CLIENTE"], titulo: "Banca en línea" });
  let cuentas = [];
  let grafica = null;
  const parametros = () => new URLSearchParams(location.hash.split("?")[1] || "");

  document.getElementById("saludo").textContent = "Hola, " + sesion.nombre.split(" ")[0] + ". Estas son sus cuentas y su saldo disponible.";

  async function cargarCuentas() {
    cuentas = await BancoAPI.get("api/cliente/cuentas");
    const lista = document.getElementById("lista-cuentas");
    lista.replaceChildren(...cuentas.map((c) => {
      const saldo = el("span", { class: "cifra grande" });
      Banco.contar(saldo, c.saldo_disponible, (v) => dinero(v, c.moneda));
      return el("article", { class: "tarjeta cuenta" },
        el("div", { class: "fila" }, el("h3", { text: c.producto }), chip(c.estado)),
        el("div", { class: "numero-cuenta", text: "N.º " + c.numero_cuenta + (c.rol_titular === "COTITULAR" ? " · cotitular" : "") }),
        el("p", { class: "suave chico", text: "Saldo disponible" }), saldo, el("span", { class: "raya-acento" }),
        el("p", { class: "suave chico", text: "Saldo contable " + dinero(c.saldo_contable, c.moneda) }),
        el("div", { class: "fila" },
          el("a", { class: "boton secundario chico", href: "#movimientos?cuenta=" + c.cuenta_id, text: "Movimientos" }),
          c.estado === "ACTIVA" ? el("a", { class: "boton primario chico", href: "#transferir?origen=" + c.cuenta_id, text: "Transferir" }) : null));
    }));
    const opciones = (filtro) => cuentas.filter(filtro).map((c) => el("option", { value: c.cuenta_id, text: c.producto + " · " + c.numero_cuenta + " · " + dinero(c.saldo_disponible, c.moneda) }));
    document.getElementById("mov-cuenta").replaceChildren(...opciones(() => true));
    document.getElementById("tr-origen").replaceChildren(...opciones((c) => c.estado === "ACTIVA"));
    mostrarDisponible();
  }

  function mostrarDisponible() {
    const c = cuentas.find((x) => String(x.cuenta_id) === document.getElementById("tr-origen").value);
    document.getElementById("tr-disponible").textContent = c ? "Disponible: " + dinero(c.saldo_disponible, c.moneda) : "";
  }
  document.getElementById("tr-origen").addEventListener("change", mostrarDisponible);

  async function cargarMovimientos() {
    const f = Banco.datosDe(document.getElementById("form-movimientos"));
    const caja = document.getElementById("lista-movimientos");
    if (!f.cuenta) return;
    caja.classList.add("cargando");
    try {
      const q = new URLSearchParams({ limite: "100" });
      if (f.desde) q.set("desde", f.desde);
      if (f.hasta) q.set("hasta", f.hasta);
      const movs = await BancoAPI.get("api/cliente/cuentas/" + f.cuenta + "/movimientos?" + q);
      const moneda = (cuentas.find((c) => String(c.cuenta_id) === String(f.cuenta)) || {}).moneda;
      caja.replaceChildren(Banco.tabla([
        { titulo: "Fecha", valor: (m) => fecha(m.fecha) },
        { titulo: "Movimiento", valor: (m) => m.descripcion || m.tipo },
        { titulo: "Contraparte", valor: (m) => m.contraparte || "—" },
        { titulo: "Estado", valor: (m) => chip(m.estado === "POSTED" ? "Aplicado" : m.estado === "REJECTED" ? "Rechazado" : "Pendiente", m.estado) },
        { titulo: "Valor", num: true, valor: (m) => el("span", { class: Number(m.valor) < 0 ? "negativo" : "positivo", text: (Number(m.valor) > 0 ? "+" : "") + dinero(m.valor, moneda) }) }
      ], movs, { vacio: "No hay movimientos en esas fechas." }));
    } catch (e) {
      caja.replaceChildren(el("p", { class: "vacio", text: e.message }));
    } finally { caja.classList.remove("cargando"); }
  }
  document.getElementById("form-movimientos").addEventListener("submit", (e) => { e.preventDefault(); cargarMovimientos(); });

  document.getElementById("form-transferir").addEventListener("submit", async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const d = Banco.datosDe(form);
    const error = document.getElementById("tr-error");
    error.textContent = "";
    d.monto = Banco.montoTexto(d.monto);
    if (!/^[0-9]{11}$/.test(d.numero_destino || "")) { error.textContent = "El número de la cuenta destino tiene 11 dígitos."; return; }
    if (!/^\d+(\.\d{1,2})?$/.test(d.monto || "") || Number(d.monto) <= 0) { error.textContent = "Escriba un monto mayor que cero, con máximo dos decimales."; return; }
    const origen = cuentas.find((c) => String(c.cuenta_id) === d.cuenta_origen_id);
    const ok = await Banco.confirmar({ titulo: "Confirme la transferencia", datos: [
      ["Desde", origen.producto + " " + origen.numero_cuenta], ["Hacia", d.numero_destino],
      ["Monto", dinero(d.monto, origen.moneda)], ["Descripción", d.descripcion || "Transferencia por banca en línea"]],
      boton: "Transferir" });
    if (!ok) return;
    const r = await Banco.enviar(document.getElementById("tr-enviar"), () => BancoAPI.post("api/cliente/transferir", {
      cuenta_origen_id: Number(d.cuenta_origen_id), numero_destino: d.numero_destino, monto: d.monto,
      descripcion: d.descripcion, clave: Banco.clave() }), { errorEn: error });
    if (!r) { cargarCuentas(); return; }
    form.reset();
    await Banco.exito({ titulo: "Transferencia exitosa", numero: r.transaccion_id,
      texto: "Nuevo saldo disponible: " + dinero(r.cuenta_origen.saldo_disponible, r.cuenta_origen.moneda) });
    await cargarCuentas();
  });

  async function cargarEstadisticas() {
    const datos = await BancoAPI.get("api/cliente/resumen");
    const ultimos = datos.slice(-12);
    const suma = (k) => ultimos.reduce((a, x) => a + Number(x[k]), 0).toFixed(2);
    const entradas = suma("entradas"), salidas = suma("salidas");
    const tarjeta = (titulo, valor, clase) => {
      const c = el("span", { class: "cifra grande " + (clase || "") });
      Banco.contar(c, valor, (v) => dinero(v, "COP"));
      return el("article", { class: "tarjeta" }, el("p", { class: "suave chico", text: titulo }), c, el("span", { class: "raya-acento" }));
    };
    document.getElementById("est-totales").replaceChildren(
      tarjeta("Entró en los últimos 12 meses con movimiento", entradas, "positivo"),
      tarjeta("Salió en ese mismo periodo", salidas, "negativo"),
      tarjeta("Diferencia", (Number(entradas) - Number(salidas)).toFixed(2)));
    const css = getComputedStyle(document.documentElement);
    if (grafica) grafica.destroy();
    grafica = new Chart(document.getElementById("est-grafica"), {
      type: "bar",
      data: { labels: ultimos.map((x) => x.anio_mes), datasets: [
        { label: "Entradas", data: ultimos.map((x) => Number(x.entradas)), backgroundColor: css.getPropertyValue("--secundario").trim(), borderRadius: 6 },
        { label: "Salidas", data: ultimos.map((x) => Number(x.salidas)), backgroundColor: css.getPropertyValue("--acento").trim(), borderRadius: 6 }] },
      options: { responsive: true, maintainAspectRatio: false,
        animation: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? false : { duration: 450 },
        plugins: { tooltip: { callbacks: { label: (i) => i.dataset.label + ": " + dinero(i.parsed.y.toFixed(2), "COP") } } },
        scales: { y: { ticks: { callback: (v) => (v >= 1e6 ? (v / 1e6).toLocaleString("es-CO") + " M" : Number(v).toLocaleString("es-CO")) } } } }
    });
  }

  await cargarCuentas();
  Banco.secciones((s) => {
    const p = parametros();
    if (s === "movimientos" && p.get("cuenta")) { document.getElementById("mov-cuenta").value = p.get("cuenta"); cargarMovimientos(); }
    if (s === "movimientos" && !p.get("cuenta") && cuentas.length) cargarMovimientos();
    if (s === "transferir" && p.get("origen")) { document.getElementById("tr-origen").value = p.get("origen"); mostrarDisponible(); }
    if (s === "estadisticas") cargarEstadisticas().catch((e) => Banco.aviso(e.message, "error"));
  });
})();
