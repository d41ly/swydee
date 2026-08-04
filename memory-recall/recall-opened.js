#!/usr/bin/env node
/**
 * recall-opened — PostToolUse observer that INFERS which recall hit was read.
 *
 * FORKED from inCMS `.claude/hooks/recall-opened.js` at fd6274d. ONE construct is edited and the
 * rest is upstream's byte for byte, so a re-pull is a three-way merge: the corpus root. Upstream
 * tests a literal `memory/` prefix and then scans for the literal `/memory/` boundary, and both
 * return null for a corpus rooted anywhere else — after which main() bails, indistinguishable from
 * "no read matched". `MEMORY_ROOT` is a per-repo value the memory-tree kit's own conf example ships,
 * so this fork derives the root from the log's `shown_paths` array, which is corpus-relative by
 * construction. No conf parse (that would be a third copy of the conf grammar, in a third language,
 * gated by nothing), no rendering step, no second place for the root to drift.
 *
 * WHY: `memory-recall/query.py` logs every query, but the log can only answer
 * "what was asked" unless someone records which hit they actually opened.
 * Measured upstream over the first 110 queries, `--opened` was used TWICE.
 *
 * WHAT IT DOES: on every `Read`, if a recall query ran RECENTLY and has no
 * opened record yet, append one saying which rank the read path sat at.
 *
 * WHAT IT CANNOT DO, stated so nobody reads more into the data than is there:
 *   - It records a Read anywhere in THIS REPOSITORY -- this checkout or any worktree
 *     sharing its git common dir. A read of another repo's corpus is ignored.
 *   - It observes a Read, not a decision. A file opened for an unrelated reason
 *     inside the window is indistinguishable from a deliberate pick. Every
 *     record it writes carries `inferred: true` so analysis can separate them
 *     from the hand-recorded `--opened` ones.
 *   - `in_shown: false` means "the caller read a corpus file that was not in
 *     the emitted list". That is evidence the answer was NOT shown, which is
 *     the most valuable signal here — but it is not proof the query failed.
 *   - A query that showed NOTHING (`shown_paths: []`) records nothing, because
 *     the root is derived from that array and an empty array declares no root.
 *     That is the one case upstream's root literal covered and this does not;
 *     the trade is a hook that works on every corpus root instead of on one.
 *   - Only the FIRST read after a query is recorded. A caller who reads five
 *     files produces one record, not five.
 *
 * SAFETY: this runs on every Read in the session. It never blocks, never
 * writes to the worktree, reads only a bounded TAIL of the log, and exits 0 on
 * every path including every error. A recall log is worth less than a Read.
 *
 * Wiring: PostToolUse matcher "Read" — `recall-opened.fragment.json` beside this file, merged by
 * `settings-merge.py --fragment`. Lands DARK: `adopt-memory-recall.sh` copies this file only under
 * `--with-hook`, so a project that does not want it has no file and no wiring alarm.
 */
'use strict'

const fs = require('fs')
const path = require('path')

const WINDOW_MS = 30 * 60 * 1000 // a query older than this is not what you are reading
const TAIL_BYTES = 128 * 1024 // enough to hold the recent records; the log grows unbounded

/**
 * The COMMON git dir — the primary tree's `.git`, shared by every worktree, which is where
 * `query.py` writes the log (`--git-common-dir`, not `--git-dir`). In a linked worktree `.git` is a
 * FILE holding `gitdir: <path>`; resolving that to `<common>/worktrees/<name>` and then reading its
 * `commondir` is the whole dance, and it is why this must not assume a directory.
 */
function gitCommonDir(root) {
  const dot = path.join(root, '.git')
  let st
  try {
    st = fs.statSync(dot)
  } catch {
    return null
  }
  if (st.isDirectory()) return dot
  const m = /^gitdir:\s*(.+)$/m.exec(fs.readFileSync(dot, 'utf8'))
  if (!m) return null
  const gitdir = path.resolve(root, m[1].trim())
  const cd = path.join(gitdir, 'commondir')
  if (!fs.existsSync(cd)) return gitdir
  return path.resolve(gitdir, fs.readFileSync(cd, 'utf8').trim())
}

/**
 * The corpus root(s) the log itself declares, as leading path segments.
 *
 * `shown_paths` holds the emitted hits spelled relative to the repo root, and every corpus file is
 * under `MEMORY_ROOT` by construction (`corpus_files` is `git ls-files <MEMORY_ROOT>`), so the
 * distinct first segments ARE the root as this repo spells it. A multi-segment root (`docs/memory`)
 * yields its first segment, which is broader than the corpus and can therefore only over-record an
 * `in_shown: false` row — never miss one, which is the failure the literal had.
 */
