/* Banco Andino · páginas que se ven sin iniciar sesión: Inicio, Equipo y Tecnologías */
(async function () {
  "use strict";
  const { el, icono } = Banco;
  const pagina = document.body.dataset.pagina || "inicio";
  await Banco.iniciar({ titulo: { equipo: "Equipo", tecnologias: "Tecnologías" }[pagina] || "" });

  if (pagina === "equipo") {
    const cont = document.getElementById("integrantes");
    try {
      const equipo = await BancoAPI.get("api/equipo");
      cont.replaceChildren(...equipo.map((p) => el("article", { class: "tarjeta integrante" },
        el("span", { class: "avatar", "aria-hidden": "true", text: p.iniciales }),
        el("h3", { text: p.nombre }),
        p.rol_proyecto ? el("p", { class: "chip neutro", text: p.rol_proyecto }) : null,
        el("p", { class: "suave chico", text: p.programa + " · Universidad de Manizales" }),
        p.hoja_de_vida
          ? el("a", { class: "boton secundario chico", href: p.hoja_de_vida, target: "_blank", rel: "noopener", html: icono("documento") + "<span>Ver hoja de vida</span>" })
          : el("span", { class: "chip alerta", text: "Hoja de vida pendiente" }))));
    } catch (e) {
      cont.replaceChildren(el("p", { class: "vacio", text: "No pudimos cargar el equipo: " + e.message }));
    }
  }

  if (pagina === "tecnologias") {
    const T = [
      ["PostgreSQL 18", "La base del banco (gates G0 a G8) y el modelo estrella del esquema bi. Las reglas del negocio viven en sus funciones, triggers y roles.", "cuadres"],
      ["Python 3.13 y FastAPI", "El servidor del aplicativo: recibe lo que piden las pantallas y llama a las funciones seguras de la base con el rol de cada perfil.", "tecnologias"],
      ["psycopg 3", "La conexión de Python con PostgreSQL. Cada petición abre una transacción con el rol del perfil (SET LOCAL ROLE).", "llave"],
      ["HTML, CSS y JavaScript", "Las pantallas, sin framework, adaptables a celular, tablet y computador. Estilo vidrio, menú plegable y animaciones cortas.", "documento"],
      ["Chart.js", "Las gráficas de la sección Estadísticas y de Mis estadísticas, copiadas dentro del proyecto para que funcionen sin internet.", "estadisticas"],
      ["Power BI Desktop", "El archivo .pbix con las 4 páginas de tableros, conectado al modelo estrella con un usuario de solo lectura.", "estadisticas"],
      ["bcrypt", "Las contraseñas del aplicativo se guardan cifradas; la base del banco no guarda contraseñas.", "candado"],
      ["Playwright", "Las pruebas que abren el aplicativo en un navegador, comparan cifras con SQL y toman las capturas.", "calidad"],
      ["Git, GitHub y GitHub Desktop", "Trabajar los cinco sobre el mismo repositorio, en la rama fase-bi.", "equipo"],
      ["Claude (IA)", "Nos ayudó a proponer, revisar y generar código. Todo lo comprobamos nosotros con pruebas; está anotado en el registro de IA.", "aprobaciones"]
    ];
    document.getElementById("tecnologias").replaceChildren(...T.map(([n, d, i]) => el("article", { class: "tarjeta tecnologia" },
      el("span", { class: "icono-caja", html: icono(i) }), el("div", {}, el("h3", { text: n }), el("p", { text: d })))));
  }
})();
