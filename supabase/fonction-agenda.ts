// NexusLab, fonction Edge « agenda » : flux .ics personnel, lu par Google Agenda,
// Apple Calendrier ou Outlook. Adresse : <projet>.supabase.co/functions/v1/agenda?jeton=...
// À déployer SANS vérification JWT (les agendas n'envoient pas d'en-tête) :
// la sécurité repose sur le jeton personnel de 64 caractères (table jetons_agenda).

const BASE = Deno.env.get("SUPABASE_URL")!;
// Clé serveur : ancienne clé service_role (JWT) ou nouvelle clé secrète (sb_secret_...), selon le projet.
const SECRETS = (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); } catch { return {}; } })();
const CLE: string = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || SECRETS.default || Object.values(SECRETS)[0] as string;
const ENTETES: Record<string, string> = CLE.startsWith("eyJ") ? { apikey: CLE, Authorization: `Bearer ${CLE}` } : { apikey: CLE };
const DASH = "https://dashboard-nexuslab.netlify.app/";
const TZ = "Europe/Zurich";

async function q(chemin: string) {
  const r = await fetch(`${BASE}/rest/v1/${chemin}`, { headers: ENTETES });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return await r.json();
}
const jourZurich = (d = new Date()) => new Intl.DateTimeFormat("sv-SE", { timeZone: TZ }).format(d);
const plusJours = (iso: string, n: number) => { const d = new Date(iso + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const echap = (t: unknown) => String(t ?? "").replace(/\\/g, "\\\\").replace(/\r?\n/g, "\\n").replace(/([,;])/g, "\\$1");
function plier(ligne: string) {
  const o: string[] = []; let r = ligne;
  while (r.length > 73) { o.push(r.slice(0, 73)); r = " " + r.slice(73); }
  o.push(r); return o.join("\r\n");
}
// « 16h30 », « 16:30-18h », « 9h à 10h15 » : début et fin (fin par défaut : 1 h après)
function plageHeure(txt: unknown): { debut: string; fin: string } | null {
  const t = String(txt ?? "").toLowerCase();
  const m = [...t.matchAll(/(\d{1,2})\s*(?:[:h.]\s*(\d{2})?)/g)].map((x) => Number(x[1]) * 60 + Number(x[2] ?? 0)).filter((v) => v >= 0 && v < 1440);
  if (!m.length) return null;
  const d = m[0], f = m[1] > d ? m[1] : Math.min(d + 60, 1439);
  const fmt = (v: number) => String(Math.floor(v / 60)).padStart(2, "0") + String(v % 60).padStart(2, "0") + "00";
  return { debut: fmt(d), fin: fmt(f) };
}

type Evt = { uid: string; date: string; plage?: { debut: string; fin: string } | null; titre: string; desc: string; lien: string };

Deno.serve(async (req) => {
  try {
    const jeton = new URL(req.url).searchParams.get("jeton") ?? "";
    if (!/^[0-9a-f]{64}$/.test(jeton)) return new Response("Lien d'agenda invalide.", { status: 404 });
    const j = await q(`jetons_agenda?jeton=eq.${jeton}&select=membre_id`);
    if (!j.length) return new Response("Lien d'agenda inconnu ou remplacé.", { status: 404 });
    const id = j[0].membre_id as string;
    const [m] = await q(`membres?id=eq.${id}&select=id,nom,actif,acces_jusquau`);
    const auj = jourZurich();
    if (!m || !m.actif || (m.acces_jusquau && m.acces_jusquau < auj)) return new Response("Accès terminé.", { status: 410 });

    const debut = plusJours(auj, -30), fin = plusJours(auj, 365);
    const entre = (col: string) => `${col}=gte.${debut}&${col}=lte.${fin}`;
    const [taches, reunions, projets, clients, objectifs] = await Promise.all([
      q(`taches?select=id,titre,echeance,statut,projet_id&statut=neq.fait&${entre("echeance")}&or=(responsable_id.eq.${id},valideur_id.eq.${id})`),
      q(`reunions?select=id,titre,date,heure,lieu,type,participants&${entre("date")}`),
      q(`projets?select=id,nom,date_mise_en_ligne&${entre("date_mise_en_ligne")}`),
      q(`clients?select=id,nom,date_relance,prochaine_action,statut,responsable_id&${entre("date_relance")}&statut=not.in.(termine,perdu,livre)`).catch(() => []),
      q(`objectifs?select=id,titre,debut,fin`).catch(() => []),
    ]);

    const ev: Evt[] = [];
    for (const t of taches) ev.push({ uid: `tache-${t.id}`, date: t.echeance, titre: `Tâche · ${t.titre}`, desc: `Statut : ${({ a_faire: "à faire", en_cours: "en cours", bloque: "bloqué", a_valider: "à valider" } as Record<string, string>)[t.statut] ?? t.statut}`, lien: DASH + "#/taches" });
    for (const r of reunions) {
      const p: string[] = r.participants ?? [];
      if (p.length && !p.includes(id)) continue;
      ev.push({ uid: `reunion-${r.id}`, date: r.date, plage: plageHeure(r.heure), titre: `Réunion · ${r.titre}`, desc: [r.heure, r.lieu].filter(Boolean).join(" · "), lien: DASH + "#/reunions/" + r.id });
    }
    for (const p of projets) ev.push({ uid: `mel-${p.id}`, date: p.date_mise_en_ligne, titre: `Mise en ligne · ${p.nom}`, desc: "", lien: DASH + "#/projets/" + p.id });
    for (const c of clients) {
      if (c.responsable_id && c.responsable_id !== id) continue;
      ev.push({ uid: `relance-${c.id}-${c.date_relance}`, date: c.date_relance, titre: `Relancer ${c.nom}`, desc: c.prochaine_action ?? "", lien: DASH + "#/clients/" + c.id });
    }
    for (const o of objectifs) {
      if (o.debut && o.debut >= debut && o.debut <= fin) ev.push({ uid: `obj-debut-${o.id}`, date: o.debut, titre: `Début objectif · ${o.titre}`, desc: "", lien: DASH + "#/objectifs" });
      if (o.fin && o.fin >= debut && o.fin <= fin) ev.push({ uid: `obj-fin-${o.id}`, date: o.fin, titre: `Fin objectif · ${o.titre}`, desc: "", lien: DASH + "#/objectifs" });
    }

    const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
    const l = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//NexusLab//Dashboard//FR", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
      plier(`X-WR-CALNAME:NexusLab (${echap(m.nom)})`), `X-WR-TIMEZONE:${TZ}`, "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H"];
    for (const e of ev) {
      const d = e.date.replace(/-/g, "");
      l.push("BEGIN:VEVENT", `UID:${e.uid}@nexus-lab.ch`, `DTSTAMP:${stamp}`);
      if (e.plage) {
        l.push(`DTSTART;TZID=${TZ}:${d}T${e.plage.debut}`, `DTEND;TZID=${TZ}:${d}T${e.plage.fin}`);
      } else {
        l.push(`DTSTART;VALUE=DATE:${d}`, `DTEND;VALUE=DATE:${plusJours(e.date, 1).replace(/-/g, "")}`, "TRANSP:TRANSPARENT");
      }
      l.push(plier("SUMMARY:" + echap(e.titre)), plier("DESCRIPTION:" + echap([e.desc, e.lien].filter(Boolean).join("\n"))), plier("URL:" + e.lien), "END:VEVENT");
    }
    l.push("END:VCALENDAR");
    return new Response(l.join("\r\n") + "\r\n", {
      headers: { "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "public, max-age=900", "Content-Disposition": 'inline; filename="nexuslab.ics"' },
    });
  } catch (err) {
    console.error(err);
    return new Response("Agenda momentanément indisponible.", { status: 500 });
  }
});
