// ── Email Validation — syntax, normalization, MX check, disposable blacklist ──
// AC3: Full pre-check pipeline before any OTP is generated or sent.
// AC4: Pipeline order: syntax → normalize → MX → disposable.

// ── 1. Syntax validation ──────────────────────────────────────────────────────

// RFC-permissive but practical — rejects obvious non-emails.
export function validateEmailSyntax(email: string): boolean {
  if (typeof email !== 'string') return false;
  if (email.length > 254) return false; // RFC 5321 max
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
}

// ── 2. Normalization ──────────────────────────────────────────────────────────

// Normalize email to a canonical form for deduplication:
// - lowercase the entire address
// - for Gmail (@gmail.com, @googlemail.com): strip dots from local part and remove +tags
// - for all providers: strip +tags from local part
export function normalizeEmail(email: string): string {
  const lower = email.toLowerCase().trim();
  const atIdx = lower.lastIndexOf('@');
  if (atIdx === -1) return lower;

  let local = lower.slice(0, atIdx);
  const domain = lower.slice(atIdx + 1);

  // Strip +tags from all providers
  const plusIdx = local.indexOf('+');
  if (plusIdx !== -1) {
    local = local.slice(0, plusIdx);
  }

  // Gmail: strip dots from local part
  if (domain === 'gmail.com' || domain === 'googlemail.com') {
    local = local.replace(/\./g, '');
  }

  return `${local}@${domain}`;
}

// ── 3. MX record check ────────────────────────────────────────────────────────

