// Dharma Library — `ask` Edge Function (Deno) — "Ask Dharma" foundation
// -----------------------------------------------------------------------------
// Grounded Q&A with mandatory verse citations.
//
// Flow
//   1. Validate + clamp the question; resolve the caller (JWT optional).
//   2. Daily cap: signed-in users may receive up to ASK_DAILY_CAP grounded
//      answers per UTC day (counted via qa_answers_today(), RLS-scoped).
//      Anonymous callers are not per-user capped — they have no stored counter;
//      provider spend is governed by the project budget instead.
//   3. Retrieve candidate verses with `retrieve_for_qa` (lexical + entity
//      match; pgvector similarity is merged in when embeddings exist).
//   4. Conversation continuity: when the caller passes a session_id they own,
//      the last few exchanges are replayed as chat turns so follow-up
//      questions resolve correctly (pure logic in context.ts).
//   5. Build a prompt containing ONLY those verses (work short code + ref +
//      text + attribution). The prompt is work-aware: it names the work(s)
//      actually retrieved and asks for citations in the form [SB 1.1.2] /
//      [BG 2.47], using that work's own short code. If the passages don't
//      support an answer the model must say so. Temperature 0.2.
//   6. Post-validate: extract cited (work, ref) pairs, drop any that were not
//      in the retrieved set (hallucination guard; a [BG …] citation can never
//      be satisfied by an SB passage), mark `grounded=false` and return an
//      honest "no reliable answer" if no valid citation remains.
//   7. Log to qa_sessions / qa_messages when a user JWT is present, and return
//      session_id + the assistant message_id (the app needs it for feedback).
//
// Secrets (set with `supabase secrets set`): OPENAI_API_KEY. Optional:
// AI_MODEL, EMBEDDING_MODEL, ASK_DAILY_CAP (default 30, 0 disables),
// OPENAI_BASE_URL (any OpenAI-compatible endpoint).
// Never fabricates scripture: the model sees real verse text only, and the
// output is constrained to cite it.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { ground, type AllowedCitations } from "./grounding.ts";
import { capReached, clampQuestion, prepareHistory } from "./context.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENAI_BASE_URL = Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1";
const MODEL = Deno.env.get("AI_MODEL") ?? "gpt-4o-mini";
const EMBEDDING_MODEL = Deno.env.get("EMBEDDING_MODEL") ?? "text-embedding-3-small";
const DAILY_CAP = Math.max(0, parseInt(Deno.env.get("ASK_DAILY_CAP") ?? "30", 10) || 30);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Passage = {
  verse_id: string; ref: string; work_slug: string; edition_id: string; edition_title: string;
  language_code: string; body: string; attribution_text: string; rank: number;
};

