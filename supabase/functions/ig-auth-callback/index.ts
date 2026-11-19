import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

import {grantRow,includesMessages} from "./grant.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const IG_APP_ID = Deno.env.get("META_APP_ID") ?? "";
const IG_APP_SECRET = Deno.env.get("META_APP_SECRET") ?? "";
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/ig-auth-callback`;

// Supabase forces text/plain + CSP sandbox on function responses, so we return a
// clean, friendly plain-text message (no HTML tags on screen). The Growth Engine
// app auto-detects the connection by polling, so this window is just a courtesy.
function page(text: string): Response {
  const h = new Headers();
  h.set("cache-control","no-store");
  h.set("referrer-policy","no-referrer");
  h.set("content-type", "text/plain; charset=utf-8");
  return new Response(text, { status: 200, headers: h });
}
const okPage = () => page("✅  Instagram conectado\n\nYa puedes cerrar esta ventana y volver a Growth Engine.\nTus estadísticas reales se están cargando solas.");
const failPage = (msg: string) => page("⚠️  No se pudo conectar\n\nCierra esta ventana y vuelve a intentarlo desde Growth Engine.\n\nDetalle: " + msg);

Deno.serve(async (req) => {
  const u = new URL(req.url);
  const code = u.searchParams.get("code");
  const state = u.searchParams.get("state");
  const err = u.searchParams.get("error_description") || u.searchParams.get("error");
  if (err) return failPage("Instagram no concedió la autorización.");
  if (!code || !state) return failPage("Falta el codigo de autorizacion.");
  if (!IG_APP_ID || !IG_APP_SECRET) return failPage("Faltan META_APP_ID / META_APP_SECRET.");

  const supa = createClient(SUPABASE_URL, SERVICE_ROLE);
  const dm = state.startsWith("igdm.");
  const { data: st } = await supa.from("ge_oauth_state").delete().eq("state",state)
    .gte("created_at",new Date(Date.now()-15*60_000).toISOString()).select("state").maybeSingle();
  if (!st) return failPage("Autorización caducada o ya utilizada. Abre el enlace de conexión otra vez.");
  function issue(stage:string,http=0,code?:number){
    console.warn(JSON.stringify({event:"ig_dm_authorization",stage,http,meta_code:typeof code==="number"?code:undefined}));
    const text:Record<string,string>={intercambio:"Instagram no ha podido canjear esta autorización.",permiso:"No se ha concedido el permiso de mensajes.",duracion:"Meta no ha emitido un permiso de larga duración.",perfil:"Meta no ha devuelto el perfil autorizado.",cuenta:"La cuenta elegida no corresponde a @jansadurnii.",conversaciones:"Meta no permite leer la lista de conversaciones de @jansadurnii.",guardar:"El CRM no ha podido guardar el permiso.",red:"No se pudo completar la petición a Instagram."};
    return page("Conexión de mensajes pendiente. "+text[stage]+" Referencia: "+stage+".");
  }
  try {
    const form = new FormData();
    form.set("client_id", IG_APP_ID);
    form.set("client_secret", IG_APP_SECRET);
    form.set("grant_type", "authorization_code");
    form.set("redirect_uri", REDIRECT_URI);
    form.set("code", code);
    const tRes = await fetch("https://api.instagram.com/oauth/access_token", { method: "POST", body: form });
    const tJson = grantRow(await tRes.json());
    if (!tRes.ok || !tJson) return dm ? issue("intercambio",tRes.status) : failPage("Instagram no ha completado el intercambio del permiso.");
    if(dm && includesMessages(tJson.permissions)===false) return issue("permiso",tRes.status);
    const shortToken = tJson.access_token as string;
    const igUserId = String(tJson.user_id ?? "");
    const grantUrl=new URL("https://graph.instagram.com/access_token");grantUrl.search=new URLSearchParams({grant_type:"ig_exchange_token",client_secret:IG_APP_SECRET,access_token:shortToken}).toString();
    const llRes = await fetch(grantUrl,{redirect:"error",signal:AbortSignal.timeout(15000)});
    const llJson = await llRes.json();
    const longToken = (llJson.access_token as string) ?? shortToken;
    const expiresIn = Number(llJson.expires_in ?? 5184000);
    const fields=dm?"user_id,username":"user_id,username,account_type,followers_count,follows_count,media_count,profile_picture_url";
    if(dm && (!llRes.ok || !llJson.access_token || !Number.isFinite(Number(llJson.expires_in)) || Number(llJson.expires_in)<=0))return issue("duracion",llRes.status,llJson.error?.code);
    const pRes = await fetch("https://graph.instagram.com/me?fields="+fields,{headers:{Authorization:"Bearer "+longToken},redirect:"error",signal:AbortSignal.timeout(15000)});
    const p = await pRes.json();
    if(dm){
      if(!pRes.ok || !p.user_id)return issue("perfil",pRes.status,p.error?.code);
      if(String(p.user_id)!=="17841449201493232")return issue("cuenta");
      const ttl=Number(llJson.expires_in);
      if(!llRes.ok || !llJson.access_token || !Number.isFinite(ttl) || ttl<=0)
        return failPage("Instagram no ha emitido una autorización de larga duración.");
      // Read one thread identifier to verify the permission. Never fetch/open a message here.
      const proof=await fetch("https://graph.instagram.com/v27.0/17841449201493232/conversations?platform=instagram&fields=id&limit=1",{headers:{Authorization:"Bearer "+longToken},redirect:"error",signal:AbortSignal.timeout(10000)});
      const proofBody=await proof.json();
      if(!proof.ok || !Array.isArray(proofBody.data))return issue("conversaciones",proof.status,proofBody.error?.code);
      const {error}=await supa.from("nf_ig_dm_connection").upsert({account_id:"17841449201493232",access_token:longToken,expires_at:new Date(Date.now()+ttl*1000).toISOString(),connected_at:new Date().toISOString()},{onConflict:"account_id"});
      if(error)return issue("guardar");
      return page("Acceso a las conversaciones de @jansadurnii confirmado. Ya puedes cerrar esta ventana. No se ha enviado ningún mensaje.");
    }
    const { error: upErr } = await supa.from("ge_ig_accounts").upsert({
      ig_user_id: String(p.user_id ?? igUserId),
      username: p.username ?? null,
      account_type: p.account_type ?? null,
      followers_count: p.followers_count ?? null,
      follows_count: p.follows_count ?? null,
      media_count: p.media_count ?? null,
      profile_picture_url: p.profile_picture_url ?? null,
      access_token: longToken,
      token_expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    }, { onConflict: "ig_user_id" });
    if (upErr) throw new Error("No se pudo guardar la cuenta.");
    return okPage();
  } catch (e) {
    return dm?issue("red"):failPage("No se pudo completar la conexión con Instagram.");
  }
});
