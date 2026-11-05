// This endpoint accepts normalized events from a trusted server-side adapter.
// It is NOT a Meta webhook: the adapter must verify Meta's signature and prove
// native/manual provenance before setting manual=true. No adapter is connected yet.
const OWNER = 'f209b91f-607b-4b14-9305-6a7d567b90b5';
const ACCOUNT = '17841449201493232';
const response = (data, status = 200) => new Response(JSON.stringify(data), {
  status, headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
});
async function hash(value) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
}
export function createHandler(env, fetcher = fetch) {
  return async req => {
    if (req.method !== 'POST') return response({error:'method_not_allowed'},405);
    const expected = env('INSTAGRAM_CONVERSATION_KEY');
    if (!expected || expected.length < 64) return response({error:'event_source_not_connected'},503);
    const supplied = req.headers.get('x-nutriflow-conversation-key') || '';
    if (supplied.length !== expected.length) return response({error:'unauthorized'},401);
    const a = await hash(expected), b = await hash(supplied);
    let diff = 0; for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    if (diff) return response({error:'unauthorized'},401);
    if (Number(req.headers.get('content-length') || 0) > 8192) return response({error:'payload_too_large'},413);
    try {
      const raw = await req.text();
      if (new TextEncoder().encode(raw).length > 8192) return response({error:'payload_too_large'},413);
      const event = JSON.parse(raw);
      if (event.account_id !== ACCOUNT || !/^\d{1,40}$/.test(event.contact_id || '') ||
          typeof event.message_id !== 'string' || !event.message_id || event.message_id.length > 300 ||
          !['in','out'].includes(event.direction) || typeof event.sent_at !== 'string' ||
          !Number.isFinite(Date.parse(event.sent_at)) ||
          typeof event.username !== 'string' || !/^[A-Za-z0-9_.]{0,64}$/.test(event.username)) {
        return response({error:'invalid_event'},400);
      }
      if (event.direction === 'out' && event.manual !== true) return response({action:'ignored_non_manual'});
      // Whitelist metadata; never forward message text, attachments or caller owner IDs.
      const result = await fetcher(env('SUPABASE_URL') + '/rest/v1/rpc/nf_record_instagram_turn', {
        method:'POST', headers:{apikey:env('SUPABASE_SERVICE_ROLE_KEY'),
          Authorization:'Bearer ' + env('SUPABASE_SERVICE_ROLE_KEY'),'Content-Type':'application/json'},
        body:JSON.stringify({p_user:OWNER,p_account:ACCOUNT,p_contact:event.contact_id,
          p_message:event.message_id,p_sent_at:event.sent_at,p_direction:event.direction,
          p_manual:event.manual === true,p_username:event.username}),
      });
      if (!result.ok) return response({error:'ingestion_failed'},502);
      return response(await result.json());
    } catch { return response({error:'invalid_request'},400); }
  };
}
