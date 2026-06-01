#!/usr/bin/env node
/*
 * parse-export.cjs - claude-migrate deterministic export parser (node-invoked).
 *
 * Invoked as:  node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs <export-dir> <run-dir> [op]
 * (Never run via shebang+exec-bit - Repo M-4.)
 *
 * Reads a Claude.ai data export folder and emits the normalized, DETERMINISTIC
 * unit/project/value artifacts the rest of the pipeline consumes. ZERO design
 * decisions: every rule below is pinned by SPEC.md (§5.3, §7.3, §7.4, §7.5, §7.6)
 * and research/domain-tech.md (§1.1-§1.5).
 *
 * Hard invariants implemented here:
 *  - M1: UNNN = sorted-ascending-uuid order; identical across modes / re-extractions.
 *  - H2: est_tokens computed DETERMINISTICALLY here (chars/4 EN, chars/3 Cyrillic/CJK),
 *        never by a model. cost_estimate is a pure function of these unit files.
 *  - §5.3 canonical text rule: prefer message.text; else join content[] type==="text"
 *        blocks in order; SKIP thinking/tool_use/tool_result; append
 *        attachments[].extracted_content; note files[].file_name as an "[image existed]"
 *        line; empty human turns -> "[no text]".
 *  - projects: prompt_template = Custom Instructions; docs[] = knowledge w/ full text;
 *        is_starter_project:true -> DROP (never emitted). PNN by sorted uuid.
 *  - unit_project_ref: export has no FK -> null for every unit (C2).
 *  - users.json: read for the email HASH only (account_check). NEVER copied, written,
 *        embedded, or logged in the clear (PII - research §1.5, SPEC §3.2/§7.5).
 *  - H-4 / §5.6: </script> (any case/variant) escaped before any HTML-embeddable field.
 *  - M2 / §7.5: duplicate clustering on normalized first-human-message + chat name;
 *        representative = lowest idx; computed in a deterministic serial pass.
 *
 * No external dependencies (Node CommonJS, stdlib only).
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/* ------------------------------------------------------------------ *
 * 0. Tiny utilities (deterministic, no randomness anywhere).
 * ------------------------------------------------------------------ */

function fail(msg, code) {
  process.stderr.write('FATAL parse-export: ' + msg + '\n');
  process.exit(typeof code === 'number' ? code : 1);
}

function readJsonFile(p) {
  let raw;
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch (e) {
    return { ok: false, error: 'read-failed' };
  }
  // Strip a UTF-8 BOM if present so JSON.parse does not choke.
  if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch (e) {
    return { ok: false, error: 'invalid-json' };
  }
}

function isObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function asArray(v) {
  return Array.isArray(v) ? v : [];
}

function asString(v) {
  return typeof v === 'string' ? v : '';
}

// SHA-256 hex of a string (used for the source email hash - value is hashed, never stored clear).
function sha256(s) {
  return crypto.createHash('sha256').update(String(s), 'utf8').digest('hex');
}

// Deterministic 8-hex digest used to build a stable slug suffix when a name is
// empty/generic. Purely a function of the uuid -> reproducible across runs.
function shortHash(s) {
  return sha256(s).slice(0, 8);
}

/* ------------------------------------------------------------------ *
 * 1. HTML-embed escaping (H-4 / §5.6).
 *    The copy page embeds bodies in <script id="data">; any </script>
 *    variant (case-insensitive, incl. "</SCRIPT >", "</script\n>") must be
 *    neutralized. We escape the closing-tag opener defensively. The copy page
 *    additionally JSON.parses + uses textContent, but the parser pre-escapes
 *    so a downstream byte-for-byte embed cannot break the page.
 * ------------------------------------------------------------------ */

function escapeScriptClose(text) {
  // /<\/(script)/gi -> "<\/$1" (SPEC §5.6, H-4). Matches "</script", "</SCRIPT",
  // "</script\n", "</script >" etc. - the close-bracket variants follow the tag
  // name and are harmless once the "</" is broken.
  return String(text).replace(/<\/(script)/gi, '<\\/$1');
}

