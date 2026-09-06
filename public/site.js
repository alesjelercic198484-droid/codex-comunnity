/* Nevsiljiv JS: potrdi nevarne akcije + samodejno skrije obvestila.
   Ni nujno za delovanje strani (vse deluje tudi brez JS). */
(function () {
  'use strict';

  document.addEventListener('submit', function (e) {
    var form = e.target;
    var msg = form.getAttribute('data-confirm');
    if (msg && !window.confirm(msg)) e.preventDefault();
  }, false);

  document.querySelectorAll('.flash').forEach(function (el) {
    if (el.classList.contains('flash--bad')) return; // napako pusti vidno
    window.setTimeout(function () {
      el.style.transition = 'opacity .4s ease';
      el.style.opacity = '0';
      window.setTimeout(function () { el.remove(); }, 450);
    }, 6000);
  });

  // gumb "Odpri" na prijavnici: skoci na kartico in jo obarva
  if (location.hash === '#otok') {
    var target = document.querySelector('.acc__item:last-of-type');
    if (target) target.scrollIntoView({ block: 'center' });
  }
})();
