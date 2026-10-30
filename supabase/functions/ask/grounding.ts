// Pure helpers for citation validation — unit-tested with `deno test`.

export const CITATION_RE = /\[SB\s+(\d+\.\d+\.\d+)\]/g;

export function extractRefs(text: string): string[] {
  return [...text.matchAll(CITATION_RE)].map((m) => m[1]);
}

/** Keep only citations whose ref was actually retrieved; strip the rest. */
export function ground(text: string, allowed: Set<string>): { answer: string; valid: string[]; grounded: boolean } {
  const valid = [...new Set(extractRefs(text).filter((r) => allowed.has(r)))];
  const grounded = valid.length > 0;
  const cleaned = text.replace(CITATION_RE, (m, r) => (allowed.has(r) ? m : "")).replace(/[ \t]{2,}/g, " ").trim();
  return { answer: grounded ? cleaned : "", valid, grounded };
}