/* ------------------------------------------------------------------ *
 * 2. Deterministic est_tokens (H2 / §7.3).
 *    chars/4 for Latin/Western text; chars/3 for Cyrillic/CJK-heavy text.
 *    We classify per-character and split the total so a mixed chat is scored
 *    fairly. Pure integer math -> identical on every run.
 * ------------------------------------------------------------------ */

// True for code points that tokenize denser (~2-3 chars/token): Cyrillic, CJK,
// Hiragana/Katakana, Hangul, and CJK-adjacent symbol blocks.
function isDenseCodePoint(cp) {
  return (
    (cp >= 0x0400 && cp <= 0x04ff) || // Cyrillic
    (cp >= 0x0500 && cp <= 0x052f) || // Cyrillic Supplement
    (cp >= 0x2de0 && cp <= 0x2dff) || // Cyrillic Extended-A
    (cp >= 0xa640 && cp <= 0xa69f) || // Cyrillic Extended-B
    (cp >= 0x3040 && cp <= 0x309f) || // Hiragana
    (cp >= 0x30a0 && cp <= 0x30ff) || // Katakana
    (cp >= 0x3400 && cp <= 0x4dbf) || // CJK Ext-A
    (cp >= 0x4e00 && cp <= 0x9fff) || // CJK Unified Ideographs
    (cp >= 0xf900 && cp <= 0xfaff) || // CJK Compatibility Ideographs
    (cp >= 0xac00 && cp <= 0xd7af) || // Hangul Syllables
    (cp >= 0x3000 && cp <= 0x303f) || // CJK Symbols & Punctuation
    (cp >= 0xff00 && cp <= 0xffef) // Halfwidth/Fullwidth Forms
  );
}

function estTokens(text) {
  const s = String(text || '');
  let denseChars = 0;
  let normalChars = 0;
  // Iterate by code point (handles surrogate pairs correctly + deterministically).
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    if (isDenseCodePoint(cp)) denseChars += 1;
    else normalChars += 1;
  }
  // chars/3 (dense) + chars/4 (normal); round each component up so empty-ish
  // text never collapses to a misleading 0 when it has any content.
  const dense = denseChars > 0 ? Math.ceil(denseChars / 3) : 0;
  const normal = normalChars > 0 ? Math.ceil(normalChars / 4) : 0;
  return dense + normal;
}

/* ------------------------------------------------------------------ *
 * 3. Canonical message-text extraction (§5.3 / research §1.1).
 * ------------------------------------------------------------------ */

// Extract the canonical resume text for ONE message object, deterministically.
//   1. prefer message.text if non-empty (assistant full replies live here).
//   2. else join content[] type==="text" blocks in order.
//   3. SKIP thinking / tool_use / tool_result blocks.
//   4. append attachments[].extracted_content (uploaded document text).
//   5. note files[].file_name as an "[image existed: NAME - not in export]" line.
//   6. empty human turns with no recoverable content -> "[no text]".
function extractMessageText(msg) {
  if (!isObject(msg)) return '[no text]';

  const sender = asString(msg.sender) || 'human';
  let core = '';

  const topText = asString(msg.text).trim();
  if (topText) {
    core = topText;
  } else {
    // Join only the type==="text" content blocks, in their original order.
    const parts = [];
    for (const block of asArray(msg.content)) {
      if (isObject(block) && block.type === 'text') {
        const t = asString(block.text);
        if (t) parts.push(t);
      }
      // thinking / tool_use / tool_result are intentionally skipped (noise for
      // continuation; they reference tools the new account may not have).
    }
    core = parts.join('\n\n').trim();
  }

  // Fold in uploaded-document text (recoverable context) and image notes.
  const extras = [];
  for (const att of asArray(msg.attachments)) {
    if (!isObject(att)) continue;
    const ec = asString(att.extracted_content).trim();
    if (ec) {
      const fname = asString(att.file_name).trim();
      const label = fname
        ? '[attachment: ' + fname + ']'
        : '[attachment]';
      extras.push(label + '\n' + ec);
    }
  }
  for (const f of asArray(msg.files)) {
    if (!isObject(f)) continue;
    const fname = asString(f.file_name).trim() || asString(f.file_uuid).trim() || 'unknown';
    // Image/binary bytes are NOT in the export - note existence, never invent content.
    extras.push('[image existed: ' + fname + ' - not in export]');
  }

  let combined = core;
  if (extras.length) {
    combined = (combined ? combined + '\n\n' : '') + extras.join('\n\n');
  }
  combined = combined.trim();

  if (!combined) {
    // Empty human/voice/attachment-only turn - never crash, mark it.
    return '[no text]';
  }
  return combined;
}

