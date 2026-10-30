/** Bounded passage retrieval: never search/rank the corpus in PostgreSQL. */
export type Passage = {
  verse_id: string; ref: string; work_slug: string; edition_id: string; edition_title: string;
  language_code: string; body: string; attribution_text: string; rank: number;
};
export type Candidate = { work_slug: string; ref: string };
const WORKS: Record<string, string> = { SB: 'bhagavata-purana', BG: 'bhagavad-gita' };
export const MAX_CANDIDATES = 8;
// Structural client keeps the helper independently testable. Caller JWT/RLS is retained.
// deno-lint-ignore no-explicit-any
export type RetrievalClient = { from: (table: string) => any };

export function candidates(value: unknown): Candidate[] {
  if (!Array.isArray(value)) return [];
  const out: Candidate[] = [];
  for (const item of value.slice(0, 32)) {
    if (!item || typeof item !== 'object') continue;
    const { work_slug, ref } = item;
    const parts = work_slug === WORKS.SB ? 3 : work_slug === WORKS.BG ? 2 : 0;
    if (!parts || typeof ref !== 'string' || !/^\d{1,3}(?:\.\d{1,3}){1,2}$/.test(ref)) continue;
    const numbers = ref.split('.').map(Number);
    if (numbers.length !== parts || numbers.some((n) => n < 1)) continue;
    const normalized = numbers.join('.');
    if (!out.some((c) => c.work_slug === work_slug && c.ref === normalized)) out.push({ work_slug, ref: normalized });
    if (out.length === MAX_CANDIDATES) break;
  }
  return out;
}

/** Names used by readers as well as the canonical citation short codes. */
const WORK_NAME = /\b(BG|SB|Bhagavad[ -]+G[iī]t[aā]|(?:(?:Srimad|Shrimad|Śrīmad|Sri|Shri|Śrī)[ -]+)?Bh[aā]gavat(?:am|a(?:[ -]+Pur[aā]ṇa)?))\b/giu;

function namedWork(name: string): string {
  return /^(?:BG|Bhagavad)/i.test(name) ? WORKS.BG : WORKS.SB;
}

/** Explicit names override the app's default work for general questions too. */
export function requestedWork(question: string, fallback: string | null): string | null {
  const names = [...question.matchAll(WORK_NAME)].map((m) => namedWork(m[0]));
  const unique = [...new Set(names)];
  return unique.length === 1 ? unique[0] : unique.length > 1 ? null : fallback;
}

export function explicitCandidates(question: string, work: string | null): Candidate[] {
  const found: Candidate[] = [];
  const names = [...question.matchAll(WORK_NAME)];
  const defaultWork = requestedWork(question, work);
  for (const m of question.matchAll(/\b(\d{1,3}(?:\.\d{1,3}){1,2})\b/g)) {
    // Bind to the preceding work name for comparisons, rather than letting
    // the UI's default SB scope swallow a named Gita reference.
    const preceding = names.filter((n) => n.index! < m.index!).at(-1);
    const scope = preceding ? namedWork(preceding[0]) : defaultWork;
    found.push({ work_slug: scope ?? '', ref: m[1] });
  }
  return candidates(found);
}

export async function retrievePassages(
  sb: RetrievalClient, question: string, work: string | null, language: string,
  select: () => Promise<unknown>,
): Promise<Passage[]> {
  const explicit = explicitCandidates(question, work);
  const scope = requestedWork(question, work);
  const refs = explicit.length ? explicit : candidates(await select()).filter((c) => !scope || c.work_slug === scope);
  if (!refs.length) {
    console.info("ask.retrieval", JSON.stringify({ stage: "candidates", count: 0 }));
    return [];
  }
  const { data: works, error: we } = await sb.from('works').select('id,slug')
    .in('slug', [...new Set(refs.map((c) => c.work_slug))]).eq('status', 'published').limit(2);
  if (we) throw we;
  console.info("ask.retrieval", JSON.stringify({ stage: "works", count: works?.length ?? 0 }));
  const passages: Passage[] = [];
  for (const w of works ?? []) {
    // Unique btree (work_id, ref), no text transforms, OR ranks or wildcard scans.
    const { data: verses, error: ve } = await sb.from('verses').select('id,ref')
      .eq('work_id', w.id).in('ref', refs.filter((c) => c.work_slug === w.slug).map((c) => c.ref))
      .eq('status', 'published').limit(MAX_CANDIDATES);
    if (ve) throw ve;
    console.info("ask.retrieval", JSON.stringify({ stage: "verses", work: w.slug, count: verses?.length ?? 0 }));
    if (!verses?.length) continue;
    const { data: editions, error: ee } = await sb.from('v_editions')
      .select('id,title,language_code,kind,script_code,attribution_text').eq('work_id', w.id).eq('status', 'published').order('sort_order').limit(32);
    if (ee) throw ee;
    const eligible = (editions ?? []).filter((e: Record<string, string>) =>
      (e.kind === 'translation' && e.language_code === language) || (e.kind === 'transliteration' && e.script_code === 'Latn')).slice(0, 4);
    console.info("ask.retrieval", JSON.stringify({ stage: "editions", work: w.slug, count: eligible.length }));
    if (!eligible.length) continue;
    // Unique btree (verse_id, edition_id); at most 8 verses x 4 editions.
    const { data: contents, error: ce } = await sb.from('verse_contents').select('verse_id,edition_id,body')
      .in('verse_id', verses.map((v: { id: string }) => v.id)).in('edition_id', eligible.map((e: { id: string }) => e.id))
      .eq('status', 'published').limit(MAX_CANDIDATES * 4);
    if (ce) throw ce;
    console.info("ask.retrieval", JSON.stringify({ stage: "contents", work: w.slug, count: contents?.length ?? 0 }));
    for (const v of verses) {
      for (const e of eligible) {
        const text = (contents ?? []).find((c: { verse_id: string; edition_id: string }) => c.verse_id === v.id && c.edition_id === e.id);
        if (text) passages.push({ verse_id: v.id, ref: v.ref, work_slug: w.slug, edition_id: e.id,
          edition_title: e.title, language_code: e.language_code, body: text.body, attribution_text: e.attribution_text, rank: 1 });
      }
    }
  }
  return passages;
}
