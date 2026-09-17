import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { capReached, clampQuestion, MAX_QUESTION_LEN, prepareHistory } from "./context.ts";

Deno.test("clampQuestion normalises whitespace and enforces the limit", () => {
  assertEquals(clampQuestion("  who\n\tspoke   first?  "), "who spoke first?");
  assertEquals(clampQuestion(""), "");
  assertEquals(clampQuestion(null), "");
  assertEquals(clampQuestion(undefined), "");
  assertEquals(clampQuestion("x".repeat(MAX_QUESTION_LEN + 50)).length, MAX_QUESTION_LEN);
});

Deno.test("prepareHistory: newest-first rows become oldest-first turns", () => {
  const rows = [
    { role: "assistant", content: "a2" },
    { role: "user", content: "q2" },
    { role: "assistant", content: "a1" },
    { role: "user", content: "q1" },
  ];
  assertEquals(
    prepareHistory(rows),
    [
      { role: "user", content: "q1" },
      { role: "assistant", content: "a1" },
      { role: "user", content: "q2" },
      { role: "assistant", content: "a2" },
    ],
  );
});

Deno.test("prepareHistory: keeps at most maxTurns, clamps long content, drops junk", () => {
  // Input is newest-first (as fetched: order desc + limit). m0 is the newest turn.
  const rows = Array.from({ length: 12 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `m${i} ${"x".repeat(2000)}` }));
  rows.push({ role: "system", content: "ignored" }, { role: "user", content: "   " });
  const turns = prepareHistory(rows, 6, 100);
  assertEquals(turns.length, 6);
  assertEquals(turns.every((t) => t.content.length <= 100), true);
  assertEquals(turns.every((t) => t.role === "user" || t.role === "assistant"), true);
  // the six newest turns survive, replayed oldest-first
  assertEquals(turns[0].content.startsWith("m5"), true);
  assertEquals(turns[5].content.startsWith("m0"), true);
});

Deno.test("capReached: only signed-in users at/over the cap are stopped", () => {
  assertEquals(capReached(0, 30, true), false);
  assertEquals(capReached(29, 30, true), false);
  assertEquals(capReached(30, 30, true), true);
  assertEquals(capReached(31, 30, true), true);
  assertEquals(capReached(999, 30, false), false); // anonymous: not per-user capped
  assertEquals(capReached(999, 0, true), false); // cap disabled
});
