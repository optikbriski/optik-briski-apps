(function () {
  var cat = window.REKASA_CATALOG;
  if (!cat) return;

  var page = document.body.getAttribute("data-page") || "beranda";
  var params = new URLSearchParams(location.search);
  var state = {
    industry: params.get("bidang") || "umum",
    plan: params.get("plan") || null,
    on: {},
    whiteLabel: false
  };
  if (state.plan && !cat.plans[state.plan]) state.plan = null;
  if (page === "paket" && !industry()) state.industry = "umum";

  function industry() {
    for (var i = 0; i < cat.industries.length; i++) {
      if (cat.industries[i].key === state.industry) return cat.industries[i];
    }
    return null;
  }

  function planDef() {
    return cat.plans[state.plan] || cat.plans.paket_c;
  }

  function included(key) {
    if (!state.plan) return false;
    var keys = (industry() || {}).plans;
    keys = keys ? keys[state.plan] || [] : [];
    return keys.indexOf(key) !== -1;
  }

  function visibleKeys() {
    var hide = (industry() && industry().hide) || [];
    var out = [];
    Object.keys(cat.modules).forEach(function (k) {
      if (hide.indexOf(k) === -1) out.push(k);
    });
    return out;
  }

  function moduleLabel(key) {
    var labels = (industry() && industry().labels) || {};
    return labels[key] || cat.modules[key].label;
  }

  function quote() {
    var plan = planDef();
    var add = 0;
    visibleKeys().forEach(function (k) {
      if (!state.on[k] || included(k)) return;
      add += cat.modules[k].addOnPriceIdr;
    });
    var wl = state.whiteLabel && !plan.whiteLabel ? cat.whiteLabelAddonIdr : 0;
    return {
      baseIdr: plan.priceIdr,
      addOnIdr: add,
      whiteLabelIdr: wl,
      amountIdr: plan.priceIdr + add + wl
    };
  }

  function rp(n) {
    var s = String(Math.abs(n));
    var out = "";
    while (s.length > 3) {
      out = "." + s.slice(-3) + out;
      s = s.slice(0, -3);
    }
    return "Rp " + s + out;
  }

  function applyPlanDefaults() {
    var keys = visibleKeys();
    state.on = {};
    keys.forEach(function (k) {
      state.on[k] = included(k);
    });
    state.whiteLabel = !!(planDef() && planDef().whiteLabel);
  }

  function el(id) {
    return document.getElementById(id);
  }

  function paketHref(planKey, industryKey) {
    return (
      "paket.html?plan=" +
      encodeURIComponent(planKey) +
      "&bidang=" +
      encodeURIComponent(industryKey || state.industry)
    );
  }

  function syncUrl() {
    if (page !== "paket") return;
    var u = new URL(location.href);
    if (state.plan) u.searchParams.set("plan", state.plan);
    else u.searchParams.delete("plan");
    u.searchParams.set("bidang", state.industry);
    history.replaceState({}, "", u.pathname + u.search + u.hash);
  }

  function industryIcon(key) {
    var map = {
      optik: "◉",
      retail: "▣",
      fnb: "♨",
      jasa: "✄",
      bengkel: "⚒",
      klinik: "+",
      grosir: "▦",
      umum: "◇"
    };
    return map[key] || "◇";
  }

  function renderIndustries() {
    var grid = el("industry-grid");
    if (grid) {
      grid.innerHTML = "";
      cat.industries.forEach(function (ind) {
        var a = document.createElement("a");
        a.className = "card industry-card";
        a.href = "paket.html?bidang=" + encodeURIComponent(ind.key);
        a.setAttribute("data-industry", ind.key);
        a.innerHTML =
          '<span class="industry-ico" aria-hidden="true">' +
          industryIcon(ind.key) +
          "</span>" +
          "<div><h3>" +
          ind.label +
          "</h3><p>" +
          ind.blurb +
          '</p><span class="industry-go">LIHAT PAKET</span></div>';
        grid.appendChild(a);
      });
    }
    if (el("industry-blurb") && industry()) {
      el("industry-blurb").textContent = industry().label;
    }
  }

  function renderHomePlans() {
    var box = el("plan-cards");
    if (!box) return;
    box.innerHTML = "";
    ["paket_c", "paket_b", "paket_a"].forEach(function (key) {
      var p = cat.plans[key];
      var names = ((industry() && industry().plans[key]) || [])
        .map(moduleLabel)
        .join(", ");
      var a = document.createElement("a");
      a.className = "card plan-card plan-link";
      a.setAttribute("data-plan", key);
      a.href = paketHref(key);
      a.innerHTML =
        '<p class="eyebrow">' + p.eyebrow + "</p>" +
        "<h3>" + p.short + "</h3>" +
        '<p class="price">' + rp(p.priceIdr) + "</p>" +
        "<p>" + p.blurb + "</p>" +
        '<p class="muted plan-include">Termasuk: ' + names + "</p>" +
        '<p class="plan-go">PILIH FITUR</p>';
      box.appendChild(a);
    });
  }

  function switchRow(id, title, sub, checked, onChange) {
    var row = document.createElement("label");
    row.className = "switch-row";
    row.setAttribute("for", id);
    var text = document.createElement("span");
    text.innerHTML = "<strong>" + title + "</strong><small>" + sub + "</small>";
    var input = document.createElement("input");
    input.type = "checkbox";
    input.id = id;
    input.checked = checked;
    input.addEventListener("change", function () {
      onChange(input.checked);
      renderTotals();
    });
    row.appendChild(text);
    row.appendChild(input);
    return row;
  }

  function renderPaketSwitch() {
    var box = el("plan-switch");
    if (!box) return;
    box.innerHTML = "";
    ["paket_c", "paket_b", "paket_a"].forEach(function (key) {
      var a = document.createElement("a");
      a.className = "chip" + (state.plan === key ? " is-on" : "");
      a.href = paketHref(key);
      a.textContent = cat.plans[key].short;
      a.addEventListener("click", function (ev) {
        ev.preventDefault();
        state.plan = key;
        applyPlanDefaults();
        render();
        syncUrl();
      });
      box.appendChild(a);
    });
  }

  function renderPaketPage() {
    var p = planDef();
    var names = ((industry() && industry().plans[state.plan]) || [])
      .map(moduleLabel)
      .join(", ");
    if (el("paket-title")) el("paket-title").textContent = p.label;
    document.title = p.label + " — REKASA KARYA INDONESIA";
    var hero = el("plan-hero");
    if (hero) {
      hero.innerHTML =
        '<p class="eyebrow">' + p.eyebrow + " · " + industry().label + "</p>" +
        '<p class="price">' + rp(p.priceIdr) + "</p>" +
        "<p>" + p.blurb + "</p>" +
        '<p class="muted plan-include">Termasuk: ' + names + "</p>";
    }
    var list = el("feature-list");
    if (!list) return;
    list.innerHTML = "";
    list.appendChild(
      switchRow(
        "wl-toggle",
        "APK & web merek sendiri",
        p.whiteLabel
          ? "Termasuk paket ini."
          : "Add-on " + rp(cat.whiteLabelAddonIdr),
        state.whiteLabel,
        function (v) {
          state.whiteLabel = v;
        }
      )
    );
    visibleKeys().forEach(function (k) {
      var m = cat.modules[k];
      var inPlan = included(k);
      list.appendChild(
        switchRow(
          "mod-" + k,
          moduleLabel(k),
          (m.summary || "") +
            (inPlan ? " · Termasuk paket." : " · Add-on " + rp(m.addOnPriceIdr)),
          !!state.on[k],
          function (v) {
            state.on[k] = v;
          }
        )
      );
    });
  }

  function renderTotals() {
    var total = el("quote-total");
    var brk = el("quote-break");
    var btn = el("pay-btn");
    if (!total || !brk || !btn) return;
    var q = quote();
    total.textContent = rp(q.amountIdr);
    var bits = ["Dasar " + rp(q.baseIdr)];
    if (q.addOnIdr) bits.push("add-on " + rp(q.addOnIdr));
    if (q.whiteLabelIdr) bits.push("merek sendiri " + rp(q.whiteLabelIdr));
    brk.textContent = bits.join(" · ");
    btn.textContent = "Bayar " + rp(q.amountIdr) + " via Midtrans";
  }

  function render() {
    renderIndustries();
    if (page === "paket") {
      var picking = !state.plan;
      var cards = el("plan-cards");
      var pageBox = el("plan-page");
      var sw = el("plan-switch");
      if (cards) cards.classList.toggle("hidden", !picking);
      if (pageBox) pageBox.classList.toggle("hidden", picking);
      if (sw) sw.classList.toggle("hidden", picking);
      if (el("paket-title") && picking) {
        el("paket-title").textContent = "Pilih paket";
        document.title = "Pilih paket — REKASA KARYA INDONESIA";
      }
      if (picking) {
        renderHomePlans();
      } else {
        renderPaketSwitch();
        renderPaketPage();
        renderTotals();
      }
    }
  }

  function selectedModules() {
    var map = {};
    visibleKeys().forEach(function (k) {
      map[k] = !!state.on[k];
    });
    return map;
  }

  function status(msg, isErr) {
    var n = el("pay-status");
    if (!n) return;
    n.textContent = msg || "";
    n.className = "pay-status" + (isErr ? " is-err" : "");
  }

  function mailtoFallback(q) {
    var cfg = window.REKASA_CHECKOUT || {};
    var email = cfg.contactEmail || "rekasakaryaindonesia@gmail.com";
    var on = Object.keys(state.on).filter(function (k) {
      return state.on[k];
    });
    var body = [
      "Pesan lisensi REKASA KARYA INDONESIA",
      "Bidang: " + industry().label,
      "Paket: " + planDef().label,
      "Total: " + rp(q.amountIdr),
      "Fitur: " + on.map(moduleLabel).join(", "),
      "Merek sendiri: " + (state.whiteLabel ? "ya" : "tidak"),
      "Usaha: " + (el("biz-name").value || "-"),
      "Kode: " + (el("biz-slug").value || "-"),
      "WA: " + (el("biz-phone").value || "-")
    ].join("%0A");
    return (
      "mailto:" +
      email +
      "?subject=" +
      encodeURIComponent("Pesan " + planDef().short + " — Rekasa") +
      "&body=" +
      body
    );
  }

  function loadSnap(clientKey, isProd) {
    return new Promise(function (resolve, reject) {
      if (window.snap) {
        resolve();
        return;
      }
      var s = document.createElement("script");
      s.src = isProd
        ? "https://app.midtrans.com/snap/snap.js"
        : "https://app.sandbox.midtrans.com/snap/snap.js";
      if (clientKey) s.setAttribute("data-client-key", clientKey);
      s.onload = function () {
        resolve();
      };
      s.onerror = function () {
        reject(new Error("Gagal memuat Midtrans Snap"));
      };
      document.head.appendChild(s);
    });
  }

  async function pay(ev) {
    ev.preventDefault();
    var q = quote();
    var cfg = window.REKASA_CHECKOUT || {};
    var name = (el("biz-name").value || "").trim();
    var phone = (el("biz-phone").value || "").trim();
    if (!name || !phone) {
      status("Isi nama usaha dan WA/HP.", true);
      return;
    }
    var btn = el("pay-btn");
    btn.disabled = true;
    status("Menyiapkan pembayaran Midtrans…");
    var payload = {
      industry_key: state.industry,
      plan_key: state.plan,
      modules: selectedModules(),
      white_label: state.whiteLabel,
      display_name: name,
      slug: (el("biz-slug").value || "").trim(),
      phone: phone,
      email: (el("biz-email").value || "").trim(),
      signer_name: ((el("biz-signer") && el("biz-signer").value) || "").trim(),
      amount_idr: q.amountIdr
    };
    var base = (cfg.supabaseUrl || "").replace(/\/$/, "");
    var anon = cfg.supabaseAnon || "";
    try {
      if (!base || !anon) throw new Error("no-edge");
      var res = await fetch(base + "/functions/v1/rekasa-midtrans-create", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: anon,
          Authorization: "Bearer " + anon
        },
        body: JSON.stringify(payload)
      });
      var data = await res.json();
      if (!data || !data.ok) throw new Error((data && data.error) || "Gagal bayar");
      if (data.redirect_url && !data.snap_token) {
        location.href = data.redirect_url;
        return;
      }
      if (data.snap_token && !data.mock_payment) {
        await loadSnap(
          data.client_key || cfg.midtransClientKey,
          data.is_production === true || cfg.midtransProduction === true
        );
        window.snap.pay(data.snap_token, {
          onSuccess: function () {
            status("Pembayaran diterima. Rekasa akan aktifkan lisensi.");
          },
          onPending: function () {
            status("Menunggu pembayaran Midtrans selesai.");
          },
          onError: function () {
            status("Pembayaran Midtrans gagal. Coba lagi.", true);
          },
          onClose: function () {
            status("Jendela Midtrans ditutup.");
          }
        });
        return;
      }
      throw new Error("mock");
    } catch (e) {
      status(
        "Gerbang Midtrans belum hidup di server. Pesanan dikirim ke email Rekasa — setelah kunci Midtrans dipasang, tombol ini buka Snap.",
        true
      );
      window.location.href = mailtoFallback(q);
    } finally {
      btn.disabled = false;
    }
  }

  if (page === "paket" && state.plan) applyPlanDefaults();
  render();
  var backPlan = el("back-paket");
  if (backPlan) {
    backPlan.addEventListener("click", function (ev) {
      ev.preventDefault();
      state.plan = null;
      render();
      syncUrl();
    });
  }
  var form = el("checkout-form");
  if (form) form.addEventListener("submit", pay);
  if (page === "paket" && params.get("bayar") === "selesai") {
    status("Pembayaran Midtrans selesai. Cek email untuk aktivasi lisensi.");
  }
})();