/* ------------------------------------------------------------------ *
 * 4. Slug + dedup normalization helpers (deterministic).
 * ------------------------------------------------------------------ */

// A name is "generic/empty" when it carries no identity (empty, whitespace,
// or a placeholder). We never trust the title as identity, but we DO use a
// meaningful name to keep an otherwise-empty chat as a KEEP candidate (M-6).
function isEmptyOrGenericName(name) {
  const n = asString(name).trim();
  if (!n) return true;
  const low = n.toLowerCase();
  if (low === '(no name)' || low === 'untitled' || low === 'new chat') return true;
  return false;
}

// File-system-safe slug for the UNNN__<slug> unit filename. Deterministic and
// domain-neutral; falls back to a uuid-derived suffix when the name is empty.
function slugify(name, uuid) {
  let base = asString(name)
    .trim()
    .toLowerCase()
    // Replace any run of non-(alnum/underscore/hyphen), including all Unicode
    // letters that are not ASCII, with a single hyphen. We keep ASCII alnum so
    // the slug is portable across filesystems and BEGIN/END marker scanners.
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48)
    .replace(/-+$/g, '');
  if (!base) base = 'chat-' + shortHash(asString(uuid));
  return base;
}

// Normalization for duplicate clustering (§7.5 / H-3): lowercase, collapse
// whitespace, strip punctuation, first 500 chars, over normalized
// first-human-message + chat name.
function normalizeForDedup(firstHumanText, name) {
  const combined = (asString(name) + ' ' + asString(firstHumanText));
  const norm = combined
    .toLowerCase()
    // Strip punctuation / symbols (Unicode-aware where supported): keep letters,
    // numbers, and whitespace, then collapse whitespace.
    .replace(/[^\p{L}\p{N}\s]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 500);
  return norm;
}

/* ------------------------------------------------------------------ *
 * 5. PNN slug for projects (sorted by uuid).
 * ------------------------------------------------------------------ */

function projectSlug(name, uuid) {
  let base = asString(name)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48)
    .replace(/-+$/g, '');
  if (!base) base = 'project-' + shortHash(asString(uuid));
  return base;
}

/* ------------------------------------------------------------------ *
 * 6. Atomic writers (same-dir mktemp + rename(2)) - deterministic content.
 * ------------------------------------------------------------------ */

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

// Stable JSON: 2-space indent, sorted object keys -> byte-identical across runs
// regardless of insertion order (supports AC-DETERMINISM / AC-PARSE).
function stableStringify(value) {
  return JSON.stringify(sortKeysDeep(value), null, 2) + '\n';
}

function sortKeysDeep(value) {
  if (Array.isArray(value)) return value.map(sortKeysDeep);
  if (isObject(value)) {
    const out = {};
    for (const k of Object.keys(value).sort()) out[k] = sortKeysDeep(value[k]);
    return out;
  }
  return value;
}

function writeAtomic(targetPath, content) {
  const dir = path.dirname(targetPath);
  ensureDir(dir);
  // mktemp in the SAME directory (rename(2) is only atomic within a filesystem).
  const tmp = path.join(dir, '.' + path.basename(targetPath) + '.' + process.pid + '.tmp');
  fs.writeFileSync(tmp, content, 'utf8');
  fs.renameSync(tmp, targetPath);
}

/* ------------------------------------------------------------------ *
 * 7. UNNN / PNN formatting.
 *    Fixed 3-digit zero-padded index keyed by sorted-uuid position (M1).
 * ------------------------------------------------------------------ */

function unnn(idx) {
  return 'U' + String(idx).padStart(3, '0');
}