const LANG_NAME: Record<string, string> = { en: "English", ml: "Malayalam", hi: "Hindi", sa: "Sanskrit" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json();
    const { language = "en", work_slug = "bhagavata-purana", session_id } = body ?? {};
    const question = clampQuestion(body?.question);
    if (question.length < 3) {
      return json({ error: "question required (3–1000 chars after trimming)" }, 400);
    }
    if (!OPENAI_API_KEY) return json({ error: "AI provider not configured (OPENAI_API_KEY missing)" }, 503);

    // Client bound to the caller's JWT so RLS applies (anon or user).
    const authHeader = req.headers.get("Authorization") ?? `Bearer ${SUPABASE_ANON_KEY}`;
    const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } });

    // 1. resolve the caller once — used for the cap, history, and logging
    let user: { id: string } | null = null;
    try {
      const { data } = await sb.auth.getUser();
      user = data?.user ?? null;
    } catch (_) { /* anonymous */ }

    // 2. daily cap (signed-in users only; see file header)
    let usedToday = 0;
    if (user && DAILY_CAP > 0) {
      try {
        const { data } = await sb.rpc("qa_answers_today");
        usedToday = typeof data === "number" ? data : 0;
      } catch (_) { /* cap is best-effort if the RPC is unavailable */ }
      if (capReached(usedToday, DAILY_CAP, true)) {
        return json({ error: "daily answer cap reached", daily_cap: DAILY_CAP }, 429);
      }
    }

    // 3. retrieval (lexical + entity)
    const { data: lexical, error: rerr } = await sb.rpc("retrieve_for_qa", {
      p_query: question, p_work_slug: work_slug, p_language: language, p_limit: 8,
    });
    if (rerr) throw rerr;
    let passages: Passage[] = lexical ?? [];

    // 3b. vector retrieval (if embeddings exist) — merged by verse
    try {
      const emb = await embed(question);
      if (emb) {
        const { data: vec } = await sb.rpc("match_verse_contents", { p_embedding: emb, p_language: language, p_work_slug: work_slug, p_limit: 8 });
        for (const v of vec ?? []) {
          if (!passages.some((p) => p.verse_id === v.verse_id && p.edition_id === v.edition_id)) passages.push(v);
        }
      }
    } catch (_) { /* embeddings optional */ }

    // Prefer translations in the user's language, then base text; cap ~12 passages
    passages = dedupe(passages).slice(0, 12);

    if (passages.length === 0) {
      return json({ answer: "", citations: [], grounded: false, model: MODEL, session_id: session_id ?? null });
    }

    // 3c. work short codes: citations are validated and labelled per work, so
    // [BG 2.47] and [SB 2.47] never collapse into one another. The works table
    // is public-readable; if the lookup fails we fall back to the slug.
    const shortCodes = await resolveWorks(sb, passages.map((p) => p.work_slug));
    const allowed: AllowedCitations = new Map();
    for (const p of passages) {
      const code = shortCodeFor(p.work_slug, shortCodes);
      if (!allowed.has(code)) allowed.set(code, new Set());
      allowed.get(code)!.add(p.ref);
    }

    // 4. conversation continuity (only for a session the caller actually owns — RLS enforces it)
    let history: ReturnType<typeof prepareHistory> = [];
    if (user && session_id) {
      try {
        const { data: rows } = await sb
          .from("qa_messages").select("role, content")
          .eq("session_id", session_id)
          .order("created_at", { ascending: false }).limit(6);
        history = prepareHistory(rows ?? []);
      } catch (_) { /* continuity is best-effort */ }
    }

    // 5. prompt (work-aware: names the works retrieved and uses their codes)
    const context = passages.map((p, i) =>
      `[${i + 1}] ${shortCodeFor(p.work_slug, shortCodes)} ${p.ref} (${p.edition_title}, ${p.language_code})\n${p.body}`).join("\n\n");
    const workList = [...new Set(passages.map((p) => workName(p, shortCodes)))].join(", ");
    const example = `[${shortCodeFor(passages[0].work_slug, shortCodes)} ${passages[0].ref}]`;
    const system = `You are a careful scholar assisting readers of the Dharma Library scriptures (${workList}).
Answer ONLY from the passages provided. Do not use outside knowledge about the text's contents, and never invent or paraphrase verses that are not in the passages.
Cite every claim with the verse reference in square brackets, using the work's short code exactly as written in the passages — for example ${example}. Only cite references that appear in the passages, and never label a verse with another work's short code.
If the passages do not contain enough information, say so plainly in one or two sentences and do not guess.
Earlier chat turns are context for the question only — every claim in your answer must still be supported by the passages below.
Write in ${LANG_NAME[language] ?? language}. Be concise (under 200 words). Keep Sanskrit terms in IAST.`;
    const userMsg = `Passages:\n\n${context}\n\nQuestion: ${question}`;

    // 6. completion
    const res = await fetch(`${OPENAI_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: JSON.stringify({
        model: MODEL, temperature: 0.2, max_tokens: 500,
        messages: [{ role: "system", content: system }, ...history, { role: "user", content: userMsg }],
      }),
    });
    if (!res.ok) throw new Error(`AI provider error ${res.status}: ${await res.text()}`);
    const data = await res.json();
    const text: string = data.choices?.[0]?.message?.content ?? "";
    const usage = data.usage ?? {};

    // 7. validate citations (hallucination guard, per work)
    const g = ground(text, allowed);
    const citations = g.valid.flatMap((c) => {
      // `allowed` was built from `passages`, so a valid (work, ref) always resolves
      const p = passages.find((x) => x.ref === c.ref && shortCodeFor(x.work_slug, shortCodes) === c.code);
      if (!p) return [];
      // `label` is what the client renders in the citation chip: "SB 1.1.2" / "BG 2.47"
      return [{
        verse_id: p.verse_id, ref: c.ref, label: `${c.code} ${c.ref}`, short_code: c.code,
        work_slug: p.work_slug, edition_id: p.edition_id, quote: p.body.slice(0, 200),
      }];
    });
    const grounded = citations.length > 0;
    const answer = g.answer;

    // 8. log (only when signed in — RLS requires ownership); message_id powers feedback
    let sid = session_id ?? null;
    let messageId: string | null = null;
    try {
      if (user) {
        if (!sid) {
          const { data: s } = await sb.from("qa_sessions").insert({ user_id: user.id, language, title: question.slice(0, 80) }).select("id").single();
          sid = s?.id ?? null;
        }
        if (sid) {
          const { data: inserted } = await sb.from("qa_messages").insert([
            { session_id: sid, role: "user", content: question },
            { session_id: sid, role: "assistant", content: answer, citations, model: MODEL, prompt_tokens: usage.prompt_tokens, output_tokens: usage.completion_tokens, grounded },
          ]).select("id, role");
          // Do NOT rely on PostgREST ordering of an insert-returning: pick the
          // assistant row explicitly or feedback would attach to the question.
          messageId = inserted?.find((r) => r.role === "assistant")?.id ?? null;
        }
      }
    } catch (_) { /* logging is best-effort */ }

    return json({ answer, citations, grounded, model: MODEL, session_id: sid, message_id: messageId });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});

type AskClient = ReturnType<typeof createClient>;

/** slug → work display title, for the prompt header. */
type WorkInfo = { slug: string; short_code?: string; title_iast?: string };

/**
 * Look up the display info of the works behind the retrieved passages, so
 * citations can be validated and labelled per work (SB vs BG). The `works`
 * table is publicly readable; a failure here is non-fatal — `shortCodeFor`
 * falls back to the slug-derived code instead.
 */
async function resolveWorks(sb: AskClient, slugs: string[]): Promise<Map<string, WorkInfo>> {
  const out = new Map<string, WorkInfo>();
  const unique = [...new Set(slugs)].filter(Boolean);
  if (unique.length === 0) return out;
  try {
    const { data } = await sb.from("works").select("slug, short_code, title_iast").in("slug", unique);
    for (const w of (data ?? []) as WorkInfo[]) {
      if (w?.slug && w?.short_code) out.set(w.slug, { ...w, short_code: String(w.short_code).toUpperCase() });
    }
  } catch (_) { /* fall back to the slug-derived code below */ }
  return out;
}

/** The citation code for a work: its stored short code, else a slug fallback. */
function shortCodeFor(slug: string, info: Map<string, WorkInfo>): string {
  const stored = info.get(slug)?.short_code;
  if (stored) return stored;
  return String(slug ?? "").replace(/[^A-Za-z0-9]/g, "").slice(0, 6).toUpperCase() || "WORK";
}

/** Human-readable work name for the prompt header; falls back to the code. */
function workName(p: Passage, info: Map<string, WorkInfo>): string {
  const title = info.get(p.work_slug)?.title_iast;
  return title ? `${title} (${shortCodeFor(p.work_slug, info)})` : shortCodeFor(p.work_slug, info);
}

function dedupe(ps: Passage[]): Passage[] {
  const seen = new Set<string>();
  const out: Passage[] = [];
  for (const p of ps) {
    const k = `${p.verse_id}:${p.edition_id}`;
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(p);
  }
  return out;
}

async function embed(text: string): Promise<number[] | null> {
  const res = await fetch(`${OPENAI_BASE_URL}/embeddings`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${OPENAI_API_KEY}` },
    body: JSON.stringify({ model: EMBEDDING_MODEL, input: text }),
  });
  if (!res.ok) return null;
  const d = await res.json();
  return d.data?.[0]?.embedding ?? null;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
