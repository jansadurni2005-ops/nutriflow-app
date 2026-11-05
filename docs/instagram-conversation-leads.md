# Manual Instagram conversations → NutriFlow leads

Status: prepared for review; NOT connected or active. Existing ManyChat capture is unchanged.

The deployed ManyChat integration records contact identities and incoming classifications,
not manually sent outbound messages. The existing Instagram OAuth source defaults to basic
profile and insights scopes. Neither provides proof of the requested manual conversation.

## Exact rule

Count chronological human turns: outbound → inbound → outbound → inbound → outbound.
Consecutive messages from the same sender form one turn. Ignore outbound automation messages
and messages with unknown provenance. Repeated event delivery does not count again. Recompute
by event timestamp so out-of-order delivery does not change the result. A partial sequence
does not create a lead. At completion, create `source=Instagram`, `status=Contacted`
(displayed as **En conversación**) and `acquisition_type=instagram`.

The server stores message IDs, sender direction and timestamps, not message bodies or media.
Identity matching uses known Instagram handles and existing mappings, never display names.
Ambiguous matches wait for review. Existing calls, sales and lost statuses are preserved.
Deleted leads are not recreated. Existing ManyChat acquisition is retained when matched.

## Required connection before deployment

1. Connect a supported, authorized source of native Instagram sent AND received message
   events for @jansadurnii. Verify permissions, webhook subscriptions and manual/automatic
   provenance using actual test messages. A Default Reply or a reply counter is insufficient.
2. Implement/verify that source's adapter. It must authenticate the provider, normalize
   stable account/contact/message IDs and timestamp, resolve the Instagram username, and
   attest `manual=true` only for confirmed manual outgoing messages. The adapter must not
   send message contents to the CRM. It must retry delivery on non-2xx responses.
3. Install `supabase/schema/instagram-conversation.sql` using the normal migration process.
   It adds independent metadata tables and a service-role-only ingestion RPC with RLS.
4. Set a dedicated random 256-bit `INSTAGRAM_CONVERSATION_KEY` in Supabase and the trusted
   adapter. Do not reuse the ManyChat key or expose either credential in frontend code.
5. Deploy `instagram-turns` with JWT verification off ONLY because its handler validates the
   dedicated key. Without that key it returns 503 and does not accept events. This endpoint
   is a trusted-adapter contract, NOT a direct Meta webhook.
6. Run one real five-turn exchange and verify exactly one lead in the CRM. Test an automatic
   reply, duplicate delivery, an already-existing lead, and a deleted lead before activation.

No Meta subscriptions, OAuth scopes, existing Edge Functions, production tables or frontend
are changed by this branch. Do not describe the feature as active until step 6 succeeds.

## Verification

`node --test tests/instagram-turns.test.mjs` checks authentication, missing configuration,
manual provenance, fixed account/owner scope, payload filtering and retryable database errors.
The SQL test file runs its schema and fixtures within a rollback-only transaction.
`tests/instagram-turns-local.mjs` runs those scenarios in isolated PGlite PostgreSQL
with a minimal CRM schema and the existing production deletion triggers. Set
`PGLITE_MODULE` to an external installation of `@electric-sql/pglite@0.5.15`.
Validation: six handler tests and nine SQL scenarios passed locally. No production
database change was applied; a rollback-only hosted validation request expired at
the confirmation step and was replaced by the isolated local database test.