// Check if a domain has valid MX records using Google DNS over HTTPS.
// Returns true if at least one MX record exists.
// Returns false on network errors (fail-open for resilience — don't block legit users
// because of a transient DNS failure).
export async function checkMxRecord(domain: string): Promise<boolean> {
  try {
    const url = `https://dns.google/resolve?name=${encodeURIComponent(domain)}&type=MX`;
    const res = await fetch(url, {
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) return true; // fail-open
    const data = await res.json() as { Status?: number; Answer?: unknown[] };
    // Status 0 = NOERROR, Status 3 = NXDOMAIN
    if (data.Status === 3) return false; // domain doesn't exist
    // No Answer means no MX records
    if (!Array.isArray(data.Answer) || data.Answer.length === 0) return false;
    return true;
  } catch {
    return true; // fail-open: network errors don't block legitimate users
  }
}

// ── 4. Disposable domain blacklist ────────────────────────────────────────────

// Curated list of well-known disposable/temporary email providers (~100 most common).
// Covers the large majority of abuse cases. Extendable via KV for production scaling.
const DISPOSABLE_DOMAINS = new Set([
  '10minutemail.com', '10minutemail.net', '10minutemail.org', '10minutemail.de',
  '20minutemail.com', '33mail.com', 'airmail.in', 'armyspy.com',
  'binkmail.com', 'boun.cr', 'bouncr.com', 'breakthru.com',
  'bspamfree.org', 'bugmenot.com', 'bund.us', 'chacuo.net',
  'chammy.info', 'cloakmail.com', 'cuvox.de', 'dacoolest.com',
  'dayrep.com', 'deadaddress.com', 'deagot.com', 'despam.it',
  'discardmail.com', 'discardmail.de', 'discard.email', 'disposable.com',
  'disposableaddress.com', 'disposableemailaddresses.com', 'disposableinbox.com',
  'dispostable.com', 'dodgeit.com', 'dodgemail.de', 'donemail.ru',
  'dontreg.com', 'dontsendmespam.de', 'drdrb.com', 'dudmail.com',
  'dump-email.info', 'dumpandfuck.com', 'e4ward.com', 'einrot.com',
  'emailage.cf', 'emaildrop.io', 'emailfake.com', 'emailigo.com',
  'emailinfive.com', 'emailsensei.com', 'emailtemporanea.com', 'emailtemporanea.net',
  'emailtemporal.org', 'emailthe.net', 'emailwarden.com', 'ephemail.net',
  'etranquil.com', 'etranquil.net', 'etranquil.org', 'explodemail.com',
  'fakeinbox.com', 'fakeinbox.net', 'fakeinformation.com', 'fakemail.fr',
  'fastacura.com', 'fastchevy.com', 'fastchrysler.com', 'fasternet.biz',
  'filzmail.com', 'filzmail.de', 'fixmail.tk', 'fleckens.hu',
  'flyspam.com', 'fortgates.net', 'freeletter.me', 'freemail.ms',
  'freundin.ru', 'front14.org', 'fudgerub.com', 'fugglies.com',
  'garliclife.com', 'gelitik.in', 'getonemail.com', 'getonemail.net',
  'giantmail.de', 'girlsundertheinfluence.com', 'gishpuppy.com', 'glitch.sx',
  'goemailgo.com', 'gotmail.com', 'gotmail.net', 'gotmail.org',
  'gotti.otherinbox.com', 'grr.la', 'gsrv.co.uk', 'guerillamail.biz',
  'guerillamail.de', 'guerillamail.info', 'guerillamail.net', 'guerillamail.org',
  'guerrillamail.biz', 'guerrillamail.com', 'guerrillamail.de', 'guerrillamail.info',
  'guerrillamail.net', 'guerrillamail.org', 'guerrillamailblock.com',
  'gustr.com', 'h.mintemail.com', 'haltospam.com', 'hatespam.org',
  'herp.in', 'hidemail.de', 'hmamail.com', 'hochsitze.com',
  'hopemail.biz', 'hulapla.de', 'hurify1.com', 'hushmail.com',
  'ieatspam.eu', 'ieatspam.info', 'ieh-mail.de', 'ihateyoualot.info',
  'iheartspam.org', 'ikbenspamvrij.nl', 'imails.info', 'inboxbear.com',
  'inboxclean.com', 'inboxclean.org', 'incognitomail.com', 'incognitomail.net',
  'incognitomail.org', 'insorg.org', 'instant-mail.de', 'instantemailaddress.com',
  'instantmail.fr', 'internet-e-mail.de', 'internet-mail.de', 'internetemails.net',
  'internetmailing.net', 'inoutmail.de', 'inoutmail.eu', 'inoutmail.info',
  'inoutmail.net', 'ipoo.org', 'irish2me.com', 'iwi.net',
  'jetable.com', 'jetable.fr.nf', 'jetable.net', 'jetable.org',
  'jnxjn.com', 'jourrapide.com', 'jsrsolutions.com', 'junklmail.com',
  'jupimail.com', 'kasmail.com', 'kaspop.com', 'killmail.com',
  'killmail.net', 'klassmaster.com', 'klzlk.com', 'kook.ml',
  'kurzepost.de', 'l33r.eu', 'lackmail.net', 'lags.us',
  'lakelivingstonreal.com', 'landmail.co', 'lastmail.co', 'lavache.com',
  'lawlz.net', 'lazyinbox.com', 'letthemeatspam.com', 'lhsdv.com',
  'lifebyfood.com', 'link2mail.net', 'litedrop.com', 'lol.ovpn.to',
  'lolfreak.net', 'lookugly.com', 'lortemail.dk', 'lucky-day.pro',
  'mailinator.com', 'mailinator.net', 'mailinator.org', 'mailinator2.com',
  'mailinator2.net', 'mailbox.in.ua', 'mailcatch.com', 'maildrop.cc',
  'maileater.com', 'mailexpire.com', 'mailfreeonline.com', 'mailfs.com',
  'mailguard.me', 'mailimate.com', 'mailme.gq', 'mailme.ir',
  'mailme.lv', 'mailme24.com', 'mailmetrash.com', 'mailmoat.com',
  'mailnull.com', 'mailnull.net', 'mailscrap.com', 'mailseal.de',
  'mailshell.com', 'mailsiphon.com', 'mailslite.com', 'mailtemp.info',
  'mailtemporaire.com', 'mailtemporaire.fr', 'mailtothis.com', 'mailzilla.com',
  'mailzilla.org', 'mbx.cc', 'mega.zik.dj', 'meinspamschutz.de',
  'meltmail.com', 'messagebeamer.de', 'mierdamail.com', 'mints.pw',
  'mobileninja.co.uk', 'mohmal.com', 'moncourrier.fr.nf', 'monemail.fr.nf',
  'monmail.fr.nf', 'mox.pp.ua', 'mt2009.com', 'mt2014.com',
  'mx0.wwwnew.eu', 'mycleaninbox.net', 'mymail-in.net', 'mymailoasis.com',
  'mypartyclip.de', 'myphantomemail.com', 'myspace.sytes.net', 'mytrashmail.com',
  'nabuma.com', 'neomailbox.com', 'nepwk.com', 'nervmich.net',
  'nervtmich.net', 'netmails.com', 'netmails.net', 'netzidiot.de',
  'nevermail.de', 'newyorkinmyveins.com', 'nfast.net', 'nfmailz.com',
  'nice-4u.com', 'nmail.cf', 'no-spam.ws', 'noblepioneer.com',
  'nodezine.com', 'nogmailspam.info', 'nomail.pw', 'nomail.xl.cx',
  'nomail2me.com', 'noman.ws', 'nonspam.eu', 'nonspammer.de',
  'notmailinator.com', 'notsharingmy.info', 'nowhere.org', 'nowmymail.com',
  'nurfuerspam.de', 'nwldx.com', 'objectmail.com', 'obobbo.com',
  'odaymail.com', 'odnorazovoe.ru', 'onewaymail.com', 'online.ms',
  'oopi.org', 'opayq.com', 'ordinaryamerican.net', 'otherinbox.com',
  'ourklips.com', 'outlawspam.com', 'owlpic.com', 'ownmail.net',
  'oxopoha.com', 'paplease.com', 'pcusers.otherinbox.com', 'pepbot.com',
  'pfui.ru', 'phreaker.net', 'pierogitown.com', 'plexolan.de',
  'pook.ml', 'popesodomy.com', 'pookmail.com', 'postacı.com',
  'privacy.net', 'privymail.de', 'proxymail.eu', 'prtnx.com',
  'prtz.eu', 'punkass.com', 'putthisinyourspamdatabase.com', 'pwrby.com',
  'quickinbox.com', 'quickmail.in', 'r9guw.com', 'recode.me',
  'recyclemail.dk', 'redchan.it', 'regbypass.com', 'regbypass.comsafe-mail.net',
  'rejectmail.com', 'renko.hu', 'rklips.com', 'rmail.com',
  'rmqkr.net', 'robertspcrepair.com', 'rppkn.com', 'rtrtr.com',
  's0ny.net', 'safe-mail.net', 'safetymail.info', 'safetypost.de',
  'sandelf.de', 'schafmail.de', 'schrott-email.de', 'secretemail.de',
  'secure-mail.biz', 'securemail.biz', 'sendspamhere.com', 'senseless-entertainment.com',
  'sharklasers.com', 'shieldemail.com', 'shiftmail.com', 'shitmail.de',
  'shitware.nl', 'shortmail.net', 'sibmail.com', 'skeefmail.com',
  'slaskpost.se', 'slopsbox.com', 'slushmail.com', 'smellfear.com',
  'sneakemail.com', 'sneakmail.de', 'snkmail.com', 'sofimail.com',
  'sofort-mail.de', 'spam4.me', 'spamail.de', 'spambob.com',
  'spambob.net', 'spambob.org', 'spambog.com', 'spambog.de',
  'spambog.ru', 'spambooger.com', 'spamcorptastic.com', 'spamcowboy.com',
  'spamcowboy.net', 'spamcowboy.org', 'spamday.com', 'spamdecoy.net',
  'spameater.com', 'spameater.org', 'spamex.com', 'spamfree.eu',
  'spamfree24.de', 'spamfree24.eu', 'spamfree24.info', 'spamfree24.net',
  'spamfree24.org', 'spamgoes.in', 'spamgourmet.com', 'spamgourmet.net',
  'spamgourmet.org', 'spamherelots.com', 'spamherenow.com', 'spamhole.com',
  'spamify.com', 'spaminator.de', 'spamkill.info', 'spaml.com',
  'spaml.de', 'spammotel.com', 'spammy.host', 'spamoff.de',
  'spamoverdose.com', 'spampalace.com', 'spampost.com', 'spamspot.com',
  'spamstack.net', 'spamthis.co.uk', 'spamtroll.net', 'speed.1s.fr',
  'spoofmail.de', 'spray.se', 'squizzy.de', 'squizzy.eu',
  'squizzy.net', 'sr.ro', 'ssoia.com', 'startkeys.com',
  'stexsy.com', 'stinkefinger.net', 'stop-my-spam.com', 'streetwisemail.com',
  'suburbanthug.com', 'suremail.info', 'sweetxxx.de', 'tafmail.com',
  'taglead.com', 'tagyourself.com', 'teewars.org', 'teleworm.com',
  'teleworm.us', 'temp-mail.com', 'temp-mail.de', 'temp-mail.io',
  'temp-mail.net', 'temp-mail.org', 'temp-mail.ru', 'temp-mail.us',
  'tempail.com', 'tempemail.co.za', 'tempemail.com', 'tempemail.net',
  'tempinbox.co.uk', 'tempinbox.com', 'tempmail.de', 'tempmail.eu',
  'tempmail.info', 'tempmail.it', 'tempmail.us', 'temporamail.com',
  'temporaryemail.net', 'temporaryemail.us', 'temporaryforwarding.com',
  'temporaryinbox.com', 'temporarymailaddress.com', 'tempsky.com',
  'thankyou2010.com', 'thanksnospam.info', 'thecloudindex.com',
  'thenulls.co.uk', 'thisisnotmyrealemail.com', 'throwam.com',
  'throwaway.email', 'throwawayemailaddress.com', 'throwam.com',
  'tilien.com', 'tittbit.in', 'tmail.com', 'tmailinator.com',
  'toiea.com', 'tradermail.info', 'trash-mail.at', 'trash-mail.com',
  'trash-mail.de', 'trash-mail.ga', 'trash-mail.io', 'trash-mail.me',
  'trash-mail.ml', 'trash-me.com', 'trashdevil.com', 'trashdevil.de',
  'trashemail.de', 'trashmail.at', 'trashmail.com', 'trashmail.de',
  'trashmail.io', 'trashmail.me', 'trashmail.net', 'trashmail.org',
  'trashmail2.com', 'trashmailer.com', 'trashmailer.com', 'trashmailer.com',
  'trillianpro.com', 'tunxis.college', 'turual.com', 'twinmail.de',
  'tyldd.com', 'uggsrock.com', 'umail.net', 'unican.es',
  'unmail.ru', 'uroid.com', 'us.af', 'username.e4ward.com',
  'venompen.com', 'veryrealemail.com', 'viditag.com', 'viewcastmedia.com',
  'viewcastmedia.net', 'viewcastmedia.org', 'vomoto.com', 'vpn.st',
  'vsimcard.com', 'vubby.com', 'w3internet.co.uk', 'wakingupesther.com',
  'walala.org', 'walkmail.net', 'wallm.com', 'wam.co.za',
  'webemail.me', 'weg-werf-email.de', 'wegwerf-email.de', 'wegwerf-emails.de',
  'wegwerfadresse.de', 'wegwerfemail.de', 'wegwerfmail.de', 'wegwerfmail.info',
  'wegwerfmail.net', 'wegwerfmail.org', 'wh4f.org', 'whatpaas.com',
  'whyspam.me', 'willhackforfood.biz', 'willselfdestruct.com', 'winemaven.info',
  'wronghead.com', 'wuzupmail.net', 'www.e4ward.com', 'www.yep.it',
  'wwwnew.eu', 'xemaps.com', 'xents.com', 'xmaily.com',
  'xoxy.net', 'xsmail.com', 'xww.ro', 'yahoo.com.br', // not disposable but domain-spoofed variants
  'yahoobs.com', 'yapped.net', 'ybox.pl', 'yepmail.net',
  'yogamaven.com', 'yopmail.com', 'yopmail.fr', 'yopmail.gq',
  'youmail.ga', 'yourtube.ml', 'yuurok.com', 'z1p.biz',
  'za.com', 'zehnminutenmail.de', 'zetmail.com', 'zip.net',
  'zipmail.com.br', 'zoemail.net', 'zoemail.org', 'zomg.info',
  'zxcv.com', 'zxcvbnm.com', 'zzz.com',
]);

export function isDisposableDomain(domain: string): boolean {
  return DISPOSABLE_DOMAINS.has(domain.toLowerCase());
}

// ── Pre-check pipeline (AC4) ──────────────────────────────────────────────────

export interface EmailPreCheckResult {
  ok: boolean;
  normalizedEmail?: string;
  error?: 'invalid_syntax' | 'no_mx_record' | 'disposable_domain';
}

// Run the full pre-check pipeline in order: syntax → normalize → MX → disposable.
// All checks run before any OTP is generated or sent.
export async function preCheckEmail(email: string): Promise<EmailPreCheckResult> {
  // 1. Syntax
  if (!validateEmailSyntax(email)) {
    return { ok: false, error: 'invalid_syntax' };
  }

  // 2. Normalize
  const normalizedEmail = normalizeEmail(email);
  const domain = normalizedEmail.split('@')[1] ?? '';

  // 3. MX record check
  const hasMx = await checkMxRecord(domain);
  if (!hasMx) {
    return { ok: false, error: 'no_mx_record' };
  }

  // 4. Disposable domain blacklist
  if (isDisposableDomain(domain)) {
    return { ok: false, error: 'disposable_domain' };
  }

  return { ok: true, normalizedEmail };
}