function rootSegments(shownPaths) {
  const segs = new Set()
  for (const p of shownPaths) {
    if (typeof p !== 'string') continue
    const first = p.split('/')[0]
    if (first && first !== '.' && first !== '..') segs.add(first)
  }
  return segs
}

/**
 * The read path as `<root>/...` relative to a checkout of THIS repository, or null.
 *
 * This tree first. Failing that, any OTHER checkout sharing our COMMON git dir: feature work
 * happens in sibling worktrees while the hook is wired out of the primary tree, so requiring the
 * read to land inside the hook's own checkout left the inferred stream permanently EMPTY for the
 * majority session shape -- measured upstream, an identical `memory/architecture/DECISIONS.md`
 * recorded in the checkout and appended nothing from a sibling worktree or from the nested
 * `.claude/worktrees/` spelling (upstream closing review F16).
 *
 * Membership is decided by the git common dir, which is what "the same repository" means; a
 * path prefix is not. It costs one statSync rather than a `git rev-parse` fork per Read.
 */
function relUnderThisRepo(readPath, mainRoot, common, roots) {
  const own = path.relative(mainRoot, path.resolve(readPath)).split(path.sep).join('/')
  if (!own.startsWith('..') && roots.has(own.split('/')[0])) return own
  const abs = path.resolve(readPath).split(path.sep).join('/')
  const want = path.resolve(common)
  // Every `/<root>/` boundary, innermost first. A checkout may itself sit under a directory named
  // like the corpus root, and only the git dir can say which split is a real repository root.
  for (const seg of roots) {
    const needle = '/' + seg + '/'
    for (let i = abs.lastIndexOf(needle); i > 0; i = abs.lastIndexOf(needle, i - 1)) {
      const other = gitCommonDir(abs.slice(0, i))
      if (other && path.resolve(other) === want) return abs.slice(i + 1)
    }
  }
  return null
}

function main(payload) {
  const readPath = payload?.tool_input?.file_path
  if (!readPath) return

  // Derive the repo from THIS FILE's location, never from cwd or `git rev-parse`:
  // <checkout>/.claude/hooks/recall-opened.js -> <checkout>. `--show-toplevel` fails under WSL bash
  // in a linked worktree (it cannot read a `gitdir: C:/...` pointer), and shelling out per Read
  // would cost a fork on the hottest tool in the session.
  const mainRoot = path.resolve(__dirname, '..', '..')
  const common = gitCommonDir(mainRoot)
  if (!common) return
  const log = path.join(common, 'recall', 'queries.jsonl')
  if (!fs.existsSync(log)) return

  const size = fs.statSync(log).size
  const fd = fs.openSync(log, 'r')
  let tail
  try {
    const start = Math.max(0, size - TAIL_BYTES)
    const buf = Buffer.alloc(size - start)
    fs.readSync(fd, buf, 0, buf.length, start)
    tail = buf.toString('utf8')
  } finally {
    fs.closeSync(fd)
  }

  // A truncated first line is not JSON; dropping it is correct, not a workaround.
  const rows = []
  for (const line of tail.split('\n')) {
    if (!line.trim()) continue
    try {
      rows.push(JSON.parse(line))
    } catch {
      /* partial or corrupt line */
    }
  }
  if (!rows.length) return

  let last = null
  for (const r of rows) if (r.type === 'query') last = r
  if (!last || !Array.isArray(last.shown_paths)) return

  // Already recorded — by hand or by a previous fire. One record per query.
  for (const r of rows) if (r.type === 'opened' && r.of_qid === last.qid) return

  const at = Date.parse(last.at)
  if (!Number.isFinite(at) || Date.now() - at > WINDOW_MS) return

  const roots = rootSegments(last.shown_paths)
  if (!roots.size) return

  // Compare repo-relative, forward-slashed. An absolute Windows path and a `memory/x.md` citation
  // are the same file spelled two ways, and endsWith on the raw string matches neither reliably.
  const rel = relUnderThisRepo(readPath, mainRoot, common, roots)
  if (!rel) return

  const rank = last.shown_paths.indexOf(rel) + 1
  const rec = {
    qid: (rows[rows.length - 1].qid || 0) + 1,
    at: new Date().toISOString().replace(/\.\d+Z$/, '+00:00'),
    type: 'opened',
    of_qid: last.qid,
    rank: rank || null,
    in_shown: rank > 0,
    inferred: true,
    path: rel,
  }
  fs.appendFileSync(log, JSON.stringify(rec) + '\n', 'utf8')
}

let raw = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', (c) => (raw += c))
process.stdin.on('end', () => {
  try {
    main(JSON.parse(raw))
  } catch {
    /* never fail a Read for a telemetry record */
  }
  process.exit(0)
})
process.stdin.on('error', () => process.exit(0))
