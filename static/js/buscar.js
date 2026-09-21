// Filtra las filas de la tabla mientras se escribe en el buscador.
// Ignora mayúsculas y tildes ("garcia" encuentra "García").
(function () {
  const campo = document.getElementById('buscar');
  const tabla = document.querySelector('table[data-filtrable]');
  const aviso = document.getElementById('sin-resultados');
  if (!campo || !tabla || !aviso) return;

  const filas = tabla.querySelectorAll('tbody tr');
  const limpiar = t => t.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');

  campo.addEventListener('input', () => {
    const q = limpiar(campo.value.trim());
    let visibles = 0;
    filas.forEach(fila => {
      const coincide = limpiar(fila.textContent).includes(q);
      fila.hidden = !coincide;
      if (coincide) visibles++;
    });
    aviso.hidden = visibles > 0;
  });
})();
