// NexusLab, fonction Edge « recevoir-mail » : webhook Resend « email.received ».
// Un client écrit (ou répond) à contact@nexus-lab.ch : Resend reçoit le mail grâce au MX du domaine
// et appelle cette fonction. Elle :
//   1. vérifie la signature du webhook (secret whsec_... de Resend),
//   2. récupère le mail complet chez Resend,
//   3. le range dans la table mails_recus (et dans le suivi du client s'il est connu),
//   4. le transfère vers la boîte commune (nexuslab.mpa@gmail.com par défaut).
// À déployer SANS vérification JWT (c'est Resend qui appelle, pas un membre connecté).
// Secrets Supabase (Edge Functions > Secrets) :
//   RESEND_RECEIVE_KEY      clé Resend en « Full access » (lire les mails reçus et transférer). À défaut, RESEND_API_KEY.
//   RESEND_WEBHOOK_SECRET   le « Signing secret » du webhook Resend (whsec_...), obligatoire
//   MAIL_FORWARD_TO         facultatif, adresse(s) de transfert séparées par des virgules

const BASE = Deno.env.get("SUPABASE_URL")!;
const SECRETS = (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); } catch { return {}; } })();
const CLE: string = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || SECRETS.default || Object.values(SECRETS)[0] as string;
const SERVEUR: Record<string, string> = CLE.startsWith("eyJ") ? { apikey: CLE, Authorization: `Bearer ${CLE}` } : { apikey: CLE };
const RESEND = Deno.env.get("RESEND_RECEIVE_KEY") || Deno.env.get("RESEND_API_KEY") || "";
const WEBHOOK = Deno.env.get("RESEND_WEBHOOK_SECRET") ?? "";
const FROM = Deno.env.get("MAIL_FROM") || "contact@nexus-lab.ch";
const VERS = (Deno.env.get("MAIL_FORWARD_TO") || "nexuslab.mpa@gmail.com").split(/[,;\s]+/).filter(Boolean);
const LIMITE_PJ = 10 * 1048576;

const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });
const echapHtml = (t: string) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

