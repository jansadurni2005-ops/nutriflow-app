// Install @electric-sql/pglite@0.5.15 outside the repo and pass its absolute module
// path in PGLITE_MODULE. This never connects to Supabase or reads real leads.
import fs from 'node:fs';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const {PGlite}=await import(pathToFileURL(process.env.PGLITE_MODULE).href);
const db=new PGlite();
try {
 await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
 insert into auth.users values('f209b91f-607b-4b14-9305-6a7d567b90b5');
 create table public.leads(id text,user_id uuid references auth.users(id),name text,source text,status text,note text,date date,acquisition_type text,lead_interest text,primary key(id,user_id));
 create table public.nf_manychat_links(user_id uuid,username text,state text,lead_id text);`);
 await db.exec(fs.readFileSync(root+'supabase/schema/lead-deletion.sql','utf8'));
 await db.exec('begin;');
 await db.exec(fs.readFileSync(root+'supabase/schema/instagram-conversation.sql','utf8'));
 const results=await db.exec(fs.readFileSync(root+'tests/instagram-turns.sql','utf8'));
 console.log(results.at(-1).rows);
 await db.exec('rollback;');
 const check=await db.query("select to_regclass('public.nf_instagram_turn_events') is null as removed");
 if(!check.rows[0].removed)throw Error('Schema rollback failed');
 console.log('Schema and fixtures rolled back.');
} finally {await db.close();}
