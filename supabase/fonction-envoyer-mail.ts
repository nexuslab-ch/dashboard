// NexusLab, fonction Edge « envoyer-mail » : envoie un mail via Resend depuis le dashboard.
// À déployer AVEC vérification JWT (seuls les membres connectés peuvent envoyer).
// Secrets à définir dans Supabase (Edge Functions > Secrets) :
//   RESEND_API_KEY   la clé API Resend (obligatoire)
//   MAIL_FROM        adresse d'envoi, par défaut contact@nexus-lab.ch (domaine vérifié chez Resend)
//   MAIL_REPLY_TO    adresse qui reçoit les réponses, par défaut la même que MAIL_FROM (contact@nexus-lab.ch)

const BASE = Deno.env.get("SUPABASE_URL")!;
const SECRETS = (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); } catch { return {}; } })();
const CLE: string = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || SECRETS.default || Object.values(SECRETS)[0] as string;
const SERVEUR: Record<string, string> = CLE.startsWith("eyJ") ? { apikey: CLE, Authorization: `Bearer ${CLE}` } : { apikey: CLE };
const PUBLIQUE = Deno.env.get("SUPABASE_ANON_KEY") || (() => { try { const p = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}"); return p.default || Object.values(p)[0]; } catch { return ""; } })() as string;
const RESEND = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM = Deno.env.get("MAIL_FROM") || "contact@nexus-lab.ch";
// Réponses : sur contact@ (reçues par Resend, rangées dans le dashboard et transférées au Gmail commun)
const REPLY_TO = Deno.env.get("MAIL_REPLY_TO") || FROM;
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
// Signature : modèle de Mehdi (logo « nexus », filet corail, nom, titre, téléphone, site)
const ACCROCHE = "Sites web et outils digitaux pour les PME de Suisse romande";
function infosSignature(m: Record<string, string | null>) {
  const nom = String(m.nom_complet || m.nom || "").trim();
  const titre = [String(m.titre || "").trim(), "NexusLab"].filter(Boolean).join(" · ");
  const tel = String(m.telephone || "").trim();
  return { nom, titre, tel };
}
function signatureTexte(m: Record<string, string | null>) {
  const { nom, titre, tel } = infosSignature(m);
  return ["●● nexus", nom, titre, [tel, "nexus-lab.ch"].filter(Boolean).join("  |  "), ACCROCHE, "HES-SO Valais"].filter(Boolean).join("\n");
}
function signatureHtml(m: Record<string, string | null>) {
  const { nom, titre, tel } = infosSignature(m);
  const police = "Manrope,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif";
  const lienTel = tel ? `<a href="tel:${echapHtml(tel.replace(/\s/g, ""))}" style="color:#3A3A3C;text-decoration:none">${echapHtml(tel)}</a>&nbsp;&nbsp;|&nbsp;&nbsp;` : "";
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0 0;border-collapse:collapse;font-family:${police}">
<tr><td style="padding:0 0 14px;line-height:1;white-space:nowrap"><span style="color:#1D1D1F;font-size:11px;vertical-align:middle">&#9679;</span><span style="color:#FF5F57;font-size:15px;vertical-align:middle">&#9679;</span><span style="padding-left:6px;color:#1D1D1F;font-size:24px;font-weight:800;letter-spacing:-0.6px;vertical-align:middle">nexus</span></td></tr>
<tr><td style="border-left:3px solid #FF5F57;padding:2px 0 2px 12px">
<div style="font-size:16px;line-height:1.3;color:#1D1D1F">${echapHtml(nom)}</div>
<div style="font-size:13px;line-height:1.4;color:#6E6E73;margin-top:2px">${echapHtml(titre)}</div>
<div style="font-size:13px;line-height:1.4;color:#3A3A3C;margin-top:10px">${lienTel}<a href="https://nexus-lab.ch" style="color:#C43A32;text-decoration:none">nexus-lab.ch</a></div>
<div style="font-size:12px;line-height:1.4;color:#6E6E73;margin-top:8px">${ACCROCHE}</div>
<div style="font-size:12px;line-height:1.4;color:#8E8E93;margin-top:2px">HES-SO Valais</div>
</td></tr></table>`;
}
function enHtml(texte: string, signature = "") {
  const paras = echapHtml(texte).split(/\n{2,}/).map((p) => `<p style="margin:0 0 14px">${p.replace(/\n/g, "<br>")}</p>`).join("");
  return `<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;color:#1D1D1F">${paras}${signature}</div>`;
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
    const [m] = await rest(`membres?select=*&email=ilike.${encodeURIComponent(email)}&limit=1`);
    if (!m || !m.actif || (m.acces_jusquau && m.acces_jusquau < auj)) return json({ erreur: "Ton compte n’a pas le droit d’envoyer des mails." }, 403);

    // 2. Contenu
    const b = await req.json();
    const liste = (x: unknown) => String(x || "").split(/[,;\s]+/).map((e) => e.trim()).filter(Boolean);
    const aListe = liste(b.destinataire), ccListe = liste(b.copie), cciListe = liste(b.cci);
    const a = aListe.join(", "), cc = ccListe.join(", ");
    const sujet = String(b.sujet || "").trim(), corps = String(b.corps || "").trim();
    if (!aListe.length || !aListe.every(emailOk)) return json({ erreur: "Une adresse du champ « À » n’est pas valide." }, 400);
    if (!ccListe.every(emailOk)) return json({ erreur: "Une adresse en copie n’est pas valide." }, 400);
    if (!cciListe.every(emailOk)) return json({ erreur: "Une adresse en copie cachée n’est pas valide." }, 400);
    if (aListe.length + ccListe.length + cciListe.length > 20) return json({ erreur: "20 destinataires au maximum par mail." }, 400);
    if (!sujet || !corps) return json({ erreur: "Il manque l’objet ou le message." }, 400);
    if (corps.length > 20000) return json({ erreur: "Le message est trop long." }, 400);

    // 3. Pièce jointe : le PDF d'un devis ou d'une facture du dashboard
    const pieces: { filename: string; content: string }[] = [], noms: string[] = [];
    let poids = 0;
    const lireFichier = async (chemin: string) => {
      const f = await fetch(`${BASE}/storage/v1/object/${BUCKET}/${chemin.split("/").map(encodeURIComponent).join("/")}`, { headers: SERVEUR });
      return f.ok ? new Uint8Array(await f.arrayBuffer()) : null;
    };
    if (b.devis_id) {
      const [d] = await rest(`devis_factures?select=id,numero,pdf_path&id=eq.${encodeURIComponent(b.devis_id)}&limit=1`);
      if (!d?.pdf_path) return json({ erreur: "Ce devis n’a pas encore de PDF. Ouvre-le et clique sur PDF une fois, puis réessaie." }, 400);
      const o = await lireFichier(d.pdf_path);
      if (!o) return json({ erreur: "Le PDF du devis est introuvable dans les documents." }, 400);
      poids += o.length; noms.push(`${d.numero}.pdf`);
      pieces.push({ filename: `${d.numero}.pdf`, content: base64(o) });
    }
    // Fichiers joints : déjà rangés dans le stockage « documents » par le dashboard
    for (const p of (Array.isArray(b.pieces) ? b.pieces : []).slice(0, 15)) {
      const chemin = String(p?.chemin || "");
      if (!chemin || chemin.includes("..") || chemin.startsWith("/")) return json({ erreur: "Pièce jointe invalide." }, 400);
      const o = await lireFichier(chemin);
      if (!o) return json({ erreur: `Fichier introuvable : ${p?.nom || chemin}` }, 400);
      poids += o.length;
      if (poids > 10 * 1048576) return json({ erreur: "Les pièces jointes dépassent 10 Mo : envoie plutôt un lien." }, 400);
      const nom = String(p?.nom || chemin.split("/").pop()).slice(0, 150);
      noms.push(nom); pieces.push({ filename: nom, content: base64(o) });
    }
    const nomPj = noms.length ? noms.join(", ") : null;

    // 4. Envoi
    const prenom = String(m.nom || "").split(" ")[0];
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: `${prenom ? prenom + ", " : ""}NexusLab <${FROM}>`,
        to: aListe, ...(ccListe.length ? { cc: ccListe } : {}), ...(cciListe.length ? { bcc: cciListe } : {}), reply_to: REPLY_TO,
        subject: sujet, text: `${corps}\n\n${signatureTexte(m)}`, html: enHtml(corps, signatureHtml(m)), ...(pieces.length ? { attachments: pieces } : {}),
      }),
    });
    const rep = await r.json().catch(() => ({}));
    const ligne = { client_id: b.client_id || null, membre_id: m.id, destinataire: a, copie: [cc, cciListe.length ? `Cci : ${cciListe.join(", ")}` : ""].filter(Boolean).join(" | ") || null, sujet, corps, devis_id: b.devis_id || null, piece_jointe: nomPj, modele: b.modele || null };
    if (!r.ok) {
      await rest("mails_envoyes", { method: "POST", body: JSON.stringify({ ...ligne, statut: "erreur", erreur: String(rep.message || r.status) }) }).catch(() => {});
      return json({ erreur: `Resend a refusé l’envoi : ${rep.message || r.status}` }, 502);
    }
    const [enr] = await rest("mails_envoyes", { method: "POST", body: JSON.stringify({ ...ligne, fournisseur_id: rep.id || null }) });

    // 5. Trace dans le suivi du client
    if (b.client_id) {
      await rest("contacts_clients", { method: "POST", body: JSON.stringify({ client_id: b.client_id, membre_id: m.id, date: auj, canal: "email", resultat: "autre", notes: `Mail envoyé : ${sujet}${nomPj ? " (PJ : " + nomPj + ")" : ""}` }) }).catch(() => {});
      if (b.devis_id) await rest(`devis_factures?id=eq.${encodeURIComponent(b.devis_id)}&statut=eq.brouillon`, { method: "PATCH", body: JSON.stringify({ statut: "envoye" }) }).catch(() => {});
    }
    return json({ ok: true, id: enr?.id });
  } catch (e) {
    return json({ erreur: "Erreur inattendue : " + (e as Error).message }, 500);
  }
});