function pnn(idx) {
  return 'P' + String(idx).padStart(2, '0');
}

/* ------------------------------------------------------------------ *
 * 8. Build one normalized unit from a raw chat object.
 *    Shape mirrors SOURCE extract_unit (§5.1):
 *      {idx,uuid,name,created_at,messages:[{sender,text}],attachments_text,
 *       image_refs,raw_token_est}
 * ------------------------------------------------------------------ */

function buildUnit(idx, chat) {
  const uuid = asString(chat.uuid);
  const name = asString(chat.name);
  const createdAt = asString(chat.created_at);

  const messages = [];
  const attachmentsText = [];
  const imageRefs = [];
  let firstHumanText = '';

  for (const m of asArray(chat.chat_messages)) {
    if (!isObject(m)) continue;
    const sender = asString(m.sender) || 'human';
    const text = extractMessageText(m);
    messages.push({ sender: sender, text: text });

    if (sender === 'human' && !firstHumanText && text && text !== '[no text]') {
      firstHumanText = text;
    }

    for (const att of asArray(m.attachments)) {
      if (!isObject(att)) continue;
      const ec = asString(att.extracted_content).trim();
      if (ec) attachmentsText.push(ec);
    }
    for (const f of asArray(m.files)) {
      if (!isObject(f)) continue;
      const fname = asString(f.file_name).trim() || asString(f.file_uuid).trim();
      if (fname) imageRefs.push(fname);
    }
  }

  // est_tokens (H2): sum over every message body + folded attachment text.
  const fullTextForTokens =
    messages.map((x) => x.text).join('\n') + '\n' + attachmentsText.join('\n');
  const rawTokenEst = estTokens(fullTextForTokens);

  return {
    idx: idx,
    unnn: unnn(idx),
    uuid: uuid,
    name: name,
    created_at: createdAt,
    messages: messages,
    attachments_text: attachmentsText,
    image_refs: imageRefs,
    raw_token_est: rawTokenEst,
    msg_count: messages.length,
    first_human_text: firstHumanText,
    name_is_generic: isEmptyOrGenericName(name),
  };
}

/* ------------------------------------------------------------------ *
 * 9. Render a unit to its units/pending/UNNN__<slug>.md file.
 *    Markdown, deterministic, </script>-escaped so it is copy-page-safe.
 * ------------------------------------------------------------------ */

function renderUnitMarkdown(unit) {
  const lines = [];
  const title = unit.name.trim() || '(no name)';
  lines.push('# ' + unnnTitle(unit) + ': ' + escapeScriptClose(title));
  lines.push('uuid: ' + unit.uuid);
  lines.push('created: ' + (unit.created_at || '(unknown)'));
  lines.push('messages: ' + unit.msg_count);
  lines.push('est_tokens: ' + unit.raw_token_est);
  if (unit.image_refs.length) {
    lines.push('images: ' + unit.image_refs.map(escapeScriptClose).join(', '));
  }
  lines.push('');
  lines.push('---');
  lines.push('');
  for (const m of unit.messages) {
    lines.push('## [' + m.sender + ']');
    lines.push('');
    lines.push(escapeScriptClose(m.text));
    lines.push('');
  }
  return lines.join('\n').replace(/\n+$/g, '\n');
}

function unnnTitle(unit) {
  return unit.unnn;
}

/* ------------------------------------------------------------------ *
 * 10. Projects (§1.3 / §5.3). is_starter_project:true -> DROP.
 * ------------------------------------------------------------------ */

