// FOCUS OS · envío de avisos Web Push programados.
//
// - GET  ?action=vapid           → clave pública VAPID (la usa la app para suscribirse).
// - POST {action:"run"}          → lo llama pg_cron cada minuto con la cabecera x-focus-cron;
//                                  envía los avisos vencidos de focus_alerts y los marca como enviados.
// - POST {action:"test"} + JWT   → envía un aviso de prueba a los dispositivos del usuario autenticado.
//
// Las claves VAPID se generan aquí la primera vez y se guardan en focus_server_keys
// (tabla sin acceso para anon/authenticated), así nunca salen del servidor.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { generateVapidKeys, sendWebPush, type VapidKeys } from "./webpush.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const SUBJECT = "https://jansadurni2005-ops.github.io/nutriflow-app/focus/";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

let cachedKeys: VapidKeys | null = null;
async function vapidKeys(): Promise<VapidKeys> {
  if (cachedKeys) return cachedKeys;
  const { data } = await admin.from("focus_server_keys").select("value").eq("id", "vapid").maybeSingle();
  if (data?.value) return (cachedKeys = JSON.parse(data.value));
  const fresh = await generateVapidKeys();
  await admin.from("focus_server_keys").upsert({ id: "vapid", value: JSON.stringify(fresh) }, { onConflict: "id", ignoreDuplicates: true });
  const { data: again } = await admin.from("focus_server_keys").select("value").eq("id", "vapid").single();
  return (cachedKeys = JSON.parse(again!.value));
}

async function cronSecretOk(req: Request): Promise<boolean> {
  const got = req.headers.get("x-focus-cron");
  if (!got) return false;
  const { data } = await admin.from("focus_server_keys").select("value").eq("id", "cron_secret").maybeSingle();
  return !!data?.value && data.value === got;
}

type Sub = { id: string; user_id: string; endpoint: string; p256dh: string; auth: string };

async function deliver(userIds: string[], messagesByUser: Map<string, { title: string; body: string; tag: string }[]>) {
  const keys = await vapidKeys();
  const { data: subs } = await admin.from("focus_push_subs").select("id,user_id,endpoint,p256dh,auth").in("user_id", userIds);
  let sent = 0, failed = 0;
  const dead: string[] = [];
  for (const sub of (subs ?? []) as Sub[]) {
    for (const msg of messagesByUser.get(sub.user_id) ?? []) {
      try {
        const status = await sendWebPush(sub, msg, keys, SUBJECT);
        if (status === 404 || status === 410) { dead.push(sub.id); break; }
        if (status >= 200 && status < 300) {
          sent++;
          await admin.from("focus_push_subs").update({ last_ok_at: new Date().toISOString() }).eq("id", sub.id);
        } else {
          failed++;
          console.error("push status", status, new URL(sub.endpoint).host);
        }
      } catch (e) {
        failed++;
        console.error("push error", String(e));
      }
    }
  }
  if (dead.length) await admin.from("focus_push_subs").delete().in("id", dead);
  return { sent, failed, removed: dead.length, devices: subs?.length ?? 0 };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);

  try {
    if (req.method === "GET" && url.searchParams.get("action") === "vapid") {
      const keys = await vapidKeys();
      return json({ publicKey: keys.publicKey });
    }

    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};

    if (body.action === "run") {
      if (!(await cronSecretOk(req))) return json({ error: "forbidden" }, 403);
      const now = new Date();
      const { data: due } = await admin
        .from("focus_alerts")
        .select("id,user_id,title,body,tag,fire_at")
        .is("sent_at", null)
        .lte("fire_at", now.toISOString())
        .gte("fire_at", new Date(now.getTime() - 15 * 60_000).toISOString())
        .order("fire_at")
        .limit(200);
      if (!due?.length) return json({ due: 0 });
      // Marcar primero para no enviar dos veces si dos ejecuciones se solapan.
      await admin.from("focus_alerts").update({ sent_at: now.toISOString() }).in("id", due.map((a) => a.id));
      const byUser = new Map<string, { title: string; body: string; tag: string }[]>();
      for (const a of due) {
        const list = byUser.get(a.user_id) ?? [];
        list.push({ title: a.title, body: a.body ?? "", tag: a.tag ?? a.id });
        byUser.set(a.user_id, list);
      }
      const result = await deliver([...byUser.keys()], byUser);
      // Limpieza de avisos antiguos ya enviados.
      await admin.from("focus_alerts").delete().lt("fire_at", new Date(now.getTime() - 3 * 86_400_000).toISOString());
      return json({ due: due.length, ...result });
    }

    if (body.action === "test") {
      const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
      const { data: userData, error } = await admin.auth.getUser(token);
      if (error || !userData.user) return json({ error: "unauthorized" }, 401);
      const uid = userData.user.id;
      const result = await deliver([uid], new Map([[uid, [{
        title: "🔔 FOCUS OS",
        body: "Los avisos funcionan. Te llegarán aunque tengas el móvil bloqueado.",
        tag: "focus-test",
      }]]]));
      return json(result);
    }

    return json({ error: "unknown action" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});
