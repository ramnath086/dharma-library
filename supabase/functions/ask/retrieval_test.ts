import { assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { candidates, explicitCandidates, retrievePassages } from './retrieval.ts';

Deno.test('candidate validation is bounded and work-aware', () => {
  assertEquals(explicitCandidates('Compare BG 2.47 and SB 1.1.2', 'bhagavata-purana'), [
    { work_slug: 'bhagavad-gita', ref: '2.47' }, { work_slug: 'bhagavata-purana', ref: '1.1.2' },
  ]);
  assertEquals(candidates([{ work_slug: 'bhagavad-gita', ref: '1.1.2' }, { work_slug: 'other', ref: '2.47' },
    { work_slug: 'bhagavad-gita', ref: '2.47),id.gt.0' }]), []);
  assertEquals(candidates(Array.from({ length: 100 }, (_, i) => ({ work_slug: 'bhagavad-gita', ref: `2.${i + 1}` }))).length, 8);
});

function client(fail = false) {
  const calls: { table: string; filters: Record<string, unknown>; limit?: number }[] = [];
  const db = { from(table: string) {
    const call = { table, filters: {} as Record<string, unknown>, limit: 0 };
    calls.push(call);
    const chain = {
      select(_s: string) { return chain; },
      eq(k: string, v: unknown) { call.filters[k] = v; return chain; },
      in(k: string, v: unknown) { call.filters[k] = v; return chain; },
      order(_s: string) { return chain; },
      limit(n: number) {
        call.limit = n;
        const work = call.filters.work_id === 'bg' ? 'bg' : 'sb';
        const rows: Record<string, unknown[]> = {
          works: [{ id: 'sb', slug: 'bhagavata-purana' }, { id: 'bg', slug: 'bhagavad-gita' }]
            .filter((w) => ((call.filters.slug as string[] | undefined) ?? []).includes(w.slug)),
          verses: [{ id: work + '-v', ref: work === 'bg' ? '2.47' : '1.1.2' }],
          v_editions: [{ id: work + '-e', title: 'Published', language_code: 'en', kind: 'translation', attribution_text: 'source' }],
          verse_contents: [{ verse_id: (call.filters.verse_id as string[] | undefined)?.[0],
            edition_id: (call.filters.edition_id as string[] | undefined)?.[0], body: 'Database text only' }],
        };
        return Promise.resolve({ data: rows[table], error: fail ? new Error('statement timeout') : null });
      },
    };
    return chain;
  } };
  return { db, calls };
}

Deno.test('explicit cross-work refs bypass selector and hydrate only exact indexed IDs', async () => {
  const { db, calls } = client();
  const ps = await retrievePassages(db, 'Compare SB 1.1.2 with BG 2.47', 'bhagavata-purana', 'en',
    () => { throw new Error('must not select or scan'); });
  assertEquals(ps.map((p) => [p.work_slug, p.ref, p.body]), [
    ['bhagavata-purana', '1.1.2', 'Database text only'], ['bhagavad-gita', '2.47', 'Database text only'],
  ]);
  for (const c of calls) {
    if (c.table === 'verses') {
      assertEquals(c.limit, 8);
      assertEquals(c.filters.ref, c.filters.work_id === 'bg' ? ['2.47'] : ['1.1.2']);
    }
    if (c.table === 'verse_contents') {
      assertEquals(c.limit, 32);
      assertEquals((c.filters.verse_id as string[]).length, 1);
      assertEquals((c.filters.edition_id as string[]).length, 1);
    }
  }
});

Deno.test('invalid or off-work selector results issue no database queries', async () => {
  const { db, calls } = client();
  assertEquals(await retrievePassages(db, 'What is duty?', 'bhagavata-purana', 'en',
    () => Promise.resolve([{ work_slug: 'bhagavad-gita', ref: '2.47' }])), []);
  assertEquals(calls, []);
});

Deno.test('database failure does not retry with corpus search or vector RPC', async () => {
  const { db, calls } = client(true);
  await assertRejects(() => retrievePassages(db, 'BG 2.47', null, 'en', () => Promise.resolve([])), Error, 'statement timeout');
  assertEquals(calls.length, 1);
});
