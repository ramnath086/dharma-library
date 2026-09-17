// Pure helpers for Ask Dharma prompt assembly — unit-tested with `deno test`.

export type HistoryRow = { role: string; content: string };
export type Turn = { role: "user" | "assistant"; content: string };

export const MAX_QUESTION_LEN = 1000;
export const MAX_HISTORY_TURNS = 6; // last 3 user/assistant pairs
export const MAX_HISTORY_CHARS = 600; // per message, keeps prompts small

/** Trim, collapse whitespace, and hard-limit question length. Returns "" when empty. */
export function clampQuestion(q: unknown): string {
  if (typeof q !== "string") return "";
  return q.replace(/\s+/g, " ").trim().slice(0, MAX_QUESTION_LEN);
}

/**
 * Build prior conversation turns for the LLM from qa_messages rows.
 * Rows may come back newest-first (we fetch with order desc + limit); turns are
 * returned oldest-first, each clamped so a long answer cannot crowd out the
 * retrieved-verse context. Non user/assistant roles are dropped.
 */
export function prepareHistory(rows: HistoryRow[], maxTurns = MAX_HISTORY_TURNS, maxChars = MAX_HISTORY_CHARS): Turn[] {
  const asc = [...rows].reverse();
  const turns: Turn[] = [];
  for (const r of asc) {
    const c = (r.content ?? "").replace(/\s+/g, " ").trim();
    if (!c) continue;
    if (r.role !== "user" && r.role !== "assistant") continue;
    turns.push({ role: r.role, content: c.slice(0, maxChars) });
  }
  return turns.slice(-maxTurns);
}

/**
 * Decide the daily-cap outcome. `used` counts answers already delivered today.
 * Only applied to signed-in sessions (null userId => never capped here; anons
 * are governed by the project-wide provider budget, not by a stored counter).
 */
export function capReached(used: number, cap: number, signedIn: boolean): boolean {
  return signedIn && cap > 0 && used >= cap;
}
