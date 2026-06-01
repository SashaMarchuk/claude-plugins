/**
 * verify-copy-page.cjs - headless byte-exact verifier for the claude-migrate copy page.
 *
 * Generalized port of the proven prototype work/verify.cjs. Domain-neutral: knows
 * nothing about any source domain; everything is derived at runtime from the page
 * and the per-card payload files.
 *
 * Invoked as:
 *   node ${CLAUDE_PLUGIN_ROOT}/bin/verify-copy-page.cjs <out-dir>
 * where <out-dir> contains the built page (index.html), payloads/<id>.json, and
 * (optionally) a .gitignore. Defaults to ./out relative to the cwd when omitted.
 *
 * It satisfies the SPEC §5.6 DOM/JS contract and the §10 acceptance IDs:
 *   - AC-VERIFY: exits 0 on a conformant golden page, 1 on a byte-mismatch fixture.
 *   - AC-ESCAPE: </SCRIPT >, </script\n>, <!-- in a brief body copy byte-exact.
 *   - AC-COPYFAIL: a file:// (non-granted clipboard) copy failure does NOT falsely
 *     mark the card copied (Edge H-5).
 *
 * Requires a local Node + Playwright runtime (references/node-playwright-preflight.md).
 *
 * Exit codes: 0 = all assertions PASS; 1 = one or more assertions FAIL;
 *             2 = FATAL (bad args / page would not load / Playwright missing).
 */

'use strict';

const fs = require('fs');
const path = require('path');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error(
    'FATAL: playwright is not installed. See references/node-playwright-preflight.md.\n' +
      (e && e.message ? e.message : String(e))
  );
  process.exit(2);
}

/* ------------------------------------------------------------------ helpers */

function fail(msg) {
  console.error('FATAL: ' + msg);
  process.exit(2);
}

// Resolve the out-dir argument; default to ./out under the cwd.
const outDirArg = process.argv[2] || path.join(process.cwd(), 'out');
const OUT_DIR = path.resolve(outDirArg);
const INDEX_HTML = path.join(OUT_DIR, 'index.html');
const PAYLOAD_DIR = path.join(OUT_DIR, 'payloads');

if (!fs.existsSync(INDEX_HTML)) {
  fail('no index.html under ' + OUT_DIR + ' (expected ' + INDEX_HTML + ')');
}

const PAGE_URL = 'file://' + INDEX_HTML;

/**
 * Build the expected map id -> {name, body}. Source of truth is the per-card
 * payload files (out/payloads/<id>.json), which hold the byte-exact body even
 * when the page lazy-loads above the inline threshold (Edge H-2). If a payload
 * file is missing for an id, we fall back to the inline DATA body captured from
 * the page itself.
 */
function loadExpected(idsFromPage, inlineById) {
  const expected = {};
  for (const id of idsFromPage) {
    const pf = path.join(PAYLOAD_DIR, id + '.json');
    if (fs.existsSync(pf)) {
      let parsed;
      try {
        parsed = JSON.parse(fs.readFileSync(pf, 'utf8'));
      } catch (e) {
        fail('payload ' + pf + ' is not valid JSON: ' + (e && e.message));
      }
      // Payload may be {name, body} or the full card shape {id, name, body, ...}.
      expected[id] = {
        name: typeof parsed.name === 'string' ? parsed.name : (inlineById[id] && inlineById[id].name) || '',
        body: typeof parsed.body === 'string' ? parsed.body : (inlineById[id] && inlineById[id].body) || ''
      };
    } else if (inlineById[id]) {
      expected[id] = { name: inlineById[id].name || '', body: inlineById[id].body || '' };
    } else {
      fail('no payload file and no inline body for card id=' + id);
    }
  }
  return expected;
}

/* ------------------------------------------------------------------ runner */