function loadProjects(exportDir) {
  const projDir = path.join(exportDir, 'projects');
  const raw = [];
  // Two shapes seen: a projects/ folder of <uuid>.json, OR a single projects.json
  // array. Support both deterministically.
  if (fs.existsSync(projDir) && fs.statSync(projDir).isDirectory()) {
    const files = fs.readdirSync(projDir).filter((f) => f.endsWith('.json')).sort();
    for (const f of files) {
      const r = readJsonFile(path.join(projDir, f));
      if (!r.ok) continue;
      if (Array.isArray(r.value)) raw.push(...r.value.filter(isObject));
      else if (isObject(r.value)) raw.push(r.value);
    }
  }
  const singleFile = path.join(exportDir, 'projects.json');
  if (fs.existsSync(singleFile)) {
    const r = readJsonFile(singleFile);
    if (r.ok && Array.isArray(r.value)) raw.push(...r.value.filter(isObject));
  }

  // Drop Anthropic starter projects; sort remaining by uuid -> PNN.
  const kept = raw.filter((p) => p.is_starter_project !== true);
  kept.sort((a, b) => cmpStr(asString(a.uuid), asString(b.uuid)));

  return kept.map((p, i) => {
    const uuid = asString(p.uuid);
    const name = asString(p.name);
    const slug = projectSlug(name, uuid);
    const docs = asArray(p.docs)
      .filter(isObject)
      .map((d) => ({
        filename: asString(d.filename) || asString(d.uuid) || 'doc',
        content: asString(d.content),
      }));
    return {
      idx: i,
      pnn: pnn(i),
      pnn_slug: pnn(i) + '__' + slug,
      pid_uuid: uuid,
      name: name,
      prompt_template: asString(p.prompt_template),
      knowledge_docs: docs,
      is_starter: false,
    };
  });
}

/* ------------------------------------------------------------------ *
 * 11. memories.json (§1.4). Opt-in downstream; we only surface its presence
 *     + a deterministic size so confirm/G-MEMORIES can decide. We do NOT copy
 *     it into source/ here (PII; the extract skill handles redacted opt-in).
 * ------------------------------------------------------------------ */

function probeMemories(exportDir) {
  const p = path.join(exportDir, 'memories.json');
  if (!fs.existsSync(p)) return { exists: false, est_tokens: 0, entries: 0 };
  const r = readJsonFile(p);
  if (!r.ok) return { exists: true, est_tokens: 0, entries: 0, error: r.error };
  const arr = asArray(r.value);
  let text = '';
  let entries = 0;
  for (const item of arr) {
    if (isObject(item) && typeof item.conversations_memory === 'string') {
      text += item.conversations_memory + '\n';
      entries += 1;
    }
  }
  return { exists: true, est_tokens: estTokens(text), entries: entries };
}

/* ------------------------------------------------------------------ *
 * 12. users.json (§1.5). Read for the email HASH ONLY. The clear email,
 *     name, and phone are NEVER returned, written, embedded, or logged.
 * ------------------------------------------------------------------ */

function probeAccountHash(exportDir) {
  const p = path.join(exportDir, 'users.json');
  if (!fs.existsSync(p)) return null;
  const r = readJsonFile(p);
  if (!r.ok) return null;
  const arr = asArray(r.value);
  const first = arr.length && isObject(arr[0]) ? arr[0] : null;
  const email = first ? asString(first.email_address).trim().toLowerCase() : '';
  if (!email) return null;
  // Only the SHA-256 leaves this function.
  return sha256(email);
}

/* ------------------------------------------------------------------ *
 * 13. Stable string compare (locale-independent, deterministic).
 * ------------------------------------------------------------------ */

function cmpStr(a, b) {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

/* ------------------------------------------------------------------ *
 * 14. Duplicate clustering (M2 / §7.5). Representative = lowest idx.
 *     Serial post-pass over all units; deterministic.
 * ------------------------------------------------------------------ */

function clusterDuplicates(units) {
  const byNorm = new Map();
  for (const u of units) {
    const key = normalizeForDedup(u.first_human_text, u.name);
    if (!key) continue; // empty key -> not clusterable (treated as unique)
    if (!byNorm.has(key)) byNorm.set(key, []);
    byNorm.get(key).push(u.idx);
  }
  // Map each unit idx -> representative idx (lowest idx in its cluster) when the
  // cluster has >1 member; otherwise no duplicate.
  const repOf = new Map();
  for (const [, idxs] of byNorm) {
    if (idxs.length < 2) continue;
    idxs.sort((a, b) => a - b);
    const rep = idxs[0];
    for (const id of idxs) repOf.set(id, rep);
  }
  return repOf;
}

/* ------------------------------------------------------------------ *
 * 15. The conversations load + sort (M1 - sorted ascending uuid).
 * ------------------------------------------------------------------ */

function loadConversations(exportDir) {
  // Default location is conversations.json at the export root.
  const candidates = [
    path.join(exportDir, 'conversations.json'),
    path.join(exportDir, 'conversations', 'conversations.json'),
  ];
  let file = null;
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      file = c;
      break;
    }
  }
  if (!file) fail('conversations.json not found under ' + exportDir, 3);

  const r = readJsonFile(file);
  if (!r.ok) fail('conversations.json is ' + r.error, 3);
  const arr = asArray(r.value).filter(isObject);

  // M1: sort by uuid ascending, THEN assign idx. Identical across runs/modes.
  arr.sort((a, b) => cmpStr(asString(a.uuid), asString(b.uuid)));
  return arr.map((chat, i) => buildUnit(i, chat));
}

