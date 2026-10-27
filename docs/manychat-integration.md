# ManyChat → NutriFlow

Active integration configured on 2026-10-27. The CRM reads `leads.acquisition_type` and `lead_interest`; manual lead metadata overrides remain available.

## ManyChat automations

- `NutriFlow | Sincronizar contactos`: New Contact Created → webhook, `kind: mc_unknown`.
- `NutriFlow | Conversaciones`: Instagram Default Reply, every time, including story replies → webhook, `kind: mc_dm`. Its inherited New Contact trigger stays OFF.
- `NutriFlow | Protocolo por mensaje`: incoming message contains `protocolo` → webhook, `kind: mc_keyword`. Its inherited New Contact trigger stays OFF.
- Existing `PROTOCOLO | Recurso + cualificación + seguimiento`: `Obtener el enlace` button → Actions (existing tag/open-conversation actions plus webhook, `mc_keyword`) → original `Enviar mensaje #10` resource delivery. The initial private reply and resource messages are preserved.

The three synchronization automations contain no outgoing messages. The existing Protocolo resource delivery continues its previous messages.

## Authentication and data

`manychat-leads` authenticates a dedicated 256-bit key in `x-nutriflow-key`. Its source stores only the SHA-256 hash. JWT verification is disabled because the function implements this webhook authentication itself. The service-role credential stays in Supabase runtime environment variables and is never sent to ManyChat or the browser. Owner and ManyChat account scope are fixed on the server.

Each request contains contact ID, name, Instagram username, classification, and `dry_run: false`. No conversation body, phone number, email, or health information is sent by these automations.

`manychat-review` independently validates the caller's user JWT with Supabase Auth before listing or resolving that user's pending matches. Its CORS origin is the GitHub Pages origin. Review SQL operations are service-role-only and check ownership.

## Identity and deduplication

- Per-user transaction lock and unique `(user_id, account_id, contact_id)` identity make repeated deliveries idempotent.
- Existing stable Instagram handles, including the legacy ManyChat import notes, link to the existing lead.
- Ambiguous handles, display names, and canonical name/handle similarities are held for explicit review; they do not create or merge a lead automatically.
- Canonical names ignore common Spanish accents, spaces, and punctuation only for review candidates, never automatic merging.
- Once a mapped lead has been deleted, delivery does not silently recreate it.
- Existing names, notes, dates, and sales statuses are preserved. First known acquisition is retained; unknown acquisition can be upgraded.
- Identity cannot be inferred with certainty when all identifying information differs. Pending review is the conservative fallback for detectable possible matches.

## Scope and limitations

This is prospective event-driven capture, not a bulk import of the entire contact list. Default Reply does not run when another keyword/automation handles a message. New contacts are still covered by the New Contact event. Existing contacts in unrelated keyword automations may require integration in those flows. ManyChat pauses, disconnected Instagram permissions, and platform restrictions can prevent delivery.

Commenters become ManyChat opted-in contacts after interacting with the opening message's button; Protocolo classification happens at `Obtener el enlace`. A comment alone is not treated as a confirmed opted-in CRM identity. Manually sent outbound messages are not counted or scored by this integration.

## Verification

- ManyChat external-request test: HTTP 200, dry-run classification and real pending-review write verified in Supabase.
- Live New Contact event produced a linked lead without manual entry.
- Rollback-only database tests: repeated identity, imported handle, ambiguous name, explicit resolution, closed-status preservation, canonical manual name candidates, and restricted RPC permissions.
- Frontend: classification/manual override and review selection/request behavior verified with synthetic records. Cloud owner login was tested with mocked success and rejection after removing the legacy embedded password.
- Database schema snapshot is `supabase/schema/manychat.sql`; deployed changes are tracked by Supabase migration history. Do not rerun the snapshot over the existing installation.

Operational note: removing an embedded credential from current source does not remove it from Git history. The account owner should rotate that previously exposed password through their normal account recovery/password process.
