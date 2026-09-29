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

export function explicitCandidates(question: string, work: string | null): Candidate[] {
  const found: Candidate[] = [];
  for (const m of question.matchAll(/\b(?:(SB|BG)\s+)?(\d{1,3}(?:\.\d{1,3}){1,2})\b/gi)) {
    found.push({ work_slug: m[1] ? WORKS[m[1].toUpperCase()] : work ?? '', ref: m[2] });
  }
  return candidates(found);
}

export async function retrievePassages(
  sb: RetrievalClient, question: string, work: string | null, language: string,
  select: () => Promise<unknown>,
): Promise<Passage[]> {
  const explicit = explicitCandidates(question, work);
  const refs = explicit.length ? explicit : candidates(await select()).filter((c) => !work || c.work_slug === work);
  if (!refs.length) return [];
  const { data: works, error: we } = await sb.from('works').select('id,slug')
    .in('slug', [...new Set(refs.map((c) => c.work_slug))]).eq('status', 'published').limit(2);
  if (we) throw we;
  const passages: Passage[] = [];
  for (const w of works ?? []) {
    // Unique btree (work_id, ref), no text transforms, OR ranks or wildcard scans.
    const { data: verses, error: ve } = await sb.from('verses').select('id,ref')
      .eq('work_id', w.id).in('ref', refs.filter((c) => c.work_slug === w.slug).map((c) => c.ref))
      .eq('status', 'published').limit(MAX_CANDIDATES);
    if (ve) throw ve;
    if (!verses?.length) continue;
    const { data: editions, error: ee } = await sb.from('v_editions')
      .select('id,title,language_code,kind,script_code,attribution_text').eq('work_id', w.id).order('sort_order').limit(32);
    if (ee) throw ee;
    const eligible = (editions ?? []).filter((e: Record<string, string>) =>
      (e.kind === 'translation' && e.language_code === language) || (e.kind === 'transliteration' && e.script_code === 'Latn')).slice(0, 4);
    if (!eligible.length) continue;
    // Unique btree (verse_id, edition_id); at most 8 verses x 4 editions.
    const { data: contents, error: ce } = await sb.from('verse_contents').select('verse_id,edition_id,body')
      .in('verse_id', verses.map((v: { id: string }) => v.id)).in('edition_id', eligible.map((e: { id: string }) => e.id))
      .eq('status', 'published').limit(MAX_CANDIDATES * 4);
    if (ce) throw ce;
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
