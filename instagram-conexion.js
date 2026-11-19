const endpoint='https://nrxltxmbpkplhgycodob.supabase.co/functions/v1/ig-crm-sync',el=id=>document.getElementById(id);
const digest=new URLSearchParams(location.hash.slice(1)).get('equipo')||'';
if(digest)history.replaceState({},'',location.pathname);
const good=/^[0-9a-f]{64}$/.test(digest);
let current=null, offset=0;
const say=s=>el('notice').textContent=s;
function token(){try{const user=JSON.parse(localStorage.getItem('nf_session')||'null'),cached=user&&JSON.parse(localStorage.getItem('_nf_sb_tok_'+user.email)||'null');return cached?.exp>Date.now()?cached.tok:null;}catch{return null;}}
async function api(op,args={}){
 const t=token();if(!t)throw Error('login');
 const r=await fetch(endpoint,{method:'POST',headers:{Authorization:'Bearer '+t,'Content-Type':'application/json'},redirect:'error',body:JSON.stringify({op,...args})});
 const j=await r.json();if(!r.ok)throw Error(j.error||'server');return j;
}
function err(e){say(e.message==='login'||e.message==='owner_required'?'Abre tu CRM e inicia sesión con la cuenta de Jan en este navegador. Después vuelve y pulsa Actualizar estado.':e.message==='stale'?'Hay mensajes nuevos. Vuelve a abrir la conversación para confirmarlos.':'No se pudo completar la operación. Actualiza el estado para reintentarlo.');}
async function status(){
 try{const s=await api('status');el('state').textContent=s.connected?'Instagram autorizó el acceso a mensajes. '+(s.error?'La última lectura requiere revisión ('+s.error+').':s.sync_at?'Última lectura: '+new Date(s.sync_at).toLocaleString('es-ES')+'.':'Esperando la primera lectura.'):'Pendiente: aún no hay un permiso vigente para leer mensajes.';el('auth').textContent=s.connected?'Renovar permiso':'Conectar Instagram';
 el('worker').textContent=s.paired?'Ordenador vinculado. '+(s.worker_seen?'Última conexión del agente: '+new Date(s.worker_seen).toLocaleString('es-ES')+'.':'Esperando al agente de Windows.'):'No hay un ordenador vinculado para clasificar con Ollama.';
 el('unlink').hidden=!s.paired;el('pairPanel').hidden=!good;el('code').textContent=digest.slice(0,8).toUpperCase();el('inbox').hidden=!s.connected;if(s.connected)await list(false);say('');}
 catch(e){el('state').textContent='Para ver el estado privado, abre sesión en tu CRM.';err(e);}
}
async function list(append){if(!append){offset=0;el('list').replaceChildren();}const {threads}=await api('list',{offset});if(!offset&&!threads.length)el('list').textContent='Todavía no hay conversaciones nuevas.';for(const t of threads){
 const a=document.createElement('article'),label=document.createElement('strong'),desc=document.createElement('p'),btn=document.createElement('button');
 label.textContent=t.handle?'@'+t.handle:'Conversación de Instagram';desc.textContent=t.incoming_count+' mensajes recibidos · '+t.outgoing_count+' enviados · '+new Date(t.latest_at).toLocaleString('es-ES');btn.textContent='Ver mis mensajes';btn.className='soft';btn.onclick=()=>openThread(t.thread_id).catch(err);a.append(label,desc,btn);el('list').append(a);
 }offset+=threads.length;el('more').hidden=threads.length<30;}
async function openThread(tid){const s=await api('thread',{tid});current={tid,rev:s.rev};el('threadName').textContent=s.handle?'@'+s.handle:'Conversación';el('msgs').replaceChildren();for(const m of s.rows){const l=document.createElement('label');if(m.role==='jan'){const c=document.createElement('input');c.type='checkbox';c.value=m.id;c.checked=m.manual;c.disabled=m.manual;l.append(c);}const span=document.createElement('span');span.className='line';span.textContent=(m.role==='jan'?' Tú: ':' Atleta: ')+(m.text||'(archivo sin texto)');l.append(span);el('msgs').append(l);}el('review').hidden=false;el('review').scrollIntoView();say('');}
el('pair').onclick=async()=>{try{if(!good||!confirm('¿Coincide '+digest.slice(0,8).toUpperCase()+' con tu ventana del agente? Este ordenador podrá leer los mensajes nuevos para clasificarlos. Se reemplazará el vínculo anterior.'))return;await api('pair',{digest});await status();el('pairPanel').hidden=true;say('Equipo vinculado. El agente se conectará automáticamente.');}catch(e){err(e);}};
el('unlink').onclick=async()=>{try{if(!confirm('¿Desvincular el agente de este CRM?'))return;await api('unpair');await status();}catch(e){err(e);}};
el('refresh').onclick=status;el('more').onclick=()=>list(true).catch(err);el('cancel').onclick=()=>{el('review').hidden=true;el('msgs').replaceChildren();current=null;};
el('confirm').onclick=async()=>{if(!current)return;const ids=[...el('msgs').querySelectorAll('input:checked:not(:disabled)')].map(e=>e.value);if(!ids.length){say('Selecciona al menos un mensaje tuyo.');return;}try{const a=await api('confirm',{...current,ids});el('cancel').click();await status();say(({created:'Lead añadido como Instagram · En conversación.',existing:'Este lead ya estaba registrado.',matched_existing:'Vinculado al lead existente.',waiting:'Mensajes confirmados. Todavía no se han completado los cinco turnos.',review_required:'Hay posibles duplicados. No se ha creado otro lead.',profile_required:'Falta el usuario de Instagram para identificar el lead.',deleted_lead_not_recreated:'Este contacto ya había sido eliminado. No se ha creado de nuevo.'})[a.action]||'Confirmación guardada.');}catch(e){err(e);}};
status();
