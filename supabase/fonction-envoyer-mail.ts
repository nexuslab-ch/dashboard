// NexusLab, fonction Edge « envoyer-mail » : envoie un mail via Resend depuis le dashboard.
// À déployer AVEC vérification JWT (seuls les membres connectés peuvent envoyer).
// Secrets à définir dans Supabase (Edge Functions > Secrets) :
//   RESEND_API_KEY   la clé API Resend (obligatoire)
//   MAIL_FROM        adresse d'envoi, par défaut contact@nexus-lab.ch (domaine vérifié chez Resend)
//   MAIL_REPLY_TO    adresse qui reçoit les réponses, par défaut nexuslab.mpa@gmail.com

const BASE = Deno.env.get("SUPABASE_URL")!;
const SECRETS = (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); } catch { return {}; } })();
const CLE: string = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || SECRETS.default || Object.values(SECRETS)[0] as string;
const SERVEUR: Record<string, string> = CLE.startsWith("eyJ") ? { apikey: CLE, Authorization: `Bearer ${CLE}` } : { apikey: CLE };
const PUBLIQUE = Deno.env.get("SUPABASE_ANON_KEY") || (() => { try { const p = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}"); return p.default || Object.values(p)[0]; } catch { return ""; } })() as string;
const RESEND = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM = Deno.env.get("MAIL_FROM") || "contact@nexus-lab.ch";
const REPLY_TO = Deno.env.get("MAIL_REPLY_TO") || "nexuslab.mpa@gmail.com";
const BUCKET = "documents";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const emailOk = (e: string) => /^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/.test(e);

async function rest(chemin: string, init: RequestInit = {}) {
  const r = await fetch(`${BASE}/rest/v1/${chemin}`, { ...init, headers: { ...SERVEUR, "Content-Type": "application/json", Prefer: "return=representation", ...(init.headers || {}) } });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return await r.json();
}
const echapHtml = (t: string) => t.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
function enHtml(texte: string) {
  const paras = echapHtml(texte).split(/\n{2,}/).map((p) => `<p style="margin:0 0 14px">${p.replace(/\n/g, "<br>")}</p>`).join("");
  return `<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;color:#1D1D1F">${paras}</div>`;
}
function base64(octets: Uint8Array) {
  let s = ""; const pas = 0x8000;
  for (let i = 0; i < octets.length; i += pas) s += String.fromCharCode(...octets.subarray(i, i + pas));
  return btoa(s);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erreur: "Méthode non autorisée." }, 405);
  try {
    if (!RESEND) return json({ erreur: "L’envoi de mails n’est pas encore configuré (clé Resend manquante dans Supabase)." }, 503);
    // 1. Qui envoie ? (jeton de la personne connectée)
    const auth = req.headers.get("Authorization") || "";
    const u = await fetch(`${BASE}/auth/v1/user`, { headers: { Authorization: auth, apikey: PUBLIQUE || CLE } });
    if (!u.ok) return json({ erreur: "Session expirée : reconnecte-toi au dashboard." }, 401);
    const email = String((await u.json()).email || "").toLowerCase();
    const auj = new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Zurich" }).format(new Date());
    const [m] = await rest(`membres?select=id,nom,actif,acces_jusquau&email=ilike.${encodeURIComponent(email)}&limit=1`);
    if (!m || !m.actif || (m.acces_jusquau && m.acces_jusquau < auj)) return json({ erreur: "Ton compte n’a pas le droit d’envoyer des mails." }, 403);

    // 2. Contenu
    const b = await req.json();
    const a = String(b.destinataire || "").trim(), cc = String(b.copie || "").trim();
    const sujet = String(b.sujet || "").trim(), corps = String(b.corps || "").trim();
    if (!emailOk(a)) return json({ erreur: "L’adresse du destinataire n’est pas valide." }, 400);
    if (cc && !cc.split(/[,;]\s*/).every(emailOk)) return json({ erreur: "Une adresse en copie n’est pas valide." }, 400);
    if (!sujet || !corps) return json({ erreur: "Il manque l’objet ou le message." }, 400);
    if (corps.length > 20000) return json({ erreur: "Le message est trop long." }, 400);

    // 3. Pièce jointe : le PDF d'un devis ou d'une facture du dashboard
    let pieces: { filename: string; content: string }[] = [], nomPj: string | null = null;
    if (b.devis_id) {
      const [d] = await rest(`devis_factures?select=id,numero,pdf_path&id=eq.${encodeURIComponent(b.devis_id)}&limit=1`);
      if (!d?.pdf_path) return json({ erreur: "Ce devis n’a pas encore de PDF. Ouvre-le et clique sur PDF une fois, puis réessaie." }, 400);
      const f = await fetch(`${BASE}/storage/v1/object/${BUCKET}/${d.pdf_path.split("/").map(encodeURIComponent).join("/")}`, { headers: SERVEUR });
      if (!f.ok) return json({ erreur: "Le PDF du devis est introuvable dans les documents." }, 400);
      nomPj = `${d.numero}.pdf`;
      pieces = [{ filename: nomPj, content: base64(new Uint8Array(await f.arrayBuffer())) }];
    }

    // 4. Envoi
    const prenom = String(m.nom || "").split(" ")[0];
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: `${prenom ? prenom + ", " : ""}NexusLab <${FROM}>`,
        to: [a], ...(cc ? { cc: cc.split(/[,;]\s*/) } : {}), reply_to: REPLY_TO,
        subject: sujet, text: corps, html: enHtml(corps), ...(pieces.length ? { attachments: pieces } : {}),
      }),
    });
    const rep = await r.json().catch(() => ({}));
    const ligne = { client_id: b.client_id || null, membre_id: m.id, destinataire: a, copie: cc || null, sujet, corps, devis_id: b.devis_id || null, piece_jointe: nomPj, modele: b.modele || null };
    if (!r.ok) {
      await rest("mails_envoyes", { method: "POST", body: JSON.stringify({ ...ligne, statut: "erreur", erreur: String(rep.message || r.status) }) }).catch(() => {});
      return json({ erreur: `Resend a refusé l’envoi : ${rep.message || r.status}` }, 502);
    }
    const [enr] = await rest("mails_envoyes", { method: "POST", body: JSON.stringify({ ...ligne, fournisseur_id: rep.id || null }) });

    // 5. Trace dans le suivi du client
    if (b.client_id) {
      await rest("contacts_clients", { method: "POST", body: JSON.stringify({ client_id: b.client_id, membre_id: m.id, date: auj, canal: "email", resultat: "autre", notes: `Mail envoyé : ${sujet}${nomPj ? " (PJ " + nomPj + ")" : ""}` }) }).catch(() => {});
      if (b.devis_id) await rest(`devis_factures?id=eq.${encodeURIComponent(b.devis_id)}&statut=eq.brouillon`, { method: "PATCH", body: JSON.stringify({ statut: "envoye" }) }).catch(() => {});
    }
    return json({ ok: true, id: enr?.id });
  } catch (e) {
    return json({ erreur: "Erreur inattendue : " + (e as Error).message }, 500);
  }
});