/* ------------------------------------------------------------------ *
 * 16. value/UNNN.value.json deterministic scaffold (§3.4).
 *     The parser writes the DETERMINISTIC fields only: est_tokens (H2),
 *     has_attachments, has_images, msg_count, looks_empty, name_is_generic,
 *     and the dedup representative. The categorical {bucket,value,confidence,
 *     reason,looks_duplicate_of} is filled later by preflight-value (haiku) or
 *     the --no-preflight heuristic engine - the parser NEVER decides a bucket.
 * ------------------------------------------------------------------ */

function buildValueScaffold(unit, repOf) {
  const isEmptyBody =
    unit.messages.every((m) => m.text === '[no text]') || unit.msg_count === 0;
  const dupRep = repOf.has(unit.idx) ? repOf.get(unit.idx) : null;
  return {
    idx: unit.idx,
    unnn: unit.unnn,
    uuid: unit.uuid,
    name: unit.name,
    // DETERMINISTIC token estimate (H2) - the sole source for cost_estimate.
    est_tokens: unit.raw_token_est,
    msg_count: unit.msg_count,
    has_attachments: unit.attachments_text.length > 0,
    has_images: unit.image_refs.length > 0,
    looks_empty: isEmptyBody,
    name_is_generic: unit.name_is_generic,
    // Dedup representative idx (M2); null when not part of a >1 cluster.
    duplicate_representative_idx: dupRep === unit.idx ? null : dupRep,
    is_duplicate_representative: dupRep === unit.idx,
    // Categorical fields are intentionally null here - set downstream, NOT by the parser.
    bucket: null,
    value: null,
    confidence: null,
    reason: null,
    looks_duplicate_of: dupRep !== null && dupRep !== unit.idx ? unnn(dupRep) : null,
  };
}

/* ------------------------------------------------------------------ *
 * 17. Main.
 * ------------------------------------------------------------------ */

