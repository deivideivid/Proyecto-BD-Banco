/* Banco Andino · panel provisional (B5): muestra quién inició sesión y su menú. */
(async function () {
  "use strict";
  document.getElementById("salir").addEventListener("click", () => BancoAPI.salir());
  const s = await BancoAPI.get("api/sesion");
  document.getElementById("saludo").textContent = "Hola, " + s.nombre;
  document.getElementById("perfil").textContent = "Perfil: " + s.perfil + (s.oficina ? " · " + s.oficina : "");
  const ul = document.getElementById("menu");
  for (const m of s.menu) {
    const li = document.createElement("li");
    li.textContent = m.replace(/_/g, " ");
    ul.appendChild(li);
  }
})();
