// Pure helpers for citation validation — unit-tested with `deno test`.
//
// Citations name the work by its short code, so the same verse number in two
// works is unambiguous: [SB 1.1.2] is Bhāgavata, [BG 2.47] is the Gītā.
// Validation is therefore on the *pair* (work, ref): a [BG …] citation can
// never be satisfied by a Bhāgavata passage that happens to carry the same
// ref, and vice versa.

/** [SB 1.1.2] / [BG 2.47] — a work short code plus a dotted verse ref. */
export const CITATION_RE = /\[([A-Za-z][A-Za-z0-9]{0,7})\s+(\d+(?:\.\d+)*)\]/g;

/** A citation as written by the model. `code` is upper-cased. */
export type Citation = { code: string; ref: string };

/** Every citation in the text, in order of appearance. */
export function extractCitations(text: string): Citation[] {
  return [...text.matchAll(CITATION_RE)].map((m) => ({ code: m[1].toUpperCase(), ref: m[2] }));
}

/** Just the verse refs, in order of appearance (duplicates kept). */
export function extractRefs(text: string): string[] {
  return extractCitations(text).map((c) => c.ref);
}

/** Retrieved verses, keyed by work short code → the refs actually retrieved. */
export type AllowedCitations = Map<string, Set<string>>;

/** True only when this exact (work, ref) pair was retrieved. */
export function isAllowed(c: Citation, allowed: AllowedCitations): boolean {
  return allowed.get(c.code)?.has(c.ref) ?? false;
}

/** Keep only citations whose (work, ref) pair was actually retrieved; strip the rest. */
export function ground(text: string, allowed: AllowedCitations): { answer: string; valid: Citation[]; grounded: boolean } {
  const valid: Citation[] = [];
  const seen = new Set<string>();
  for (const c of extractCitations(text)) {
    if (!isAllowed(c, allowed)) continue;
    const k = `${c.code} ${c.ref}`;
    if (seen.has(k)) continue;
    seen.add(k);
    valid.push(c);
  }
  const grounded = valid.length > 0;
  const cleaned = text
    .replace(CITATION_RE, (m, code: string, ref: string) =>
      isAllowed({ code: code.toUpperCase(), ref }, allowed) ? m : "")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
  return { answer: grounded ? cleaned : "", valid, grounded };
}