function main() {
  const args = process.argv.slice(2);
  const exportDir = args[0];
  const runDir = args[1];
  const op = args[2] || 'parse';

  if (!exportDir) fail('usage: parse-export.cjs <export-dir> <run-dir> [op]', 2);
  if (!fs.existsSync(exportDir) || !fs.statSync(exportDir).isDirectory()) {
    fail('export dir not found or not a directory: ' + exportDir, 2);
  }

  // ---- account_check op: emit the source email hash ONLY (no PII). ----------
  if (op === 'account_check') {
    const hash = probeAccountHash(exportDir);
    process.stdout.write(stableStringify({ verified_account_email_hash: hash }));
    return;
  }

  // ---- enumerate op: emit sorted unit uuids (M1). ---------------------------
  if (op === 'enumerate') {
    const units = loadConversations(exportDir);
    process.stdout.write(stableStringify(units.map((u) => u.uuid)));
    return;
  }

  // ---- default 'parse' op: full deterministic emit into the run dir. --------
  if (!runDir) fail('usage: parse-export.cjs <export-dir> <run-dir> [op]', 2);

  // Defensive: never let the run dir resolve outside the user .planning tree by
  // a traversal trick. The caller passes an absolute run path; we only require
  // it exist (state.sh created it) - we do NOT create arbitrary parents.
  if (!fs.existsSync(runDir)) fail('run dir does not exist (init first): ' + runDir, 2);

  const units = loadConversations(exportDir);
  const projects = loadProjects(exportDir);
  const memories = probeMemories(exportDir);
  const sourceHash = probeAccountHash(exportDir);

  // Deterministic duplicate clustering (M2) over ALL units.
  const repOf = clusterDuplicates(units);

  // Write each unit's markdown to units/pending/ and its value scaffold to value/.
  const unitsPending = path.join(runDir, 'units', 'pending');
  const valueDir = path.join(runDir, 'value');
  const projectRoot = path.join(runDir, 'project');
  ensureDir(unitsPending);
  ensureDir(valueDir);

  let totalEstTokens = 0;
  const unitIndex = [];
  for (const u of units) {
    const slug = slugify(u.name, u.uuid);
    const mdName = u.unnn + '__' + slug + '.md';
    writeAtomic(path.join(unitsPending, mdName), renderUnitMarkdown(u));

    const scaffold = buildValueScaffold(u, repOf);
    writeAtomic(path.join(valueDir, u.unnn + '.value.json'), stableStringify(scaffold));

    totalEstTokens += u.raw_token_est;
    unitIndex.push({
      idx: u.idx,
      unnn: u.unnn,
      uuid: u.uuid,
      name: u.name,
      file: 'units/pending/' + mdName,
      created_at: u.created_at,
      msg_count: u.msg_count,
      est_tokens: u.raw_token_est,
      // unit_project_ref: export has NO foreign key -> always null (C2).
      project_ref: null,
    });
  }

  // Per-project artifacts: the parser stages the raw project facts under
  // project/<PNN__slug>/source.json so synthesize-project can build the two
  // instruction variants + knowledge docs deterministically. We do NOT generate
  // instructions here (that is the opus synth step).
  const projectIndex = [];
  for (const p of projects) {
    const pdir = path.join(projectRoot, p.pnn_slug);
    ensureDir(path.join(pdir, 'knowledge'));
    writeAtomic(
      path.join(pdir, 'source.json'),
      stableStringify({
        pnn: p.pnn,
        pnn_slug: p.pnn_slug,
        pid_uuid: p.pid_uuid,
        name: p.name,
        prompt_template: p.prompt_template,
        knowledge_docs: p.knowledge_docs.map((d) => ({ filename: d.filename })),
      })
    );
    // Stage knowledge docs as separate files (full text recoverable per §1.3).
    for (const d of p.knowledge_docs) {
      const docSlug = projectSlug(d.filename, d.filename) || 'doc';
      writeAtomic(path.join(pdir, 'knowledge', docSlug + '.md'), d.content + '\n');
    }
    projectIndex.push({ pnn: p.pnn, pnn_slug: p.pnn_slug, name: p.name, docs: p.knowledge_docs.length });
  }

  // A single deterministic manifest the extract skill / state.sh reads to seed
  // counters. NOTE: source_account_email_hash is the HASH ONLY - never the email.
  const manifest = {
    parser_version: '1',
    chats_total: units.length,
    projects_total: projectIndex.length,
    total_est_tokens: totalEstTokens,
    source_account_email_hash: sourceHash, // hash-only; users.json never copied/written clear
    memories: memories, // {exists, est_tokens, entries} - opt-in downstream
    units: unitIndex,
    projects: projectIndex,
  };
  writeAtomic(path.join(runDir, 'parse-manifest.json'), stableStringify(manifest));

  // Emit a terse machine-readable summary on stdout (the calling skill parses it).
  // PII-safe: only the hash, counts, and token totals leave the process.
  process.stdout.write(
    stableStringify({
      ok: true,
      chats_total: manifest.chats_total,
      projects_total: manifest.projects_total,
      total_est_tokens: manifest.total_est_tokens,
      memories_exists: memories.exists,
      source_account_email_hash: sourceHash,
      duplicate_clusters: countClusters(repOf),
    })
  );
}

function countClusters(repOf) {
  const reps = new Set();
  for (const [, rep] of repOf) reps.add(rep);
  return reps.size;
}

try {
  main();
} catch (e) {
  fail((e && e.message) ? e.message : String(e), 1);
}
