(function () {
  var cat = window.REKASA_CATALOG;
  if (!cat) return;

  var state = {
    industry: "umum",
    plan: "paket_c",
    on: {},
    whiteLabel: false
  };

  function industry() {
    for (var i = 0; i < cat.industries.length; i++) {
      if (cat.industries[i].key === state.industry) return cat.industries[i];
    }
    return cat.industries[cat.industries.length - 1];
  }

  function planDef() {
    return cat.plans[state.plan];
  }

  function included(key) {
    var keys = industry().plans[state.plan] || [];
    return keys.indexOf(key) !== -1;
  }

  function visibleKeys() {
    var hide = industry().hide || [];
    var out = [];
    Object.keys(cat.modules).forEach(function (k) {
      if (hide.indexOf(k) === -1) out.push(k);
    });
    return out;
  }

  function moduleLabel(key) {
    var labels = industry().labels || {};
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
    state.whiteLabel = !!planDef().whiteLabel;
  }

  function el(id) {
    return document.getElementById(id);
  }

  function renderIndustries() {
    var box = el("industry-chips");
    box.innerHTML = "";
    cat.industries.forEach(function (ind) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "chip" + (ind.key === state.industry ? " is-on" : "");
      b.textContent = ind.label;
      b.addEventListener("click", function () {
        state.industry = ind.key;
        applyPlanDefaults();
        render();
      });
      box.appendChild(b);
    });
  }

  function renderPlans() {
    var box = el("plan-cards");
    box.innerHTML = "";
    ["paket_c", "paket_b", "paket_a"].forEach(function (key) {
      var p = cat.plans[key];
      var names = (industry().plans[key] || []).map(moduleLabel).join(", ");
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "card plan-card" + (state.plan === key ? " is-on" : "");
      btn.setAttribute("data-plan", key);
      btn.innerHTML =
        '<p class="eyebrow">' + p.eyebrow + "</p>" +
        "<h3>" + p.short + "</h3>" +
        '<p class="price">' + rp(p.priceIdr) + "</p>" +
        "<p>" + p.blurb + "</p>" +
        '<p class="muted" style="margin-top:12px">Termasuk: ' + names + "</p>";
      btn.addEventListener("click", function () {
        state.plan = key;
        applyPlanDefaults();
        render();
        el("fitur").scrollIntoView({ behavior: "smooth", block: "start" });
      });
      box.appendChild(btn);
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
      renderFeatureHints();
    });
    row.appendChild(text);
    row.appendChild(input);
    return row;
  }

  function renderFeatures() {
    var list = el("feature-list");
    list.innerHTML = "";
    var plan = planDef();
    list.appendChild(
      switchRow(
        "wl-toggle",
        "APK & web merek sendiri",
        plan.whiteLabel
          ? "Termasuk paket tertinggi."
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
    el("feature-industry").textContent = industry().label + " · " + plan.label;
  }

  function renderFeatureHints() {}

  function renderTotals() {
    var q = quote();
    el("quote-total").textContent = rp(q.amountIdr);
    var bits = ["Dasar " + rp(q.baseIdr)];
    if (q.addOnIdr) bits.push("add-on " + rp(q.addOnIdr));
    if (q.whiteLabelIdr) bits.push("merek sendiri " + rp(q.whiteLabelIdr));
    el("quote-break").textContent = bits.join(" · ");
    el("pay-btn").textContent = "Bayar " + rp(q.amountIdr) + " via Midtrans";
  }

  function render() {
    renderIndustries();
    renderPlans();
    renderFeatures();
    renderTotals();
    el("industry-blurb").textContent = industry().blurb;
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

  applyPlanDefaults();
  render();
  el("checkout-form").addEventListener("submit", pay);
  var q = new URLSearchParams(location.search);
  if (q.get("bayar") === "selesai") {
    status("Pembayaran Midtrans selesai. Cek email untuk aktivasi lisensi.");
  }
})();
