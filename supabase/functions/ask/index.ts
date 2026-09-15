// Dharma Library — `ask` Edge Function (Deno)
// -----------------------------------------------------------------------------
// Grounded Q&A with mandatory verse citations.
//
// Flow
//   1. Retrieve candidate verses with `retrieve_for_qa` (lexical + entity
//      match; pgvector similarity is merged in when embeddings exist).
//   2. Build a prompt containing ONLY those verses (ref + text + attribution).
//   3. Ask the model to answer strictly from the passages and to cite refs in
//      the form [SB 1.1.2]. If the passages don't support an answer it must
//      say so. Temperature 0.2.
//   4. Post-validate: extract cited refs, drop any that were not in the
//      retrieved set (hallucination guard), mark `grounded=false` and return
//      an honest "no reliable answer" if no valid citation remains.
//   5. Log to qa_sessions / qa_messages when a user JWT is present.
//
// Secrets (set with `supabase secrets set`): OPENAI_API_KEY. Optional:
// AI_MODEL, EMBEDDING_MODEL, OPENAI_BASE_URL (any OpenAI-compatible endpoint).
// Never fabricates scripture: the model sees real verse text only, and the
// output is constrained to cite it.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { ground } from "./grounding.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENAI_BASE_URL = Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1";
const MODEL = Deno.env.get("AI_MODEL") ?? "gpt-4o-mini";
const EMBEDDING_MODEL = Deno.env.get("EMBEDDING_MODEL") ?? "text-embedding-3-small";

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
    const { question, language = "en", work_slug = "bhagavata-purana", session_id } = await req.json();
    if (!question || typeof question !== "string" || question.trim().length < 3) {
      return json({ error: "question required" }, 400);
    }
    if (!OPENAI_API_KEY) return json({ error: "AI provider not configured (OPENAI_API_KEY missing)" }, 503);

    // Client bound to the caller's JWT so RLS applies (anon or user).
    const authHeader = req.headers.get("Authorization") ?? `Bearer ${SUPABASE_ANON_KEY}`;
    const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } });

    // 1. retrieval (lexical + entity)
    const { data: lexical, error: rerr } = await sb.rpc("retrieve_for_qa", {
      p_query: question, p_work_slug: work_slug, p_language: language, p_limit: 8,
    });
    if (rerr) throw rerr;
    let passages: Passage[] = lexical ?? [];

    // 1b. vector retrieval (if embeddings exist) — merged by verse
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
    const allowedRefs = new Set(passages.map((p) => p.ref));

    if (passages.length === 0) {
      return json({ answer: "", citations: [], grounded: false, model: MODEL });
    }

    // 2. prompt
    const context = passages.map((p, i) =>
      `[${i + 1}] SB ${p.ref} (${p.edition_title}, ${p.language_code})\n${p.body}`).join("\n\n");
    const system = `You are a careful scholar assisting readers of the Śrīmad Bhāgavata Purāṇa.
Answer ONLY from the passages provided. Do not use outside knowledge about the text's contents, and never invent or paraphrase verses that are not in the passages.
Cite every claim with the verse reference in square brackets exactly like [SB 1.1.2]. Only cite references that appear in the passages.
If the passages do not contain enough information, say so plainly in one or two sentences and do not guess.
Write in ${LANG_NAME[language] ?? language}. Be concise (under 200 words). Keep Sanskrit terms in IAST.`;
    const user = `Passages:\n\n${context}\n\nQuestion: ${question}`;

    // 3. completion
    const res = await fetch(`${OPENAI_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: JSON.stringify({ model: MODEL, temperature: 0.2, max_tokens: 500, messages: [{ role: "system", content: system }, { role: "user", content: user }] }),
    });
    if (!res.ok) throw new Error(`AI provider error ${res.status}: ${await res.text()}`);
    const data = await res.json();
    const text: string = data.choices?.[0]?.message?.content ?? "";
    const usage = data.usage ?? {};

    // 4. validate citations (hallucination guard)
    const g = ground(text, allowedRefs);
    const grounded = g.grounded;
    const citations = g.valid.map((ref) => {
      const p = passages.find((x) => x.ref === ref)!;
      return { verse_id: p.verse_id, ref, work_slug: p.work_slug, edition_id: p.edition_id, quote: p.body.slice(0, 200) };
    });
    const answer = g.answer;

    // 5. log (only when signed in — RLS requires ownership)
    let sid = session_id ?? null;
    try {
      const { data: userRes } = await sb.auth.getUser();
      if (userRes?.user) {
        if (!sid) {
          const { data: s } = await sb.from("qa_sessions").insert({ user_id: userRes.user.id, language, title: question.slice(0, 80) }).select("id").single();
          sid = s?.id ?? null;
        }
        if (sid) {
          await sb.from("qa_messages").insert([
            { session_id: sid, role: "user", content: question },
            { session_id: sid, role: "assistant", content: answer, citations, model: MODEL, prompt_tokens: usage.prompt_tokens, output_tokens: usage.completion_tokens, grounded },
          ]);
        }
      }
    } catch (_) { /* logging is best-effort */ }

    return json({ answer, citations, grounded, model: MODEL, session_id: sid });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});

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
