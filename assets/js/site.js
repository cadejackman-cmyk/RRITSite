/* RedRock IT — site behaviour. No dependencies. */
(function () {
  'use strict';
  var doc = document, body = doc.body;

  /* ---- sticky header shadow ---- */
  var hdr = doc.querySelector('.hdr');
  var totop = doc.querySelector('.totop');
  var callbar = doc.querySelector('.callbar');
  var lastY = 0, ticking = false;

  function onScroll() {
    var y = window.pageYOffset;
    if (hdr) hdr.classList.toggle('stuck', y > 8);
    if (totop) totop.classList.toggle('show', y > 700);
    if (callbar) callbar.classList.toggle('show', y > 460 && y < lastY + 4000);
    lastY = y;
    ticking = false;
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { window.requestAnimationFrame(onScroll); ticking = true; }
  }, { passive: true });
  onScroll();

  if (totop) totop.addEventListener('click', function () {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  /* ---- desktop dropdown menus (hover + click + keyboard) ---- */
  var items = [].slice.call(doc.querySelectorAll('.nav-item'));
  var hoverOK = window.matchMedia('(hover:hover) and (min-width:1081px)').matches;

  function closeAll(except) {
    items.forEach(function (it) {
      if (it === except) return;
      it.classList.remove('open');
      var b = it.querySelector('.nav-link');
      if (b && b.hasAttribute('aria-expanded')) b.setAttribute('aria-expanded', 'false');
    });
  }

  items.forEach(function (it) {
    var btn = it.querySelector('.nav-link');
    var menu = it.querySelector('.mega');
    if (!btn || !menu) return;
    var t;

    btn.addEventListener('click', function (e) {
      e.preventDefault();
      var open = it.classList.contains('open');
      closeAll(it);
      it.classList.toggle('open', !open);
      btn.setAttribute('aria-expanded', String(!open));
    });

    if (hoverOK) {
      it.addEventListener('mouseenter', function () {
        clearTimeout(t);
        closeAll(it);
        it.classList.add('open');
        btn.setAttribute('aria-expanded', 'true');
      });
      it.addEventListener('mouseleave', function () {
        t = setTimeout(function () {
          it.classList.remove('open');
          btn.setAttribute('aria-expanded', 'false');
        }, 140);
      });
    }

    /* keyboard: leaving the submenu closes it */
    it.addEventListener('focusout', function (e) {
      if (!it.contains(e.relatedTarget)) {
        it.classList.remove('open');
        btn.setAttribute('aria-expanded', 'false');
      }
    });
  });

  doc.addEventListener('click', function (e) {
    if (!e.target.closest('.nav-item')) closeAll(null);
  });
  doc.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    closeAll(null);
    if (body.classList.contains('menu-open')) toggleDrawer(false);
  });

  /* ---- mobile drawer ---- */
  var burger = doc.querySelector('.burger');
  var drawer = doc.querySelector('.drawer');

  function toggleDrawer(open) {
    body.classList.toggle('menu-open', open);
    if (burger) burger.setAttribute('aria-expanded', String(open));
    body.style.overflow = open ? 'hidden' : '';
    if (open && drawer) {
      var first = drawer.querySelector('a,button');
      if (first) first.focus({ preventScroll: true });
    } else if (burger) {
      burger.focus({ preventScroll: true });
    }
  }

  if (burger) burger.addEventListener('click', function () {
    toggleDrawer(!body.classList.contains('menu-open'));
  });

  /* drawer accordions */
  [].forEach.call(doc.querySelectorAll('.dr-top[data-acc]'), function (btn) {
    btn.addEventListener('click', function () {
      var g = btn.closest('.dr-group');
      var open = g.classList.contains('open');
      g.classList.toggle('open', !open);
      btn.setAttribute('aria-expanded', String(!open));
    });
  });

  /* close drawer when navigating to an in-page anchor */
  [].forEach.call(doc.querySelectorAll('.drawer a[href]'), function (a) {
    a.addEventListener('click', function () {
      if (a.getAttribute('href').charAt(0) === '#') toggleDrawer(false);
    });
  });

  /* reset drawer state if resized to desktop */
  window.addEventListener('resize', function () {
    if (window.innerWidth > 1080 && body.classList.contains('menu-open')) toggleDrawer(false);
  });

  /* ---- reveal on scroll ---- */
  var rv = [].slice.call(doc.querySelectorAll('.rv'));
  if (rv.length) {
    if (!('IntersectionObserver' in window) ||
        window.matchMedia('(prefers-reduced-motion:reduce)').matches) {
      rv.forEach(function (el) { el.classList.add('in'); });
    } else {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          if (!en.isIntersecting) return;
          var el = en.target;
          var d = parseInt(el.getAttribute('data-rv') || '0', 10);
          setTimeout(function () { el.classList.add('in'); }, d);
          io.unobserve(el);
        });
      }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
      rv.forEach(function (el) { io.observe(el); });
    }
  }

  /* ---- FAQ: only one open at a time within a group ---- */
  [].forEach.call(doc.querySelectorAll('.faq'), function (group) {
    var all = [].slice.call(group.querySelectorAll('details'));
    all.forEach(function (d) {
      d.addEventListener('toggle', function () {
        if (!d.open) return;
        all.forEach(function (o) { if (o !== d) o.open = false; });
      });
    });
  });

  /* ---- contact click tracking ---- */
  /* Calls and emails are the real conversions for this business, and the contact
     form is an embedded Microsoft Form we cannot see inside. gtag() is defined in
     the head and queues into dataLayer, so these fire correctly even before
     gtag.js has finished loading on the window load event. */
  doc.addEventListener('click', function (e) {
    if (typeof window.gtag !== 'function') return;
    var el = e.target;
    var a = el && el.closest ? el.closest('a[href^="tel:"], a[href^="mailto:"]') : null;
    if (!a) return;
    var tel = a.getAttribute('href').indexOf('tel:') === 0;
    var where = a.closest('.callbar') ? 'call bar'
              : (a.closest('.hdr') || a.closest('.util')) ? 'header'
              : a.closest('.ftr') ? 'footer'
              : 'page body';
    window.gtag('event', tel ? 'contact_call' : 'contact_email', {
      method: tel ? 'phone' : 'email',
      link_location: where,
      page_path: location.pathname
    });
  });

  /* ---- contact form ---- */
  /* Posts JSON to /api/contact, which nginx proxies to a small loopback service.
     Field errors come back from the server and are rendered per field, so the
     browser and the server never disagree about what is valid. */
  (function () {
    var form = doc.getElementById('checkupForm');
    if (!form) return;
    var done = doc.getElementById('formDone');
    var alertBox = doc.getElementById('formAlert');
    var btn = doc.getElementById('formSubmit');
    var FIELDS = ['name','company','email','phone','industry','reason','message','consent'];
    var opened = Date.now();   // the server rejects anything submitted implausibly fast

    function setErr(name, msg) {
      var el = doc.getElementById('e-' + name);
      if (!el) return;
      el.textContent = msg || '';
      var field = el.closest('.field');
      if (field) field.classList.toggle('err', !!msg);
    }
    function clearErrs() {
      FIELDS.forEach(function (n) { setErr(n, ''); });
      alertBox.hidden = true;
      alertBox.textContent = '';
    }
    function busy(on) {
      if (on) {
        btn.setAttribute('aria-busy', 'true');
        btn.innerHTML = '<span class="spin"></span> Sending';
      } else {
        btn.removeAttribute('aria-busy');
        btn.textContent = 'Send it over';
      }
    }

    /* Checked here as well as on the server so an obviously incomplete form
       never leaves the browser. The server stays the authority; this only
       saves a round trip and answers instantly. */
    function localCheck(p) {
      var e = {};
      if (!p.name || p.name.trim().length < 2) e.name = 'Please tell us your name.';
      if (!p.company || p.company.trim().length < 2) e.company = 'Please tell us your business name.';
      if (!p.email || !/^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$/.test(p.email)) e.email = 'That email address does not look right.';
      if (!p.phone || !/^[0-9 ()+.\-]{7,30}$/.test(p.phone)) e.phone = 'Please give a phone number we can reach you on.';
      if (!p.industry) e.industry = 'Please choose an option.';
      if (!p.reason) e.reason = 'Please choose an option.';
      if (!p.message || p.message.trim().length < 10) e.message = 'A sentence or two is enough, but we need something.';
      if (!p.consent) e.consent = 'We need your agreement before we can contact you.';
      return e;
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      clearErrs();
      var fd = new FormData(form);
      var payload = {
        name: fd.get('name'), company: fd.get('company'), email: fd.get('email'),
        phone: fd.get('phone'), industry: fd.get('industry'), reason: fd.get('reason'),
        message: fd.get('message'), consent: !!fd.get('consent'),
        website: fd.get('website') || '', ts: opened
      };

      var local = localCheck(payload);
      var badKeys = Object.keys(local);
      if (badKeys.length) {
        badKeys.forEach(function (k) { setErr(k, local[k]); });
        var el0 = doc.getElementById('f-' + badKeys[0]);
        if (el0) el0.focus();
        return;
      }
      busy(true);

      fetch('/api/contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (d) {
          return { status: r.status, body: d };
        });
      }).then(function (res) {
        if (res.body && res.body.ok) {
          form.hidden = true;
          done.hidden = false;
          done.setAttribute('tabindex', '-1');
          done.focus();
          done.scrollIntoView({ behavior: 'smooth', block: 'center' });
          if (typeof window.gtag === 'function') {
            window.gtag('event', 'contact_form', { method: 'form', page_path: location.pathname });
          }
          return;
        }
        var errs = (res.body && res.body.errors) || {};
        var first = null;
        Object.keys(errs).forEach(function (k) { setErr(k, errs[k]); if (!first) first = k; });
        if (first) {
          var el = doc.getElementById('f-' + first);
          if (el) el.focus();
        } else {
          alertBox.textContent = (res.body && res.body.error) ||
            'Something went wrong at our end. Please call (801) 562-2300 and we will pick it up.';
          alertBox.hidden = false;
        }
      }).catch(function () {
        alertBox.textContent = 'We could not reach the server. Please call (801) 562-2300.';
        alertBox.hidden = false;
      }).then(function () { busy(false); });
    });
  })();

  /* ---- current year ---- */
  [].forEach.call(doc.querySelectorAll('[data-year]'), function (el) {
    el.textContent = new Date().getFullYear();
  });
})();