async function rest(chemin: string, init: RequestInit = {}) {
  const r = await fetch(`${BASE}/rest/v1/${chemin}`, { ...init, headers: { ...SERVEUR, "Content-Type": "application/json", Prefer: "return=representation", ...(init.headers || {}) } });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return await r.json();
}
async function resend(chemin: string, init: RequestInit = {}) {
  const r = await fetch(`https://api.resend.com${chemin}`, { ...init, headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json", ...(init.headers || {}) } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Resend ${r.status} ${j?.message || ""}`);
  return j;
}
function base64(octets: Uint8Array) {
  let s = ""; const pas = 0x8000;
  for (let i = 0; i < octets.length; i += pas) s += String.fromCharCode(...octets.subarray(i, i + pas));
  return btoa(s);
}
function depuisBase64(t: string) {
  const s = atob(t); const o = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) o[i] = s.charCodeAt(i);
  return o;
}
// Signature Svix (utilisée par Resend) : HMAC-SHA256 de « id.timestamp.corps », clé = secret après « whsec_ », en base64
async function signatureValide(req: Request, corps: string) {
  const id = req.headers.get("svix-id") || "", ts = req.headers.get("svix-timestamp") || "", sig = req.headers.get("svix-signature") || "";
  if (!id || !ts || !sig || !WEBHOOK) return false;
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;
  const cle = await crypto.subtle.importKey("raw", depuisBase64(WEBHOOK.replace(/^whsec_/, "")), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const attendu = base64(new Uint8Array(await crypto.subtle.sign("HMAC", cle, new TextEncoder().encode(`${id}.${ts}.${corps}`))));
  return sig.split(" ").some((p) => p.split(",")[1] === attendu);
}
// « Marc Rey <marc@rey.ch> » -> { email, nom }
function adresse(v: unknown) {
  const s = String(Array.isArray(v) ? v[0] : v || "").trim();
  const m = s.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/);
  return m ? { email: m[2].trim().toLowerCase(), nom: m[1].trim() || null } : { email: s.toLowerCase(), nom: null };
}
const listeTexte = (v: unknown) => (Array.isArray(v) ? v : v ? [v] : []).map((x) => String(x)).join(", ");

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erreur: "Méthode non autorisée." }, 405);
  const corps = await req.text();
  if (!(await signatureValide(req, corps))) return json({ erreur: "Signature invalide." }, 401);
  try {
    const ev = JSON.parse(corps);
    if (ev?.type !== "email.received") return json({ ok: true, ignore: ev?.type || "inconnu" });
    const emailId = String(ev.data?.email_id || "");
    if (!emailId) return json({ erreur: "email_id manquant." }, 400);

    // Déjà traité ? (Resend réessaie avec le même mail en cas d'échec)
    const deja = await rest(`mails_recus?select=id,transfere&resend_id=eq.${encodeURIComponent(emailId)}&limit=1`);
    if (deja[0]?.transfere) return json({ ok: true, doublon: true });

    // 1. Le mail complet
    const m = await resend(`/emails/receiving/${encodeURIComponent(emailId)}`);
    const exp = adresse(m.from || ev.data.from);
    const sujet = String(m.subject || ev.data.subject || "(sans objet)");
    const texte = String(m.text || "").slice(0, 100000) || String(m.html || "").replace(/<style[\s\S]*?<\/style>/gi, "").replace(/<[^>]+>/g, " ").replace(/\s+\n/g, "\n").slice(0, 100000);
    const pjs: { id?: string; filename?: string; content_type?: string; size?: number }[] = Array.isArray(m.attachments) ? m.attachments : [];

    // 2. Client connu ? (même adresse e-mail que la fiche)
    const [c] = await rest(`clients?select=id,nom&email=ilike.${encodeURIComponent(exp.email)}&limit=1`).catch(() => []);

    // 3. Rangement dans le dashboard
    let ligne = deja[0];
    if (!ligne) {
      [ligne] = await rest("mails_recus", { method: "POST", body: JSON.stringify({
        resend_id: emailId, client_id: c?.id || null, expediteur: exp.email, expediteur_nom: exp.nom,
        destinataires: listeTexte(m.to || ev.data.to), sujet, texte,
        pieces: pjs.map((p) => ({ nom: p.filename, type: p.content_type, taille: p.size })),
        recu_le: m.created_at || ev.data.created_at || new Date().toISOString(),
      }) });
      if (c?.id) {
        const auj = new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Zurich" }).format(new Date());
        await rest("contacts_clients", { method: "POST", body: JSON.stringify({ client_id: c.id, date: auj, canal: "email", resultat: "autre", notes: `Mail reçu : ${sujet}` }) }).catch(() => {});
      }
    }

    // 4. Transfert vers la boîte commune (sauf boucle : un mail venant de notre propre domaine)
    if (exp.email.endsWith("@nexus-lab.ch") || VERS.includes(exp.email)) return json({ ok: true, id: ligne?.id, transfert: "ignoré" });
    const pieces: { filename: string; content: string }[] = [];
    let poids = 0; const manquantes: string[] = [];
    for (const p of pjs) {
      try {
        const a = await resend(`/emails/receiving/${encodeURIComponent(emailId)}/attachments/${encodeURIComponent(String(p.id))}`);
        const url = a.download_url || a.data?.download_url;
        const f = url ? await fetch(url) : null;
        const o = f && f.ok ? new Uint8Array(await f.arrayBuffer()) : null;
        if (!o || poids + o.length > LIMITE_PJ) { manquantes.push(String(p.filename)); continue; }
        poids += o.length; pieces.push({ filename: String(p.filename || "piece-jointe"), content: base64(o) });
      } catch { manquantes.push(String(p.filename)); }
    }
    const entete = `Reçu sur ${listeTexte(m.to || ev.data.to)} de ${exp.nom ? exp.nom + " " : ""}<${exp.email}>${c ? ` (client : ${c.nom})` : ""}.${manquantes.length ? ` Pièces jointes à voir dans le dashboard : ${manquantes.join(", ")}.` : ""} Pour répondre au client, réponds depuis le dashboard ou directement à ce mail.`;
    const html = `<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;color:#6E6E73;border-left:3px solid #FF5F57;padding:6px 10px;margin:0 0 16px">${echapHtml(entete)}</div>${m.html || `<pre style="white-space:pre-wrap;font-family:inherit">${echapHtml(texte)}</pre>`}`;
    await resend("/emails", { method: "POST", body: JSON.stringify({
      from: `${exp.nom || exp.email} via NexusLab <${FROM}>`, to: VERS, reply_to: exp.email,
      subject: sujet, html, text: `${entete}\n\n${texte}`, ...(pieces.length ? { attachments: pieces } : {}),
    }) });
    if (ligne?.id) await rest(`mails_recus?id=eq.${ligne.id}`, { method: "PATCH", body: JSON.stringify({ transfere: true }) }).catch(() => {});
    return json({ ok: true, id: ligne?.id });
  } catch (e) {
    // 500 : Resend réessaiera plus tard
    return json({ erreur: (e as Error).message }, 500);
  }
});
