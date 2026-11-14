/* Banco Andino · Administrador: usuarios, roles y accesos al aplicativo. No ve ni mueve dinero. */
(async function () {
  "use strict";
  const { el, fecha, chip } = Banco;
  const sesion = await Banco.iniciar({ perfiles: ["ADMINISTRADOR"], titulo: "Administración" });
  const PERFIL_DE_ROL = { CAJERO: "CAJERO", SUPERVISOR: "SUPERVISOR", AUDITOR: "AUDITOR", ADMIN_SEGURIDAD: "ADMINISTRADOR" };
  let catalogos = { roles: [], oficinas: [] };
  let accesos = new Map();

  async function cargarCatalogos() {
    catalogos = await BancoAPI.get("api/admin/catalogos");
    document.getElementById("filtro-rol").append(...catalogos.roles.map((r) => el("option", { value: r.codigo, text: r.nombre })));
    document.getElementById("nuevo-oficina").append(...catalogos.oficinas.map((o) => el("option", { value: o.oficina_id, text: o.nombre })));
  }
  async function cargarAccesos() {
    const lista = await BancoAPI.get("api/admin/accesos");
    accesos = new Map(lista.map((a) => [a.usuario_id, a]));
    return lista;
  }

  async function cargarUsuarios() {
    const f = Banco.datosDe(document.getElementById("form-usuarios"));
    const q = new URLSearchParams();
    if (f.q) q.set("q", f.q);
    if (f.rol) q.set("rol", f.rol);
    const caja = document.getElementById("lista-usuarios");
    caja.classList.add("cargando");
    try {
      const [usuarios] = await Promise.all([BancoAPI.get("api/admin/usuarios?" + q), cargarAccesos()]);
      caja.replaceChildren(Banco.tabla([
        { titulo: "Login", campo: "login" },
        { titulo: "Nombre", valor: (u) => u.nombres + " " + u.apellidos },
        { titulo: "Oficina", valor: (u) => u.oficina || "—" },
        { titulo: "Roles", valor: (u) => u.roles ? u.roles.split(", ").map((r) => chip(r, "neutro")) : "Sin rol" },
        { titulo: "Estado", valor: (u) => chip(u.estado) },
        { titulo: "Aplicativo", valor: (u) => { const a = accesos.get(u.usuario_id); return a ? chip(a.activo ? "Con acceso" : "Sin acceso", a.activo ? "exito" : "neutro") : "—"; } },
        { titulo: "", acciones: true, valor: (u) => u.login === "canal.digital" ? el("span", { class: "chip neutro", text: "Usuario técnico" }) : el("div", { class: "fila fin" },
            el("button", { class: "boton secundario chico", type: "button", text: "Roles", onclick: (e) => roles(u, e.currentTarget) }),
            el("button", { class: "boton secundario chico", type: "button", text: "Acceso", onclick: (e) => darAcceso(u, e.currentTarget) }),
            el("button", { class: "boton chico " + (u.estado === "ACTIVO" ? "peligro" : "primario"), type: "button", text: u.estado === "ACTIVO" ? "Desactivar" : "Activar", onclick: (e) => cambiarEstado(u, e.currentTarget) })) }
      ], usuarios, { vacio: "No hay usuarios con esos filtros." }));
    } catch (e) { caja.replaceChildren(el("p", { class: "vacio", text: e.message })); }
    finally { caja.classList.remove("cargando"); }
  }

  async function roles(u, boton) {
    const tiene = u.roles ? u.roles.split(", ") : [];
    const opciones = catalogos.roles.map((r) => [(tiene.includes(r.codigo) ? "quitar:" : "dar:") + r.codigo, (tiene.includes(r.codigo) ? "Revocar " : "Asignar ") + r.nombre]);
    const d = await Banco.pedirDatos({ titulo: "Roles de " + u.login, texto: tiene.length ? "Tiene: " + tiene.join(", ") : "No tiene roles vigentes.",
      campos: [{ nombre: "accion", etiqueta: "Qué hacer", tipo: "select", opciones }], boton: "Revisar" });
    if (!d) return;
    const [accion, rol] = d.accion.split(":");
    const ok = await Banco.confirmar({ titulo: (accion === "dar" ? "Asignar " : "Revocar ") + rol, datos: [["Usuario", u.login], ["Rol", rol]],
      texto: accion === "quitar" ? "La asignación queda con fecha de fin; si tenía sesión abierta, pierde el acceso de inmediato." : null,
      boton: accion === "dar" ? "Asignar" : "Revocar", peligro: accion === "quitar" });
    if (!ok) return;
    const r = await Banco.enviar(boton, () => accion === "dar"
      ? BancoAPI.post("api/admin/usuarios/" + u.usuario_id + "/roles", { rol })
      : BancoAPI.post("api/admin/usuarios/" + u.usuario_id + "/roles/" + rol + "/revocar"));
    if (r) { Banco.aviso("Listo: " + (accion === "dar" ? "rol asignado." : "rol revocado."), "exito"); cargarUsuarios(); }
  }

  async function darAcceso(u, boton) {
    const a = accesos.get(u.usuario_id);
    const perfiles = (u.roles ? u.roles.split(", ") : []).map((r) => PERFIL_DE_ROL[r]).filter(Boolean);
    if (!perfiles.length) { Banco.aviso("Primero asígnele un rol a " + u.login + ".", "error"); return; }
    if (u.estado !== "ACTIVO") { Banco.aviso("El usuario está inactivo.", "error"); return; }
    const opciones = perfiles.map((p) => ["dar:" + p, (a && a.activo ? "Restablecer contraseña como " : "Dar acceso como ") + Banco.NOMBRE_PERFIL[p]]);
    if (a && a.activo) opciones.push(["quitar:", "Quitar el acceso al aplicativo"]);
    const d = await Banco.pedirDatos({ titulo: "Acceso de " + u.login + " al aplicativo",
      texto: a ? (a.activo ? "Tiene acceso como " + Banco.NOMBRE_PERFIL[a.perfil] + ". Último ingreso: " + fecha(a.ultimo_ingreso) + "." : "Tenía acceso y se le quitó.") : "Todavía no tiene acceso.",
      campos: [{ nombre: "accion", etiqueta: "Qué hacer", tipo: "select", opciones }], boton: "Revisar" });
    if (!d) return;
    const [accion, perfil] = d.accion.split(":");
    if (accion === "quitar") {
      const ok = await Banco.confirmar({ titulo: "Quitar el acceso de " + u.login, boton: "Quitar acceso", peligro: true });
      if (!ok) return;
      const r = await Banco.enviar(boton, () => BancoAPI.post("api/admin/usuarios/" + u.usuario_id + "/acceso/quitar"));
      if (r) { Banco.aviso("Acceso quitado.", "exito"); cargarUsuarios(); }
      return;
    }
    const ok = await Banco.confirmar({ titulo: "Dar acceso a " + u.login, datos: [["Perfil", Banco.NOMBRE_PERFIL[perfil]], ["Usuario para entrar", u.login]],
      texto: "Se genera una contraseña temporal que solo se muestra ahora.", boton: "Generar contraseña" });
    if (!ok) return;
    const r = await Banco.enviar(boton, () => BancoAPI.post("api/admin/usuarios/" + u.usuario_id + "/acceso", { perfil }));
    if (!r) return;
    await Banco.exito({ titulo: "Acceso listo", texto: "Entréguele estos datos al empleado. La contraseña no se vuelve a mostrar.",
      extra: el("dl", { class: "detalle" }, el("dt", { text: "Usuario" }), el("dd", { text: r.login }), el("dt", { text: "Contraseña temporal" }), el("dd", { class: "clave-temporal", text: r.clave_temporal })) });
    cargarUsuarios();
  }

  async function cambiarEstado(u, boton) {
    const nuevo = u.estado === "ACTIVO" ? "INACTIVO" : "ACTIVO";
    const ok = await Banco.confirmar({ titulo: (nuevo === "INACTIVO" ? "Desactivar a " : "Activar a ") + u.login,
      texto: nuevo === "INACTIVO" ? "No podrá operar en el banco ni entrar al aplicativo." : null, boton: nuevo === "INACTIVO" ? "Desactivar" : "Activar", peligro: nuevo === "INACTIVO" });
    if (!ok) return;
    const r = await Banco.enviar(boton, () => BancoAPI.post("api/admin/usuarios/" + u.usuario_id + "/estado", { estado: nuevo }));
    if (r) { Banco.aviso("Estado actualizado.", "exito"); cargarUsuarios(); }
  }

  async function pintarAccesos() {
    const lista = await cargarAccesos();
    document.getElementById("lista-accesos").replaceChildren(Banco.tabla([
      { titulo: "Usuario", campo: "login" }, { titulo: "Perfil", valor: (a) => Banco.NOMBRE_PERFIL[a.perfil] },
      { titulo: "Estado", valor: (a) => a.bloqueado ? chip("Bloqueado por intentos", "peligro") : chip(a.activo ? "Activo" : "Sin acceso", a.activo ? "exito" : "neutro") },
      { titulo: "Último ingreso", valor: (a) => fecha(a.ultimo_ingreso) }
    ], lista, { vacio: "Nadie tiene acceso todavía." }));
  }

  document.getElementById("form-usuarios").addEventListener("submit", (e) => { e.preventDefault(); cargarUsuarios(); });
  document.getElementById("form-nuevo").addEventListener("submit", async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const error = form.querySelector(".mensaje-error");
    const d = Banco.datosDe(form);
    d.login = (d.login || "").toLowerCase();
    d.numero_documento = (d.numero_documento || "").toUpperCase();
    d.oficina_id = d.oficina_id ? Number(d.oficina_id) : null;
    if (!/^[a-z0-9._]{4,40}$/.test(d.login)) { error.textContent = "El login lleva de 4 a 40 minúsculas, números, punto o guion bajo."; return; }
    const ok = await Banco.confirmar({ titulo: "Crear usuario", datos: [["Login", d.login], ["Nombre", (d.nombres || "") + " " + (d.apellidos || "")], ["Documento", d.tipo_documento + " " + d.numero_documento]] });
    if (!ok) return;
    const r = await Banco.enviar(form.querySelector('button[type="submit"]'), () => BancoAPI.post("api/admin/usuarios", d), { errorEn: error });
    if (!r) return;
    form.reset();
    await Banco.exito({ titulo: "Usuario creado", texto: "Ahora asígnele un rol desde Usuarios y roles." });
    document.querySelector('#form-usuarios [name="q"]').value = d.login;
    location.hash = "#usuarios";
    cargarUsuarios();
  });

  await cargarCatalogos().catch((e) => Banco.aviso(e.message, "error"));
  const hechas = new Set();
  Banco.secciones((s) => {
    if (s === "usuarios" && !hechas.has(s)) { hechas.add(s); cargarUsuarios(); }
    if (s === "accesos") pintarAccesos().catch((e) => Banco.aviso(e.message, "error"));
  });
  void sesion;
})();