(async () => {
  const results = { tests: [], mismatches: [], clipboardMode: null };
  const ok = (name, cond, extra) =>
    results.tests.push(Object.assign({ name, pass: !!cond }, extra ? { extra } : {}));

  const browser = await chromium.launch({ headless: true });

  // ---- Phase 1: granted-clipboard context (the byte-exact happy path) ------
  const ctx = await browser.newContext();
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write']);
  const page = await ctx.newPage();
  page.on('dialog', (d) => d.accept());

  const consoleErrors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') consoleErrors.push(m.text());
  });
  page.on('pageerror', (e) => consoleErrors.push('PAGEERROR: ' + (e && e.message ? e.message : String(e))));

  let resp;
  try {
    resp = await page.goto(PAGE_URL, { waitUntil: 'load' });
  } catch (e) {
    await browser.close();
    fail('could not load ' + PAGE_URL + ': ' + (e && e.message ? e.message : String(e)));
  }
  if (resp && typeof resp.status === 'function' && resp.status() >= 400) {
    await browser.close();
    fail('page returned HTTP ' + resp.status() + ' for ' + PAGE_URL);
  }

  // Read DATA + ids straight from the page (escaped </script>, JSON.parse path).
  const pageData = await page.evaluate(() => {
    const raw = document.getElementById('data');
    const parsed = window.DATA
      ? window.DATA
      : raw
      ? JSON.parse(raw.textContent)
      : null;
    if (!parsed) return null;
    return parsed.map((d) => ({
      id: d.id,
      group: d.group,
      kind: d.kind,
      // body may be absent inline when lazy-loaded above the threshold (H-2).
      name: typeof d.name === 'string' ? d.name : null,
      body: typeof d.body === 'string' ? d.body : null
    }));
  });
  if (!pageData || !Array.isArray(pageData) || pageData.length === 0) {
    await browser.close();
    fail('#data did not parse into a non-empty DATA array');
  }

  const ids = pageData.map((d) => d.id);
  const N = ids.length;
  const inlineById = {};
  for (const d of pageData) inlineById[d.id] = { name: d.name, body: d.body };
  const expected = loadExpected(ids, inlineById);

  // A. counts -------------------------------------------------------------
  const tot = (await page.$eval('#tot', (e) => e.textContent.trim()).catch(() => null));
  const dataLen = await page.evaluate(() =>
    window.DATA ? window.DATA.length : JSON.parse(document.getElementById('data').textContent).length
  );
  const cnt0 = (await page.$eval('#cnt', (e) => e.textContent.trim()).catch(() => null));
  ok('DATA has ' + N + ' entries', dataLen === N, { dataLen });
  ok('#tot shows ' + N, tot === String(N), { tot });
  ok('initial copied counter = 0', cnt0 === '0', { cnt0 });

  // Detect real-clipboard read vs the __lastCopied fallback. Click the first
  // brief, then try to read the clipboard; if that throws, use window.__lastCopied.
  await page.click('#card-' + ids[0] + ' .btn-primary');
  await page.waitForTimeout(60);
  let clipboardMode = '__lastCopied';
  try {
    const probe = await page.evaluate(() => navigator.clipboard.readText());
    if (typeof probe === 'string') clipboardMode = 'clipboard';
  } catch (e) {
    clipboardMode = '__lastCopied';
  }
  results.clipboardMode = clipboardMode;

  const readCopied = async () =>
    clipboardMode === 'clipboard'
      ? page.evaluate(() => navigator.clipboard.readText())
      : page.evaluate(() => window.__lastCopied);

  // B. loop EVERY card: click Copy-brief -> compare copied vs payload body ----
  for (const id of ids) {
    await page.click('#card-' + id + ' .btn-primary');
    await page.waitForTimeout(10);
    const copied = await readCopied();
    const exp = expected[id].body;
    if (copied !== exp) {
      results.mismatches.push({
        id,
        len_copied: (copied == null ? '' : String(copied)).length,
        len_expected: (exp == null ? '' : String(exp)).length
      });
    }
  }
  ok('all ' + N + ' cards copy EXACT payload body (byte-for-byte)', results.mismatches.length === 0, {
    mismatches: results.mismatches.length
  });

  // After copying all: counter == N, all cards marked, bar at 100%.
  const cntAll = (await page.$eval('#cnt', (e) => e.textContent.trim()).catch(() => null));
  const copiedCards = await page.$$eval('.card.copied', (els) => els.length);
  const barW = (await page.$eval('#barfill', (e) => e.style.width).catch(() => null));
  ok('counter = ' + N + ' after copying all', cntAll === String(N), { cntAll });
  ok('all ' + N + ' cards show copied state', copiedCards === N, { copiedCards });
  ok('progress bar = 100%', barW === '100%', { barW });

  // C. persistence across reload -----------------------------------------
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(60);
  const cntReload = (await page.$eval('#cnt', (e) => e.textContent.trim()).catch(() => null));
  const copiedReload = await page.$$eval('.card.copied', (els) => els.length);
  ok('marks persist after reload (counter)', cntReload === String(N), { cntReload });
  ok('marks persist after reload (cards)', copiedReload === N, { copiedReload });

  // D. reset (after persistence proven) ----------------------------------
  await page.click('#resetBtn');
  await page.waitForTimeout(150);
  const cntReset = (await page.$eval('#cnt', (e) => e.textContent.trim()).catch(() => null));
  const copiedReset = await page.$$eval('.card.copied', (els) => els.length);
  // The localStorage key is derived at build time as "claudeMig.copied.<RUN>.v1".
  // Read whatever key the page actually uses (it sets window.KEY per §5.6).
  const lsAfter = await page.evaluate(() => {
    const k = window.KEY || null;
    if (k) return localStorage.getItem(k);
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key && key.indexOf('claudeMig.copied.') === 0) return localStorage.getItem(key);
    }
    return null;
  });
  ok('reset clears counter to 0', cntReset === '0', { cntReset });
  ok('reset clears copied cards', copiedReset === 0, { copiedReset });
  ok('reset clears localStorage marks', lsAfter === '{}' || lsAfter === null, { lsAfter });

  // E. name button copies the name only and does NOT mark the card -------
  // Domain-neutral: prefer a card whose payload name is non-empty (and, when
  // available, a chat card) so the assertion is robust regardless of card order.
  let nameId =
    pageData.find((d) => d.kind === 'chat' && expected[d.id] && expected[d.id].name) ||
    pageData.find((d) => expected[d.id] && expected[d.id].name) ||
    pageData[0];
  nameId = nameId.id;
  // The second button in the card's actions row is "Copy name" (§5.6).
  await page.click('#card-' + nameId + ' .acts button:nth-child(2)');
  await page.waitForTimeout(40);
  const nameCopied = await readCopied();
  const nameMarked = await page.$eval('#card-' + nameId, (el) => el.classList.contains('copied'));
  ok('name button copies the chat name', nameCopied === expected[nameId].name, {
    got: (nameCopied == null ? '' : String(nameCopied)).slice(0, 60)
  });
  ok('name button does NOT mark card copied', nameMarked === false, { nameMarked });

  // F. search filter toggles .card.hide by data-name ---------------------
  // Derive a query that matches at least one card but not all, from the data.
  let query = '';
  if (N > 1) {
    const firstName = expected[ids[0]].name || '';
    // Use a distinctive token from the first card's name; fall back to a slice.
    const tokens = firstName.split(/\s+/).filter((t) => t.length >= 3);
    query = tokens.length ? tokens[0] : firstName.slice(0, 4);
  }
  let searchAsserted = false;
  if (query) {
    await page.fill('#search', query);
    await page.waitForTimeout(120);
    const visible = await page.$$eval('.card:not(.hide)', (els) => els.length);
    const hidden = await page.$$eval('.card.hide', (els) => els.length);
    // A good query shows >=1 and hides >=1; if the token happens to be ubiquitous
    // we still assert it does not crash and at least keeps the matching card.
    if (visible > 0 && hidden > 0) {
      ok('search filters cards (some shown, some hidden)', true, { visible, hidden, query });
      searchAsserted = true;
    } else {
      // Fall back to a guaranteed-no-match query to prove hide works at all.
      const noMatch = '__zzz_no_match_' + Date.now();
      await page.fill('#search', noMatch);
      await page.waitForTimeout(120);
      const v2 = await page.$$eval('.card:not(.hide)', (els) => els.length);
      const h2 = await page.$$eval('.card.hide', (els) => els.length);
      ok('search hides all cards on a no-match query', v2 === 0 && h2 === N, { v2, h2 });
      searchAsserted = true;
    }
    await page.fill('#search', '');
    await page.waitForTimeout(80);
    const visibleCleared = await page.$$eval('.card:not(.hide)', (els) => els.length);
    ok('clearing search restores all cards', visibleCleared === N, { visibleCleared });
  }
  if (!searchAsserted) {
    // Single-card page: still confirm the search box exists and a no-match hides it.
    await page.fill('#search', '__zzz_no_match_' + Date.now());
    await page.waitForTimeout(120);
    const v2 = await page.$$eval('.card:not(.hide)', (els) => els.length);
    ok('search hides the only card on a no-match query', v2 === 0, { v2 });
    await page.fill('#search', '');
  }

  // 0 console errors over the whole granted-context run.
  ok('0 console / page errors', consoleErrors.length === 0, { consoleErrors });

  await page.close();
  await ctx.close();

  // ---- Phase 2: NON-granted (file://) copy-fail assertion (Edge H-5) -------
  // A fresh context with NO clipboard permissions. navigator.clipboard.writeText
  // rejects and execCommand on file:// is unreliable, so onCopyBrief must NOT mark
  // the card copied; it must surface the error state instead.
  const ctx2 = await browser.newContext();
  const page2 = await ctx2.newPage();
  page2.on('dialog', (d) => d.accept());
  // Force every copy path to fail so we exercise the error branch deterministically,
  // independent of headless clipboard quirks: stub writeText to reject and make
  // execCommand('copy') return false.
  await page2.addInitScript(() => {
    try {
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        get() {
          return { writeText: () => Promise.reject(new Error('not allowed')) };
        }
      });
    } catch (e) {
      /* some engines disallow redefining; the execCommand stub below still applies */
    }
    const origExec = document.execCommand && document.execCommand.bind(document);
    document.execCommand = function (cmd) {
      if (cmd === 'copy') return false;
      return origExec ? origExec.apply(document, arguments) : false;
    };
  });

  await page2.goto(PAGE_URL, { waitUntil: 'load' });
  await page2.waitForTimeout(60);

  const failId = ids[0];
  await page2.click('#card-' + failId + ' .btn-primary');
  await page2.waitForTimeout(120);

  const failState = await page2.evaluate((cid) => {
    const card = document.getElementById('card-' + cid);
    const cnt = document.getElementById('cnt');
    return {
      marked: card ? card.classList.contains('copied') : null,
      hasError: card ? card.classList.contains('copy-error') : null,
      counter: cnt ? cnt.textContent.trim() : null
    };
  }, failId);

  ok('copy failure does NOT falsely mark the card copied (H-5)', failState.marked === false, failState);
  ok('copy failure surfaces an error state (.copy-error)', failState.hasError === true, failState);
  ok('copy failure does NOT advance the copied counter', failState.counter === '0', failState);

  await page2.close();
  await ctx2.close();
  await browser.close();

  // ---- Report -----------------------------------------------------------
  const passed = results.tests.filter((t) => t.pass).length;
  const failed = results.tests.filter((t) => !t.pass);
  console.log(
    JSON.stringify(
      {
        outDir: OUT_DIR,
        cards: N,
        clipboardMode: results.clipboardMode,
        passed,
        total: results.tests.length,
        failed,
        mismatches: results.mismatches,
        consoleErrors
      },
      null,
      2
    )
  );
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e && e.stack ? e.stack : e);
  process.exit(2);
});
