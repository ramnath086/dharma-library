import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { extractCitations, ground, type AllowedCitations } from "./grounding.ts";

/** Retrieved verses: work short code → refs actually retrieved. */
function allowed(...entries: [string, string[]][]): AllowedCitations {
  return new Map(entries.map(([code, refs]) => [code, new Set(refs)]));
}

Deno.test("keeps valid citations and strips hallucinated ones", () => {
  const r = ground("Bhakti is the goal [SB 1.1.2]. Also see [SB 9.9.9].", allowed(["SB", ["1.1.2", "1.1.10"]]));
  assertEquals(r.grounded, true);
  assertEquals(r.valid, [{ code: "SB", ref: "1.1.2" }]);
  assertEquals(r.answer.includes("9.9.9"), false);
});

Deno.test("no valid citation => not grounded, empty answer", () => {
  const r = ground("Certainly! The answer is 42 [SB 7.7.7].", allowed(["SB", ["1.1.1"]]));
  assertEquals(r.grounded, false);
  assertEquals(r.answer, "");
});

Deno.test("accepts two-part Gītā refs such as [BG 2.47]", () => {
  const r = ground("Act without attachment [BG 2.47].", allowed(["BG", ["2.47", "2.48"]]));
  assertEquals(r.grounded, true);
  assertEquals(r.valid, [{ code: "BG", ref: "2.47" }]);
  assertEquals(r.answer, "Act without attachment [BG 2.47].");
});

Deno.test("a ref alone is never enough — the work must match too", () => {
  // 2.47 exists in the retrieved Bhāgavata set, but the model labelled it BG.
  const r = ground("See [BG 2.47] and [SB 2.47].", allowed(["SB", ["2.47"]]));
  assertEquals(r.valid, [{ code: "SB", ref: "2.47" }]);
  assertEquals(r.answer.includes("BG 2.47"), false);
  assertEquals(r.answer.includes("SB 2.47"), true);
});

Deno.test("a Gītā citation cannot validate against a Bhāgavata passage, or vice versa", () => {
  const sbOnly = ground("As said in [BG 1.1.2].", allowed(["SB", ["1.1.2"]]));
  assertEquals(sbOnly.grounded, false);
  assertEquals(sbOnly.answer, "");

  const bgOnly = ground("As said in [SB 2.47].", allowed(["BG", ["2.47"]]));
  assertEquals(bgOnly.grounded, false);
  assertEquals(bgOnly.answer, "");
});

Deno.test("keeps mixed SB and BG citations in order, without duplicates", () => {
  const r = ground(
    "Duty [BG 2.47] and devotion [SB 1.1.2], again [BG 2.47].",
    allowed(["SB", ["1.1.2"]], ["BG", ["2.47"]]),
  );
  assertEquals(r.valid, [{ code: "BG", ref: "2.47" }, { code: "SB", ref: "1.1.2" }]);
  assertEquals(r.grounded, true);
  assertEquals(r.answer, "Duty [BG 2.47] and devotion [SB 1.1.2], again [BG 2.47].");
});

Deno.test("extractCitations returns work code + ref pairs", () => {
  assertEquals(extractCitations("a [SB 1.1.2] b [BG 2.47] c"), [
    { code: "SB", ref: "1.1.2" },
    { code: "BG", ref: "2.47" },
  ]);
});

Deno.test("matches the work code case-insensitively and ignores unknown works", () => {
  const r = ground("lowercase [bg 2.47] and unknown [XX 1.1.1].", allowed(["BG", ["2.47"]]));
  assertEquals(r.valid, [{ code: "BG", ref: "2.47" }]);
  assertEquals(r.answer.includes("XX 1.1.1"), false);
});

Deno.test("ignores brackets that are not citations", () => {
  assertEquals(extractCitations("[1] a passage, [note], [SB], [SB x.y]"), []);
});
