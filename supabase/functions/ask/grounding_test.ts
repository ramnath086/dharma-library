import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ground } from "./grounding.ts";

Deno.test("keeps valid citations and strips hallucinated ones", () => {
  const r = ground("Bhakti is the goal [SB 1.1.2]. Also see [SB 9.9.9].", new Set(["1.1.2", "1.1.10"]));
  assertEquals(r.grounded, true);
  assertEquals(r.valid, ["1.1.2"]);
  assertEquals(r.answer.includes("9.9.9"), false);
});

Deno.test("no valid citation => not grounded, empty answer", () => {
  const r = ground("Certainly! The answer is 42 [SB 7.7.7].", new Set(["1.1.1"]));
  assertEquals(r.grounded, false);
  assertEquals(r.answer, "");
});
