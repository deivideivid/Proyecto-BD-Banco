/* =====================================================================
   Banco Andino · Marco común de las pantallas (B6)
   - Arma la barra superior, el menú lateral plegable (como el de Opera) y, en celular,
     el menú que sale encima del contenido y la barra de abajo con los accesos más usados.
   - Trae ayudas que usan todas las pantallas: formato de dinero, ventanas de confirmar y de
     éxito, avisos, botones "procesando" y el cambio de sección por la dirección (#seccion).
   Todo el texto que viene del servidor se pone con textContent (nunca como HTML).
   ===================================================================== */
(function () {
  "use strict";

  /* ---------- Íconos de línea, todos del mismo estilo ---------- */
  const TRAZOS = {
    inicio: "M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z",
    cuentas: "M3 7h15a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3z M3 7l12-3v3 M16 13.5h2",
    movimientos: "M8 6h13 M8 12h13 M8 18h13 M3.5 6h.01 M3.5 12h.01 M3.5 18h.01",
    transferir: "M7 7h13l-4-4 M17 17H4l4 4",
    estadisticas: "M4 20V10 M10 20V4 M16 20v-7 M22 20H2",
    buscar: "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z M21 21l-5-5",
    usuario_mas: "M15 19a6 6 0 0 0-12 0 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M19 8v6 M16 11h6",
    caja: "M3 6h18v12H3z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6.5 9h.01 M17.5 15h.01",
    aprobaciones: "M9 11l3 3 8-8 M20 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11",
    reversar: "M3 12a9 9 0 1 0 3-6.7 M3 4v5h5",
    inactivar: "M10 9v6 M14 9v6 M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z",
    calidad: "M12 3l8 3v6c0 4.5-3.3 8.3-8 9-4.7-.7-8-4.5-8-9V6z M9 12l2 2 4-4",
    cuadres: "M12 3v18 M6 21h12 M5 7h14 M5 7l-3 7a3 3 0 0 0 6 0z M19 7l-3 7a3 3 0 0 0 6 0z",
    bitacora: "M9 4h6v3H9z M8 5H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2 M8 12h8 M8 16h5",
    ingresos: "M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4 M10 17l5-5-5-5 M15 12H3",
    ficha: "M3 5h18v14H3z M8 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4z M5 16a3 3 0 0 1 6 0 M14 9h4 M14 13h4",
    equipo: "M17 21a5 5 0 0 0-10 0 M12 13a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M22 20a4 4 0 0 0-3.5-4 M17 4.5a3 3 0 0 1 0 5.6 M2 20a4 4 0 0 1 3.5-4 M7 4.5a3 3 0 0 0 0 5.6",
    tecnologias: "M8 9l-3 3 3 3 M16 9l3 3-3 3 M13.5 5l-3 14",
    salir: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4 M16 17l5-5-5-5 M21 12H9",
    menu: "M4 6h16 M4 12h16 M4 18h16",
    candado: "M6 11h12v10H6z M8 11V7a4 4 0 0 1 8 0v4",
    mas: "M12 5v14 M5 12h14",
    llave: "M15 7a4 4 0 1 1-3.9 5H4v3H2v-5h9.1A4 4 0 0 1 15 7z",
    documento: "M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z M14 3v6h6 M9 13h6 M9 17h6"
  };
  function icono(nombre) {
    const d = TRAZOS[nombre] || TRAZOS.documento;
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + d + '"/></svg>';
  }
  const LOGO = '<svg class="logo" viewBox="0 0 32 32" aria-hidden="true"><path d="M3 25 L12 10 L17 18 L21 12 L29 25 Z" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/><path d="M2 28 H30" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>';

  /* ---------- Menú de cada perfil (abajo = acceso en la barra del celular) ---------- */
  const COMUNES = [
    { grupo: "El proyecto" },
    { nombre: "Equipo", href: "equipo.html", icono: "equipo" },
    { nombre: "Tecnologías", href: "tecnologias.html", icono: "tecnologias" }
  ];
  const MENUS = {
    PUBLICO: [
      { nombre: "Inicio", href: "index.html", icono: "inicio", abajo: true },
      { nombre: "Ingresar", href: "ingresar.html", icono: "ingresos", abajo: true },
      { nombre: "Equipo", href: "equipo.html", icono: "equipo", abajo: true },
      { nombre: "Tecnologías", href: "tecnologias.html", icono: "tecnologias", abajo: true }
    ],
    CLIENTE: [
      { grupo: "Banca en línea" },
      { nombre: "Mis cuentas", href: "cliente.html#cuentas", icono: "cuentas", abajo: true, corto: "Cuentas" },
      { nombre: "Movimientos", href: "cliente.html#movimientos", icono: "movimientos", abajo: true },
      { nombre: "Transferir", href: "cliente.html#transferir", icono: "transferir", abajo: true },
      { nombre: "Mis estadísticas", href: "cliente.html#estadisticas", icono: "estadisticas", abajo: true, corto: "Estadísticas" }
    ],
    CAJERO: [
      { grupo: "Caja" },
      { nombre: "Buscar cliente", href: "caja.html#buscar", icono: "buscar", abajo: true },
      { nombre: "Operación de caja", href: "caja.html#operacion", icono: "caja", abajo: true, corto: "Operación" },
      { nombre: "Nuevo cliente", href: "caja.html#nuevo", icono: "usuario_mas", abajo: true }
    ],
    SUPERVISOR: [
      { grupo: "Caja" },
      { nombre: "Buscar cliente", href: "caja.html#buscar", icono: "buscar", abajo: true },
      { nombre: "Operación de caja", href: "caja.html#operacion", icono: "caja" },
      { nombre: "Nuevo cliente", href: "caja.html#nuevo", icono: "usuario_mas" },
      { grupo: "Supervisión" },
      { nombre: "Pendientes de aprobar", href: "supervisor.html#pendientes", icono: "aprobaciones", abajo: true },
      { nombre: "Reversar", href: "supervisor.html#reversar", icono: "reversar", abajo: true },
      { nombre: "Inactivar cuentas", href: "supervisor.html#inactivar", icono: "inactivar" },
      { nombre: "Estadísticas de la oficina", href: "estadisticas.html#resumen", icono: "estadisticas", abajo: true }
    ],
    AUDITOR: [
      { grupo: "Auditoría de datos" },
      { nombre: "Calidad de datos", href: "auditor.html#calidad", icono: "calidad", abajo: true, corto: "Calidad" },
      { nombre: "Cuadres", href: "auditor.html#cuadres", icono: "cuadres", abajo: true },
      { nombre: "Bitácora", href: "auditor.html#bitacora", icono: "bitacora", abajo: true },
      { nombre: "Ingresos al aplicativo", href: "auditor.html#ingresos", icono: "ingresos" },
      { nombre: "Control y calidad (tablero)", href: "estadisticas.html#control", icono: "estadisticas", abajo: true, corto: "Tablero" }
    ],
    ADMINISTRADOR: [
      { grupo: "Seguridad" },
      { nombre: "Usuarios y roles", href: "admin.html#usuarios", icono: "ficha", abajo: true, corto: "Usuarios" },
      { nombre: "Nuevo usuario", href: "admin.html#nuevo", icono: "usuario_mas", abajo: true, corto: "Nuevo" },
      { nombre: "Accesos al aplicativo", href: "admin.html#accesos", icono: "llave", abajo: true, corto: "Accesos" },
      { nombre: "Estadísticas", href: "estadisticas.html#resumen", icono: "estadisticas", abajo: true, corto: "Estadísticas" }
    ]
  };
  const INICIO = {
    CLIENTE: "cliente.html#cuentas", CAJERO: "caja.html#buscar", SUPERVISOR: "supervisor.html#pendientes",
    AUDITOR: "auditor.html#calidad", ADMINISTRADOR: "admin.html#usuarios"
  };
  const NOMBRE_PERFIL = { CLIENTE: "Cliente", CAJERO: "Cajero", SUPERVISOR: "Supervisor", AUDITOR: "Auditor de datos", ADMINISTRADOR: "Administrador" };

  /* ---------- Pequeñas ayudas ---------- */
  function el(tag, props, ...hijos) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v === undefined || v === null || v === false) continue;
      if (k === "class") e.className = v;
      else if (k === "text") e.textContent = v;
      else if (k === "html") e.innerHTML = v;              // solo para íconos propios
      else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
      else if (k === "dataset") Object.assign(e.dataset, v);
      else e.setAttribute(k, v === true ? "" : v);
    }
    for (const h of hijos.flat(Infinity)) if (h !== null && h !== undefined && h !== false) e.append(h instanceof Node ? h : document.createTextNode(String(h)));
    return e;
  }
  const leer = (k) => { try { return localStorage.getItem(k); } catch (_) { return null; } };
  const guardar = (k, v) => { try { localStorage.setItem(k, v); } catch (_) { /* sin almacenamiento */ } };
  const reducirMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Dinero exacto desde texto: "1767796946066.07" -> "1.767.796.946.066,07" (sin coma flotante) */
  function numero(texto, decimales) {
    if (texto === null || texto === undefined || texto === "") return "—";
    let s = String(texto).trim();
    const negativo = s.startsWith("-");
    if (negativo) s = s.slice(1);
    let [ent, dec = ""] = s.split(".");
    if (dec.length > decimales) { [ent, dec] = Number(s).toFixed(decimales).split("."); dec = dec || ""; }
    ent = ent.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    return (negativo ? "-" : "") + ent + (decimales > 0 ? "," + (dec + "0".repeat(decimales)).slice(0, decimales) : "");
  }
  function dinero(texto, moneda) { return numero(texto, 2) + " " + (moneda || "COP"); }
  function entero(texto) { return numero(texto, 0); }
  const FECHA = new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
  const SOLO_FECHA = new Intl.DateTimeFormat("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "short", year: "numeric" });
  function fecha(iso, conHora = true) {
    if (!iso) return "—";
    const d = new Date(iso);
    return isNaN(d) ? String(iso) : (conHora ? FECHA : SOLO_FECHA).format(d);
  }
  function clave() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    const b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
    return h.slice(0, 8) + "-" + h.slice(8, 12) + "-" + h.slice(12, 16) + "-" + h.slice(16, 20) + "-" + h.slice(20);
  }
  /* Cifra que cuenta hasta su valor (menos de medio segundo) */
  function contar(nodo, valorTexto, formato) {
    const final = formato(valorTexto);
    const destino = Number(valorTexto);
    if (reducirMovimiento || !isFinite(destino) || destino === 0) { nodo.textContent = final; return; }
    const inicio = performance.now(), dur = 450;
    const paso = (t) => {
      const p = Math.min(1, (t - inicio) / dur), e = 1 - Math.pow(1 - p, 3);
      nodo.textContent = p < 1 ? formato((destino * e).toFixed(2)) : final;
      if (p < 1) requestAnimationFrame(paso);
    };
    requestAnimationFrame(paso);
  }

  /* ---------- Avisos, ventanas y botones ---------- */
  function avisos() {
    let c = document.querySelector(".avisos");
    if (!c) { c = el("div", { class: "avisos", "aria-live": "polite" }); document.body.append(c); }
    return c;
  }
  function aviso(texto, tipo) {
    const a = el("div", { class: "aviso-flotante " + (tipo || ""), role: tipo === "error" ? "alert" : "status", text: texto });
    avisos().append(a);
    setTimeout(() => a.remove(), tipo === "error" ? 7000 : 4500);
  }
  function ventana(contenido, { centrada = false } = {}) {
    const fondo = el("div", { class: "ventana-fondo" });
    const caja = el("div", { class: "ventana" + (centrada ? " centrada" : ""), role: "dialog", "aria-modal": "true" }, contenido);
    fondo.append(caja);
    document.body.append(fondo);
    const foco = caja.querySelector("button.primario, button");
    if (foco) setTimeout(() => foco.focus(), 30);
    return fondo;
  }
  /* Antes de cada operación: muestra los datos y pide confirmar */
  function confirmar({ titulo, texto, datos = [], boton = "Confirmar", peligro = false }) {
    return new Promise((resolver) => {
      let fondo;
      const cerrar = (v) => { document.removeEventListener("keydown", tecla); fondo.remove(); resolver(v); };
      const tecla = (e) => { if (e.key === "Escape") cerrar(false); };
      const lista = el("dl", {}, datos.map(([k, v]) => [el("dt", { text: k }), el("dd", { text: v })]));
      fondo = ventana([
        el("h2", { text: titulo }),
        texto ? el("p", { class: "suave", text: texto }) : null,
        datos.length ? lista : null,
        el("div", { class: "fila" },
          el("button", { class: "boton secundario", type: "button", text: "Cancelar", onclick: () => cerrar(false) }),
          el("button", { class: "boton " + (peligro ? "peligro" : "primario"), type: "button", text: boton, onclick: () => cerrar(true) }))
      ]);
      fondo.addEventListener("click", (e) => { if (e.target === fondo) cerrar(false); });
      document.addEventListener("keydown", tecla);
    });
  }
  /* Formulario en ventana. campos: [{nombre, etiqueta, tipo, opciones:[[valor, texto]], requerido, ayuda, valor, patron}]
     Devuelve los datos escritos, o null si cancela. */
  function pedirDatos({ titulo, texto, campos, boton = "Continuar", peligro = false }) {
    return new Promise((resolver) => {
      let fondo;
      const cerrar = (v) => { document.removeEventListener("keydown", tecla); fondo.remove(); resolver(v); };
      const tecla = (e) => { if (e.key === "Escape") cerrar(null); };
      const error = el("p", { class: "mensaje-error", role: "alert" });
      const form = el("form", { class: "formulario", novalidate: true },
        campos.map((c) => {
          let control;
          if (c.tipo === "select") control = el("select", { name: c.nombre }, (c.opciones || []).map(([v, t]) => el("option", { value: v, text: t })));
          else if (c.tipo === "textarea") control = el("textarea", { name: c.nombre, rows: 3, maxlength: c.max || 200 });
          else control = el("input", { name: c.nombre, type: c.tipo || "text", inputmode: c.inputmode, maxlength: c.max, min: c.min, placeholder: c.placeholder || "" });
          if (c.valor !== undefined && c.valor !== null) control.value = c.valor;
          return el("label", { class: "campo" + (c.monto ? " monto" : "") }, c.etiqueta, control, c.ayuda ? el("span", { class: "ayuda", text: c.ayuda }) : null);
        }),
        error,
        el("div", { class: "fila" },
          el("button", { class: "boton secundario", type: "button", text: "Cancelar", onclick: () => cerrar(null) }),
          el("button", { class: "boton " + (peligro ? "peligro" : "primario"), type: "submit", text: boton })));
      form.addEventListener("submit", (e) => {
        e.preventDefault();
        const d = datosDe(form);
        for (const c of campos) {
          let v = d[c.nombre];
          if (c.monto && v) v = d[c.nombre] = montoTexto(v);
          if (c.requerido && !v) { error.textContent = "Falta: " + c.etiqueta + "."; return; }
          if (c.monto && v && (!/^\d+(\.\d{1,2})?$/.test(v) || Number(v) <= 0)) { error.textContent = c.etiqueta + ": un valor mayor que cero, con máximo dos decimales."; return; }
          if (c.patron && v && !new RegExp("^(" + c.patron + ")$").test(v)) { error.textContent = c.etiqueta + ": " + (c.mensaje || "formato no válido") + "."; return; }
          if (c.minimo && v && v.length < c.minimo) { error.textContent = c.etiqueta + ": mínimo " + c.minimo + " caracteres."; return; }
        }
        cerrar(d);
      });
      fondo = ventana([el("h2", { text: titulo }), texto ? el("p", { class: "suave", text: texto }) : null, form]);
      fondo.addEventListener("click", (e) => { if (e.target === fondo) cerrar(null); });
      document.addEventListener("keydown", tecla);
      const primero = form.querySelector("input, select, textarea");
      if (primero) setTimeout(() => primero.focus(), 40);
    });
  }
  /* Ventana solo para mostrar algo (por ejemplo, los movimientos de una cuenta) */
  function mostrar(titulo, contenido) {
    let fondo;
    const cerrar = () => fondo.remove();
    fondo = ventana([el("h2", { text: titulo }), contenido,
      el("div", { class: "fila" }, el("button", { class: "boton primario", type: "button", text: "Cerrar", onclick: cerrar }))]);
    fondo.querySelector(".ventana").classList.add("ancha");
    fondo.addEventListener("click", (e) => { if (e.target === fondo) cerrar(); });
  }

  /* Al terminar: marca de éxito animada con el número de la transacción */
  function exito({ titulo, texto, numero: num, extra }) {
    return new Promise((resolver) => {
      const marca = '<svg class="marca-exito" viewBox="0 0 74 74" aria-hidden="true"><circle cx="37" cy="37" r="34"/><path d="M23 38l9 9 19-20"/></svg>';
      let fondo;
      const cerrar = () => { fondo.remove(); resolver(); };
      fondo = ventana([
        el("div", { html: marca }),
        el("h2", { text: titulo }),
        texto ? el("p", { class: "suave", text: texto }) : null,
        num !== undefined && num !== null ? el("p", {}, "Número de la transacción ", el("span", { class: "numero", text: String(num) })) : null,
        extra || null,
        el("div", { class: "fila centro" }, el("button", { class: "boton primario", type: "button", text: "Listo", onclick: cerrar }))
      ], { centrada: true });
    });
  }
  /* Corre una operación: botón en "procesando", errores en lenguaje sencillo y la tarjeta se sacude */
  async function enviar(boton, operacion, { errorEn, sacudir } = {}) {
    if (errorEn) errorEn.textContent = "";
    const textoOriginal = boton ? boton.textContent : "";
    if (boton) { boton.classList.add("procesando"); boton.disabled = true; boton.textContent = "Procesando…"; }
    try {
      return await operacion();
    } catch (e) {
      if (e.name === "AbortError") return null;
      let m = e.message;
      if (e.detalle && e.detalle.rechazo_id) m += " (quedó registrado el rechazo n.º " + e.detalle.rechazo_id + ")";
      if (errorEn) errorEn.textContent = m; else aviso(m, "error");
      const s = sacudir || (boton && boton.closest(".tarjeta, .ventana"));
      if (s) { s.classList.remove("sacudir"); void s.offsetWidth; s.classList.add("sacudir"); }
      return null;
    } finally {
      if (boton) { boton.classList.remove("procesando"); boton.disabled = false; boton.textContent = textoOriginal; }
    }
  }
  /* Lee un formulario como objeto (vacíos = null) */
  function datosDe(form) {
    const o = {};
    for (const [k, v] of new FormData(form).entries()) o[k] = typeof v === "string" ? (v.trim() === "" ? null : v.trim()) : v;
    return o;
  }
  /* Monto tal como lo escribe la persona en Colombia: "1.250.000,50" -> "1250000.50" */
  function montoTexto(v) {
    if (v === null || v === undefined) return null;
    let s = String(v).replace(/\s|\$/g, "");
    if (s.includes(",")) s = s.replace(/\./g, "").replace(",", ".");
    else if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, "");
    return s;
  }

  /* ---------- Tablas que en celular se vuelven tarjetas ---------- */
  /* En el celular las tablas se ven como tarjetas (la primera columna es el título de cada una)
     y, si son largas, mostramos de a 10 con un botón para ver más. En computador se ven todas. */
  const POR_TANDA_CELULAR = 10;
  function tabla(columnas, filas, { vacio = "No hay datos." } = {}) {
    if (!filas.length) return el("p", { class: "vacio", text: vacio });
    const enCelular = window.matchMedia("(max-width: 900px)").matches;
    let visibles = enCelular ? POR_TANDA_CELULAR : filas.length;
    const thead = el("thead", {}, el("tr", {}, columnas.map((c) => el("th", { class: c.num ? "num" : null, text: c.titulo }))));
    const tbody = el("tbody", {}, filas.map((f, n) => el("tr", { class: n >= visibles ? "fila-oculta" : null }, columnas.map((c, i) => {
      const td = el("td", { class: (c.num ? "num " : "") + (c.acciones ? "acciones " : "") + (i === 0 && !c.acciones ? "titulo-fila" : ""), "data-col": c.titulo });
      const v = c.valor ? c.valor(f) : f[c.campo];
      if (v instanceof Node) td.append(v); else if (Array.isArray(v)) td.append(...v); else td.textContent = v === null || v === undefined ? "—" : v;
      return td;
    }))));
    const caja = el("div", { class: "tabla-caja" }, el("table", { class: "tabla responsiva" }, thead, tbody));
    if (filas.length > visibles) {
      const mas = el("button", { class: "boton secundario mas-filas", type: "button" });
      const texto = () => { const quedan = filas.length - visibles; mas.textContent = "Mostrar " + Math.min(POR_TANDA_CELULAR, quedan) + " más (quedan " + quedan + ")"; };
      mas.addEventListener("click", () => {
        visibles += POR_TANDA_CELULAR;
        [...tbody.children].forEach((tr, n) => tr.classList.toggle("fila-oculta", n >= visibles));
        if (visibles >= filas.length) mas.remove(); else texto();
      });
      texto();
      caja.append(el("p", { class: "conteo-filas", text: "Mostrando " + visibles + " de " + filas.length }), mas);
      const conteo = caja.querySelector(".conteo-filas");
      mas.addEventListener("click", () => { conteo.textContent = visibles >= filas.length ? filas.length + " en total" : "Mostrando " + visibles + " de " + filas.length; });
    }
    return caja;
  }
  function chip(texto, clase) { return el("span", { class: "chip " + (clase || texto), text: texto }); }
  /* Estados y tipos de transacción en español (la base guarda el código; el color sale del código) */
  const ESTADO_TX = { POSTED: "Aplicada", REJECTED: "Rechazada", PENDING_APPROVAL: "Pendiente de aprobación" };
  const TIPO_TX = { CONSIGNACION: "Consignación", RETIRO: "Retiro", TRANSFERENCIA: "Transferencia", AJUSTE: "Ajuste",
                    REVERSO: "Reverso", CREDITO: "Crédito", DEBITO: "Débito" };
  function chipEstado(codigo) { return chip(ESTADO_TX[codigo] || codigo, codigo); }
  function tipoTexto(codigo) { return TIPO_TX[codigo] || codigo || "—"; }

  /* ---------- Secciones por la dirección (#seccion) ---------- */
  function secciones(alCambiar) {
    const todas = [...document.querySelectorAll("[data-seccion]")];
    todas.forEach((s) => s.classList.add("seccion"));
    const mostrar = () => {
      const id = location.hash.replace(/^#/, "").split("?")[0];
      const actual = todas.find((s) => s.dataset.seccion === id) || todas[0];
      todas.forEach((s) => s.classList.toggle("activa", s === actual));
      marcarActual();
      if (actual && alCambiar) alCambiar(actual.dataset.seccion);
      cerrarMenu();
    };
    window.addEventListener("hashchange", mostrar);
    mostrar();
  }

  /* ---------- Marco ---------- */
  let marcoEl = null;
  function marcarActual() {
    const aqui = location.pathname.split("/").pop() || "index.html";
    const hash = location.hash.split("?")[0];
    const enlaces = document.querySelectorAll(".item-menu, .barra-abajo a");
    let mejor = null;
    enlaces.forEach((a) => {
      const [pag, h = ""] = a.getAttribute("href").split("#");
      const coincide = pag === aqui && (h === "" || "#" + h === hash);
      if (coincide) mejor = mejor || a.getAttribute("href");
    });
    if (!mejor) { // si la dirección no trae sección, la primera de la página
      const primero = [...enlaces].find((a) => a.getAttribute("href").split("#")[0] === aqui);
      mejor = primero && primero.getAttribute("href");
    }
    enlaces.forEach((a) => a.toggleAttribute("aria-current", false));
    enlaces.forEach((a) => { if (a.getAttribute("href") === mejor) a.setAttribute("aria-current", "page"); });
  }
  function cerrarMenu() { if (marcoEl) marcoEl.classList.remove("menu-abierto"); }
  function armarMarco(sesion, titulo) {
    const perfil = sesion ? sesion.perfil : "PUBLICO";
    const items = sesion ? MENUS[perfil].concat(COMUNES) : MENUS.PUBLICO;
    const principal = document.querySelector("main");
    principal.classList.add("marco-contenido");

    marcoEl = el("div", { class: "marco" });
    if (leer("banco.menu.plegado") === "1") marcoEl.classList.add("plegado");

    const botonMenu = el("button", { class: "boton-menu", type: "button", "aria-label": "Abrir o plegar el menú", "aria-expanded": "true", html: icono("menu") });
    botonMenu.addEventListener("click", () => {
      if (window.matchMedia("(max-width: 900px)").matches) {
        marcoEl.classList.toggle("menu-abierto");
        botonMenu.setAttribute("aria-expanded", String(marcoEl.classList.contains("menu-abierto")));
      } else {
        marcoEl.classList.toggle("plegado");
        guardar("banco.menu.plegado", marcoEl.classList.contains("plegado") ? "1" : "0");
        botonMenu.setAttribute("aria-expanded", String(!marcoEl.classList.contains("plegado")));
        setTimeout(() => window.dispatchEvent(new Event("resize")), 420);   // que las gráficas se acomoden
      }
    });

    const usuario = sesion
      ? el("div", { class: "usuario" },
          el("div", { class: "chip-usuario" }, el("b", { text: sesion.nombre }), el("small", { text: NOMBRE_PERFIL[perfil] + (sesion.oficina ? " · " + sesion.oficina : "") })),
          el("span", { class: "avatar", "aria-hidden": "true", text: sesion.nombre.split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]).join("").toUpperCase() }),
          el("button", { class: "boton secundario chico boton-salir", type: "button", html: icono("salir") + "<span>Salir</span>", onclick: () => BancoAPI.salir() }))
      : el("div", { class: "usuario" }, el("a", { class: "boton destacado chico", href: "ingresar.html", text: "Ingresar" }));

    const barra = el("header", { class: "marco-barra" },
      botonMenu,
      el("a", { class: "marca", href: sesion ? INICIO[perfil] : "index.html", html: LOGO + "<span>Banco Andino</span>" }),
      titulo ? el("span", { class: "titulo-pagina", text: "· " + titulo }) : null,
      usuario);

    const nav = el("nav", { "aria-label": "Menú principal" }, items.map((i) => i.grupo
      ? el("div", { class: "grupo", text: i.grupo })
      : el("a", { class: "item-menu", href: i.href, "data-nombre": i.nombre, html: icono(i.icono) + '<span class="texto"></span>' })));
    nav.querySelectorAll(".item-menu").forEach((a) => { a.querySelector(".texto").textContent = a.dataset.nombre; });
    const menu = el("aside", { class: "marco-menu" }, nav);

    // En celular: deslizar el menú hacia la izquierda lo cierra
    let x0 = null;
    menu.addEventListener("touchstart", (e) => { x0 = e.touches[0].clientX; }, { passive: true });
    menu.addEventListener("touchend", (e) => { if (x0 !== null && e.changedTouches[0].clientX - x0 < -60) cerrarMenu(); x0 = null; });

    const fondo = el("div", { class: "fondo-menu", onclick: cerrarMenu });
    const abajo = el("nav", { class: "barra-abajo", "aria-label": "Accesos rápidos" },
      items.filter((i) => i.abajo).slice(0, 4).map((i) => {
        const a = el("a", { href: i.href, html: icono(i.icono) + "<span></span>" });
        a.querySelector("span").textContent = i.corto ? i.corto : i.nombre.split(" ")[0] === "Pendientes" ? "Pendientes" : i.nombre.replace(/ \(.*\)$/, "").replace(/ de la oficina$/, "");
        return a;
      }));

    principal.parentNode.insertBefore(marcoEl, principal);
    marcoEl.append(barra, menu, principal, fondo);
    document.body.append(abajo);
    document.querySelectorAll(".item-menu, .barra-abajo a").forEach((a) => a.addEventListener("click", cerrarMenu));
    window.addEventListener("hashchange", marcarActual);
    marcarActual();
  }

  /* Arranca la página. perfiles = quién puede verla (vacío = pública) */
  async function iniciar({ perfiles = [], titulo = "" } = {}) {
    let sesion = null;
    try { sesion = await BancoAPI.sesionOpcional(); } catch (_) { sesion = null; }
    if (perfiles.length) {
      if (!sesion) {
        location.href = "ingresar.html?volver=" + encodeURIComponent(location.pathname.replace(/^\//, "") + location.hash);
        return new Promise(() => {});
      }
      if (!perfiles.includes(sesion.perfil)) { location.href = INICIO[sesion.perfil]; return new Promise(() => {}); }
    }
    armarMarco(sesion, titulo);
    document.body.classList.add("listo");
    return sesion;
  }

  window.Banco = { iniciar, secciones, icono, el, dinero, entero, numero, fecha, clave, contar, aviso, confirmar, exito,
                   enviar, datosDe, montoTexto, tabla, chip, chipEstado, tipoTexto, pedirDatos, mostrar, INICIO, NOMBRE_PERFIL };
})();
