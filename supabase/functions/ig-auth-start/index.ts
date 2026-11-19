import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const IG_APP_ID = Deno.env.get("META_APP_ID") ?? "";
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/ig-auth-callback`;
const SCOPES = Deno.env.get("META_SCOPES") ?? "instagram_business_basic,instagram_business_manage_insights";

function setupPage() {
  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Growth Engine · configuración</title></head>` +
    `<body style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#0B0B0D;color:#F3F3F6;margin:0;min-height:100vh;display:grid;place-items:center;padding:24px">` +
    `<div style="max-width:520px;background:#141417;border:1px solid #26262C;border-radius:18px;padding:26px">` +
    `<div style="font-size:40px">🔌</div>` +
    `<h2 style="margin:6px 0 4px">Casi listo — falta 1 paso</h2>` +
    `<p style="color:#9A9AA4;margin:0 0 16px">La app y el servidor funcionan. Para conectar tu Instagram necesitas crear tu <b>app de Meta</b> y pegar 2 secretos. Es cosa de una vez.</p>` +
    `<ol style="color:#C9C9D2;line-height:1.6;padding-left:18px">` +
    `<li>En <b>developers.facebook.com</b> crea una app y añade <b>Instagram → API setup with Instagram login</b>.</li>` +
    `<li>Registra esta <b>URL de redirección</b>:<br><code style="display:block;background:#0B0B0D;border:1px solid #26262C;border-radius:8px;padding:8px;margin:6px 0;font-size:12px;word-break:break-all">${REDIRECT_URI}</code></li>` +
    `<li>En <b>Supabase → Edge Functions → Secrets</b> añade <code>META_APP_ID</code> y <code>META_APP_SECRET</code>.</li>` +
    `<li>Vuelve a Growth Engine y pulsa <b>Conectar Instagram</b>.</li>` +
    `</ol>` +
    `<p style="color:#6C6C76;font-size:13px;margin-top:14px">¿Dudas? Llévale a Claude la guía GROWTH-ENGINE-SETUP.md y te ayuda pantalla por pantalla.</p>` +
    `</div></body></html>`;
  return new Response(html, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

Deno.serve(async (req) => {
  if(req.method !== "GET") return new Response("Método no permitido",{status:405});
  const dm = new URL(req.url).searchParams.get("mensajes") === "1";
  if (!IG_APP_ID) return setupPage();
  const supa = createClient(SUPABASE_URL, SERVICE_ROLE);
  const state = (dm ? "igdm." : "") + crypto.randomUUID();
  const {error} = await supa.from("ge_oauth_state").insert({ state });
  if(error) return new Response("No se pudo iniciar la conexión. Vuelve a abrir el enlace.",{status:503});
  const url = new URL("https://www.instagram.com/oauth/authorize");
  url.searchParams.set("client_id", IG_APP_ID);
  url.searchParams.set("redirect_uri", REDIRECT_URI);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", dm ? "instagram_business_basic,instagram_business_manage_messages" : SCOPES);
  if(dm) url.searchParams.set("force_authentication","1");
  url.searchParams.set("state", state);
  return new Response(null,{status:302,headers:{Location:url.toString(),"Cache-Control":"no-store","Referrer-Policy":"no-referrer"}});
});
