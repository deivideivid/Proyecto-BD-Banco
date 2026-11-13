/* Banco Andino · Estadísticas (B4)
   Pide los datos al servidor (/api/estadisticas/...) y dibuja las 4 páginas de Power BI con
   Chart.js. No calcula indicadores: solo los muestra. Los montos llegan como texto para
   mostrarlos exactos, al centavo. */
(function () {
  "use strict";

  const reducirMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Cómo se muestra cada indicador
  const INDICADORES = {
    K01: { nombre: "Transacciones contabilizadas", tipo: "entero" },
    K02: { nombre: "Monto movido COP", tipo: "COP" },
    K03: { nombre: "Monto movido USD", tipo: "USD" },
    K04: { nombre: "Ticket promedio COP", tipo: "COP" },
    K05: { nombre: "Tasa de rechazo", tipo: "porcentaje" },
    K06: { nombre: "Reversos", tipo: "entero" },
    K07: { nombre: "Clientes con movimientos", tipo: "entero" },
    K08: { nombre: "Cuentas activas (al corte)", tipo: "entero" },
    K09: { nombre: "Saldo total COP (al corte)", tipo: "COP" },
    K10: { nombre: "Saldo total USD (al corte)", tipo: "USD" },
    K11: { nombre: "Cuentas en sobregiro (al corte)", tipo: "entero" },
    K12: { nombre: "Puntaje del quality gate", tipo: "decimal1" },
    K13: { nombre: "Controles en PASS (de 6)", tipo: "entero" },
    TXR: { nombre: "Transacciones rechazadas", tipo: "entero" },
    CTA: { nombre: "Cuentas al corte", tipo: "entero" }
  };

  // Gráficas de cada página (las mismas de Power BI)
  const GRAFICAS = {
    monto_mes:          { titulo: "Monto movido COP por mes", tipo: "line", moneda: true },
    tx_tipo:            { titulo: "Transacciones por tipo", tipo: "bar", horizontal: true },
    tx_hora:            { titulo: "Transacciones por hora del día", tipo: "bar" },
    tx_dia:             { titulo: "Transacciones por día de la semana", tipo: "bar" },
    rechazo_motivo:     { titulo: "Rechazos por motivo", tipo: "bar", horizontal: true },
    monto_tipo:         { titulo: "Monto movido COP por tipo", tipo: "bar", horizontal: true, moneda: true },
    cuentas_estado:     { titulo: "Cuentas por estado (al corte)", tipo: "doughnut" },
    cuentas_producto:   { titulo: "Cuentas por producto", tipo: "bar" },
    saldo_departamento: { titulo: "Saldo COP por departamento de la oficina", tipo: "bar", horizontal: true, moneda: true, ancha: true, alta: true }
  };

  const TABLAS = {
    top_clientes: {
      titulo: "Clientes con más saldo en pesos (10 primeros)",
      columnas: [["cliente", "Cliente"], ["tipo_cliente", "Tipo"], ["departamento", "Departamento"],
                 ["cuentas", "Cuentas", "entero"], ["saldo_cop", "Saldo COP", "COP"]]
    },
    controles: {
      titulo: "Controles de cuadre y calidad (fecha de carga)",
      columnas: [["control_id", "ID"], ["grupo", "Grupo"], ["control", "Control"], ["esperado", "Esperado"],
                 ["obtenido", "Obtenido"], ["resultado", "Resultado", "chip"]]
    },
    pruebas: {
      titulo: "Pruebas del quality gate de G6",
      columnas: [["test_id", "ID"], ["dimension", "Dimensión"], ["regla", "Regla"], ["severidad", "Severidad"],
                 ["resultado", "Resultado", "chip"], ["obtenido", "Obtenido"]],
      desplazable: true
    }
  };

  const PAGINAS = ["resumen", "transacciones", "clientes", "control"];
  const estado = { pagina: "resumen", filtros: { mes: "", producto: "", departamento: "" }, opciones: null, peticion: null };
  const graficasActivas = [];

  const $ = (sel) => document.querySelector(sel);

  /* ---------- Formato de números (es-CO: miles con punto, decimales con coma) ---------- */
  function agruparMiles(entero) {
    return entero.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  }
  // Formatea un número que llega como texto, sin pasarlo por coma flotante
  function exacto(texto, decimales) {
    if (texto === null || texto === undefined) return "—";
    let s = String(texto);
    let negativo = s.startsWith("-");
    if (negativo) s = s.slice(1);
    let [ent, dec = ""] = s.split(".");
    if (decimales > 0) {
      if (dec.length > decimales) {            // redondeo en texto (solo pasa en K12)
        const n = Number(s).toFixed(decimales);
        [ent, dec] = n.split(".");
      }
      dec = (dec + "0".repeat(decimales)).slice(0, decimales);
      return (negativo ? "-" : "") + agruparMiles(ent) + "," + dec;
    }
    return (negativo ? "-" : "") + agruparMiles(ent);
  }
  function formatear(texto, tipo) {
    switch (tipo) {
      case "COP": return exacto(texto, 2) + " COP";
      case "USD": return exacto(texto, 2) + " USD";
      case "porcentaje": return exacto(texto, 2) + " %";
      case "decimal1": return exacto(texto, 1);
      default: return exacto(texto, 0);
    }
  }
  function abreviar(n) {
    const a = Math.abs(n);
    const f = (v) => v.toLocaleString("es-CO", { maximumFractionDigits: 1 });
    if (a >= 1e12) return f(n / 1e12) + " B";
    if (a >= 1e9) return f(n / 1e9) + " mil M";
    if (a >= 1e6) return f(n / 1e6) + " M";
    if (a >= 1e3) return f(n / 1e3) + " mil";
    return f(n);
  }
  function completo(n, moneda) {
    return n.toLocaleString("es-CO", { minimumFractionDigits: moneda ? 2 : 0, maximumFractionDigits: 2 }) + (moneda ? " COP" : "");
  }

  /* ---------- Colores desde el CSS (así la paleta se cambia en un solo lugar) ---------- */
  function colores() {
    const css = getComputedStyle(document.documentElement);
    return {
      serie: css.getPropertyValue("--serie").split(",").map((c) => c.trim()),
      texto: css.getPropertyValue("--texto-suave").trim(),
      primario: css.getPropertyValue("--primario").trim()
    };
  }

  /* ---------- Conexión con el servidor ---------- */
  async function pedir(url, senal) {
    const r = await fetch(url, { signal: senal, headers: { Accept: "application/json" } });
    if (!r.ok) {
      let detalle = "El servidor respondió " + r.status;
      try { detalle = (await r.json()).detail || detalle; } catch (_) { /* sin cuerpo */ }
      throw new Error(detalle);
    }
    return r.json();
  }

  function mostrarError(texto) {
    const aviso = $("#aviso-error");
    aviso.textContent = "No pudimos cargar las estadísticas: " + texto;
    aviso.hidden = false;           // se queda visible hasta que una carga salga bien
  }

  /* ---------- Estado en la dirección (#pagina?mes=...) para poder compartir un filtro ---------- */
  function leerDireccion() {
    const [pag, consulta = ""] = location.hash.replace(/^#/, "").split("?");
    if (PAGINAS.includes(pag)) estado.pagina = pag;
    const p = new URLSearchParams(consulta);
    for (const k of Object.keys(estado.filtros)) estado.filtros[k] = p.get(k) || "";
  }
  function escribirDireccion() {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(estado.filtros)) if (v) p.set(k, v);
    const q = p.toString();
    history.replaceState(null, "", "#" + estado.pagina + (q ? "?" + q : ""));
  }

  /* ---------- Filtros ---------- */
  function llenarFiltros() {
    for (const nombre of ["mes", "producto", "departamento"]) {
      const sel = $("#f-" + nombre);
      for (const o of estado.opciones[nombre]) {
        const op = document.createElement("option");
        op.value = o.valor;
        op.textContent = o.etiqueta;
        sel.appendChild(op);
      }
    }
  }
  function sincronizarFiltros() {
    for (const [k, v] of Object.entries(estado.filtros)) {
      const sel = $("#f-" + k);
      sel.value = v;
      if (sel.value !== v) { estado.filtros[k] = ""; sel.value = ""; }   // valor que no existe
    }
  }

  /* ---------- Dibujo ---------- */
  function animarNumero(elemento, texto, tipo) {
    const final = formatear(texto, tipo);
    const destino = Number(texto);
    if (reducirMovimiento || !isFinite(destino) || destino === 0) { pintarValor(elemento, final); return; }
    const inicio = performance.now(), duracion = 450;
    const decimales = tipo === "entero" ? 0 : (tipo === "decimal1" ? 1 : 2);
    function paso(ahora) {
      const t = Math.min(1, (ahora - inicio) / duracion);
      const suave = 1 - Math.pow(1 - t, 3);
      if (t < 1) {
        pintarValor(elemento, formatear((destino * suave).toFixed(decimales), tipo));
        requestAnimationFrame(paso);
      } else {
        pintarValor(elemento, final);         // siempre termina en el valor exacto
      }
    }
    requestAnimationFrame(paso);
  }
  function pintarValor(elemento, texto) {
    const partes = texto.match(/^(.*?)( COP| USD| %)?$/);
    const cifra = document.createElement("span");
    cifra.className = "cifra";
    cifra.textContent = partes[1];
    elemento.replaceChildren(cifra);
    if (partes[2]) {
      const s = document.createElement("small");
      s.textContent = partes[2].trim();
      elemento.appendChild(s);
    }
  }

  function dibujarTarjetas(datos, ids) {
    const cont = $("#tarjetas");
    cont.replaceChildren();
    cont.classList.toggle("cuatro", ids.length === 4);
    for (const id of ids) {
      const def = INDICADORES[id];
      const ind = datos ? datos.indicadores[id] : null;
      const t = document.createElement("article");
      t.className = "tarjeta vidrio";
      t.dataset.kpi = id;
      const nombre = document.createElement("div");
      nombre.className = "nombre";
      nombre.textContent = def.nombre;
      const valor = document.createElement("div");
      valor.className = "valor";
      if (ind) {
        valor.dataset.valor = ind.valor;
        if (formatear(ind.valor, def.tipo).length > 15) { valor.classList.add("largo"); t.classList.add("ancha-movil"); }
        valor.title = formatear(ind.valor, def.tipo);
        animarNumero(valor, ind.valor, def.tipo);
      } else {
        const e = document.createElement("div");
        e.className = "esqueleto";
        valor.appendChild(e);
      }
      const ref = document.createElement("div");
      ref.className = "id";
      ref.textContent = id.startsWith("K") ? id : "apoyo";
      t.append(nombre, valor, ref);
      cont.appendChild(t);
    }
  }

  function destruirGraficas() {
    while (graficasActivas.length) graficasActivas.pop().destroy();
  }

  function dibujarGraficas(datos) {
    destruirGraficas();
    const cont = $("#graficas");
    cont.replaceChildren();
    const c = colores();
    for (const [serie, filas] of Object.entries(datos.graficas)) {
      const def = GRAFICAS[serie];
      const caja = document.createElement("article");
      caja.className = "grafica vidrio" + (def.ancha ? " ancha" : "") + (def.alta ? " alta" : "");
      caja.dataset.serie = serie;
      const h = document.createElement("h3");
      h.textContent = def.titulo;
      caja.appendChild(h);
      if (!filas.length) {
        const v = document.createElement("p");
        v.className = "vacio";
        v.textContent = "No hay datos con estos filtros.";
        caja.appendChild(v);
        cont.appendChild(caja);
        continue;
      }
      const lienzo = document.createElement("div");
      lienzo.className = "lienzo";
      if (def.alta) lienzo.style.height = Math.max(240, filas.length * 22 + 40) + "px";
      const canvas = document.createElement("canvas");
      canvas.setAttribute("role", "img");
      canvas.setAttribute("aria-label", def.titulo);
      lienzo.appendChild(canvas);
      caja.appendChild(lienzo);
      cont.appendChild(caja);

      const etiquetas = filas.map((f) => f.etiqueta);
      const valores = filas.map((f) => Number(f.valor));
      const esDona = def.tipo === "doughnut";
      const ejeValor = def.horizontal ? "x" : "y";
      const config = {
        type: def.tipo,
        data: {
          labels: etiquetas,
          datasets: [{
            data: valores,
            backgroundColor: esDona ? c.serie : (def.tipo === "line" ? "rgba(31,58,95,.12)" : c.primario),
            borderColor: esDona ? "rgba(255,255,255,.9)" : c.primario,
            borderWidth: esDona ? 2 : (def.tipo === "line" ? 2 : 0),
            borderRadius: def.tipo === "bar" ? 6 : 0,
            fill: def.tipo === "line",
            tension: 0.25,
            pointRadius: def.tipo === "line" ? 2 : 0
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: reducirMovimiento ? false : { duration: 450 },
          indexAxis: def.horizontal ? "y" : "x",
          plugins: {
            legend: { display: esDona, position: "bottom", labels: { color: c.texto, boxWidth: 12 } },
            tooltip: {
              callbacks: {
                title: (items) => items[0].label,
                label: (item) => completo(item.parsed[esDona ? undefined : ejeValor] ?? item.parsed, def.moneda)
              }
            }
          },
          scales: esDona ? {} : {
            [ejeValor]: { beginAtZero: true, ticks: { color: c.texto, callback: (v) => abreviar(Number(v)) }, grid: { color: "rgba(31,58,95,.07)" } },
            [ejeValor === "x" ? "y" : "x"]: {
              ticks: {
                color: c.texto, autoSkip: !def.horizontal,
                callback: function (v) {
                  const t = this.getLabelForValue(v);
                  const max = window.innerWidth < 600 ? 16 : 26;
                  return t.length > max ? t.slice(0, max - 1) + "…" : t;
                }
              },
              grid: { display: false }
            }
          }
        }
      };
      graficasActivas.push(new Chart(canvas, config));
    }
  }

  function dibujarTablas(datos) {
    const cont = $("#tablas");
    cont.replaceChildren();
    for (const [nombre, filas] of Object.entries(datos.tablas)) {
      const def = TABLAS[nombre];
      const caja = document.createElement("article");
      caja.className = "tabla vidrio";
      caja.dataset.tabla = nombre;
      const h = document.createElement("h3");
      h.textContent = def.titulo;
      const envoltura = document.createElement("div");
      if (def.desplazable) envoltura.className = "desplazable";
      const tabla = document.createElement("table");
      const thead = tabla.createTHead().insertRow();
      for (const [, titulo, tipo] of def.columnas) {
        const th = document.createElement("th");
        th.textContent = titulo;
        if (tipo === "entero" || tipo === "COP") th.style.textAlign = "right";
        thead.appendChild(th);
      }
      const cuerpo = tabla.createTBody();
      for (const f of filas) {
        const tr = cuerpo.insertRow();
        for (const [campo, titulo, tipo] of def.columnas) {
          const td = tr.insertCell();
          td.dataset.col = titulo;
          const v = f[campo];
          if (tipo === "chip") {
            const s = document.createElement("span");
            s.className = "chip " + v;
            s.textContent = v;
            td.appendChild(s);
          } else if (tipo === "entero" || tipo === "COP") {
            td.className = "num";
            td.textContent = formatear(v, tipo);
          } else {
            td.textContent = v === null ? "—" : v;
          }
        }
      }
      envoltura.appendChild(tabla);
      caja.append(h, envoltura);
      cont.appendChild(caja);
    }
  }

  function notaFiltros(datos) {
    const nota = $("#nota-filtros");
    if (estado.pagina === "control") {
      nota.textContent = "Los controles y el quality gate son de toda la base: esta página no usa filtros, igual que en Power BI.";
    } else if (estado.filtros.mes && datos && datos.fecha_corte) {
      nota.textContent = "Los saldos y las cuentas son una foto al corte (" + datos.fecha_corte +
        "): el filtro de mes no los cambia.";
    } else {
      nota.textContent = "";
    }
  }

  /* ---------- Carga de una página ---------- */
  async function cargar() {
    escribirDireccion();
    document.querySelectorAll(".pestanas button").forEach((b) => {
      b.setAttribute("aria-selected", String(b.dataset.pagina === estado.pagina));
    });
    $("#filtros").hidden = estado.pagina === "control";
    const conf = { resumen: ["K01", "K02", "K07", "K08", "K09", "K05"],
                   transacciones: ["K01", "K04", "K03", "K05", "TXR", "K06"],
                   clientes: ["CTA", "K08", "K11", "K09", "K10", "K07"],
                   control: ["K12", "K13", "K01", "CTA"] }[estado.pagina];

    if (estado.peticion) estado.peticion.abort();
    estado.peticion = new AbortController();
    const contenido = $(".contenido");
    contenido.classList.add("cargando");
    if (!$("#tarjetas").children.length || $("#tarjetas").dataset.pagina !== estado.pagina) dibujarTarjetas(null, conf);
    $("#estado-carga").textContent = "Calculando…";

    const p = new URLSearchParams();
    if (estado.pagina !== "control") for (const [k, v] of Object.entries(estado.filtros)) if (v) p.set(k, v);
    try {
      const datos = await pedir("api/estadisticas/" + estado.pagina + (p.toString() ? "?" + p : ""), estado.peticion.signal);
      $("#aviso-error").hidden = true;
      dibujarTarjetas(datos, conf);
      $("#tarjetas").dataset.pagina = estado.pagina;
      dibujarGraficas(datos);
      dibujarTablas(datos);
      notaFiltros(datos);
      ["#tarjetas", "#graficas", "#tablas"].forEach((s) => {
        const e = $(s); e.classList.remove("entrando"); void e.offsetWidth; e.classList.add("entrando");
      });
      $("#estado-carga").textContent = datos.desde_cache ? "(ya estaba calculado)" : "(calculado en " + (datos.calculado_en_ms / 1000).toLocaleString("es-CO", { maximumFractionDigits: 1 }) + " s)";
      document.body.dataset.listo = estado.pagina + "|" + p.toString();
    } catch (e) {
      if (e.name !== "AbortError") { mostrarError(e.message); $("#estado-carga").textContent = ""; }
    } finally {
      contenido.classList.remove("cargando");
    }
  }

  /* ---------- Arranque ---------- */
  async function iniciar() {
    leerDireccion();
    document.querySelectorAll(".pestanas button").forEach((b) => {
      b.addEventListener("click", () => { estado.pagina = b.dataset.pagina; cargar(); });
    });
    document.querySelectorAll("#filtros select").forEach((s) => {
      s.addEventListener("change", () => { estado.filtros[s.dataset.filtro] = s.value; cargar(); });
    });
    $("#limpiar").addEventListener("click", () => {
      for (const k of Object.keys(estado.filtros)) estado.filtros[k] = "";
      sincronizarFiltros();
      cargar();
    });
    // Si alguien pega o cambia la dirección (#transacciones?mes=...), mostramos esa vista
    window.addEventListener("hashchange", () => {
      leerDireccion();
      if (estado.opciones) sincronizarFiltros();
      cargar();
    });
    try {
      estado.opciones = await pedir("api/estadisticas/filtros");
      llenarFiltros();
      sincronizarFiltros();
    } catch (e) {
      mostrarError(e.message);
    }
    cargar();
  }

  document.addEventListener("DOMContentLoaded", iniciar);
})();
