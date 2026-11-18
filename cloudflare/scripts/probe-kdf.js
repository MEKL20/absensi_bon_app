import { Miniflare } from "miniflare";
const mf = new Miniflare({
  modules: true,
  compatibilityDate: "2026-08-06",
  script:
    'export default {async fetch(){try {const k=await crypto.subtle.importKey("raw",new Uint8Array([1]),"PBKDF2",false,["deriveBits"]);await crypto.subtle.deriveBits({name:"PBKDF2",hash:"SHA-256",salt:new Uint8Array([2]),iterations:600000},k,256);return new Response("600k supported");}catch(e){return new Response(e.name+": "+e.message)}}}',
});
try {
  console.log(await (await mf.dispatchFetch("https://x/")).text());
} finally {
  await mf.dispose();
}
