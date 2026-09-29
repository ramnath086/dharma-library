# Ask query timeout fix

The mandatory `retrieve_for_qa` call invokes `search_verses` (0006, read-only).
Its hits CTE evaluates `to_tsvector('simple', vc.folded)`, substring LIKE,
reference/entity OR predicates and ranking across verse_contents, then sorts
before LIMIT. There is no matching text-search index in the migrations. An RPC
statement-timeout error is thrown by Ask and becomes HTTP 500. This identifies
the fatal source-code path; a production EXPLAIN/trace was not available here.

Ask now bypasses both that RPC and the optional vector ranking query. Explicit
SB/BG references use exact work/ref lookups. General questions use the existing
server-side provider to propose at most eight candidate references, not text.
Only published database verses and eligible public editions become passages.
No candidate text/quote/answer is trusted, and the existing cross-work citation
grounding remains unchanged. Selection can miss passages; absent or invalid
candidates return the existing ungrounded empty response, never a broad scan.

Queries: works by slug; verses by (work_id, ref); v_editions by work_id;
verse_contents by (verse_id, edition_id). Existing unique/btree indexes cover
the verse and content predicates. All calls retain the caller JWT and RLS.
Limits bound hydration to eight references and four editions each. No schema,
timeout-setting, secret, UI, offline index, or corpus changes are required.

The optional embedding request is removed from Ask. OPENAI_API_KEY remains
server-only; its secret UI digest is expected, not evidence of a missing key.
verify_jwt=false is unchanged. No deployment is performed by this change.
Production timing and general-question retrieval quality must be checked after
an owner-authorized deployment; unit tests do not measure production SQL time.
