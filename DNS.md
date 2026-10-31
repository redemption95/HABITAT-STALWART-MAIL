# DNS for habitat.org.in mail

A reference for every mail-related DNS record: what it does, why it's there, and whether to keep it. Stalwart's
automatic DNS management (Cloudflare API) created most of these on 2026-10-29. All mail records are **DNS only
(grey cloud)**: Cloudflare's proxy only carries web traffic, not mail.

**Status:** **Keep**: correct as it is. **Change**: keep the record, edit the value. **Delete**: remove it.
**Add**: missing, create it by hand.

## The one limitation behind most decisions

On this VPS, **port 443 belongs to Caddy** (the Habitat website/API) and only accepts Cloudflare's IPs. Stalwart's
own HTTPS port is published only on `127.0.0.1:8443`, for the admin through an SSH tunnel. Port **995** (POP3) isn't
published at all.

So anything that asks a phone, mail app or other mail server to fetch `https://mail.habitat.org.in/...` (or POP3)
**cannot work**. Records that advertise those services point clients at something unreachable, so they're deleted.

What the outside world *can* reach on `mail.habitat.org.in`: **25** (server-to-server mail), **465** and **587**
(sending from apps), **993** (IMAP).

## 1. Records Stalwart created

### Core: finding and trusting the server

| Record | Type | Value | Purpose | Status |
|---|---|---|---|---|
| `mail` | A | `201.18.203.51` | Turns the name `mail.habitat.org.in` into the VPS IP. The MX record, phone apps and the TLS certificate all use this name. Must be grey: proxied would hide the real IP, and mail ports would stop working. | **Keep** |
| `@` | TXT | `v=spf1 mx -all` | **SPF** for the domain: "only the servers in my MX record may send mail from @habitat.org.in; reject everyone else (`-all`)". Receivers check it against the sending IP. There must be **exactly one** `v=spf1` record on `@`. | **Keep**, if nothing else sends as @habitat.org.in (see section 3) |
| `mail` | TXT | `v=spf1 a -all` | SPF for the server's own name. When Stalwart connects to Gmail it introduces itself (HELO) as `mail.habitat.org.in`, and some receivers check SPF for that name too. "`a`" means "the IP in mail's A record". | **Keep** |
| `v1-rsa-20261029._domainkey` | TXT | `v=DKIM1; k=rsa; …` | **DKIM** public key (RSA). Stalwart signs every outgoing mail with the private key; receivers fetch this key to check the signature, which proves the mail wasn't forged or altered. RSA is the type every receiver understands. | **Keep** |
| `v1-ed25519-20261029._domainkey` | TXT | `v=DKIM1; k=ed25519; …` | Second DKIM key, using the newer, shorter Ed25519 algorithm. Receivers that support it use it; the rest use RSA. Harmless to have both. | **Keep** |
| `_dmarc` | TXT | `v=DMARC1; p=reject; rua=mailto:postmaster@…` | **DMARC** tells receivers what to do with mail that fails SPF/DKIM alignment (`p=`), and where to send daily reports (`rua=`). `p=reject` from day one is risky: any mistake means Gmail/Outlook refuse your real mail, and you only find out from complaints. | **Change** to `v=DMARC1; p=none; rua=mailto:dmarc@habitat.org.in` |

### Sending/receiving security reports

| Record | Type | Value | Purpose | Status |
|---|---|---|---|---|
| `_smtp._tls` | TXT | `v=TLSRPT1; rua=mailto:postmaster@…` | **TLS-RPT**: asks big providers (Gmail, Microsoft) to send daily reports about encrypted-connection problems when delivering to you. Costs nothing, and postmaster@ goes to support@. | **Keep** |
| `_mta-sts` | TXT | `v=STSv1; id=…` | **MTA-STS** announcement: "this domain has a policy requiring encrypted delivery; fetch it from `https://mta-sts.habitat.org.in/.well-known/mta-sts.txt`". That URL is on port 443, which Caddy holds, so the policy can't be fetched. A policy that's announced but can't be fetched causes report noise, and can cause delivery problems if one is ever cached. | **Delete** |
| `mta-sts` | CNAME | `mail.habitat.org.in` | Hostname for the MTA-STS policy file above. Unreachable for the same reason. | **Delete** |

### Mail-app auto-setup (phones, Thunderbird, Outlook)

| Record | Type | Value | Purpose | Status |
|---|---|---|---|---|
| `_imaps._tcp` | SRV | `0 1 993 mail.habitat.org.in` | Standard (RFC 6186) hint: "IMAP over TLS for this domain is at mail.habitat.org.in:993". Some apps fill in the server settings from it. Port 993 is open. | **Keep** |
| `_submissions._tcp` | SRV | `0 1 465 mail.habitat.org.in` | Same, for sending: "SMTP submission over TLS is on port 465". Port 465 is open. | **Keep** |
| `_pop3s._tcp` | SRV | `0 1 995 mail.habitat.org.in` | Advertises POP3 on 995. Not published, and not wanted (IMAP is better for several devices). | **Delete** |
| `_jmap._tcp` | SRV | `0 1 443 mail.habitat.org.in` | Advertises **JMAP**, a modern JSON-over-HTTPS replacement for IMAP. It needs port 443. | **Delete** |
| `_caldavs._tcp` | SRV | `0 1 443 mail.habitat.org.in` | Advertises calendars (CalDAV) on 443. Not reachable, and not needed. | **Delete** |
| `_carddavs._tcp` | SRV | `0 1 443 mail.habitat.org.in` | Advertises contacts (CardDAV) on 443. Not reachable, and not needed. | **Delete** |
| `autoconfig` | CNAME | `mail.habitat.org.in` | Thunderbird (and others) fetch `https://autoconfig.habitat.org.in/mail/config-v1.1.xml` for settings. Port 443, so unreachable. The app would wait for a timeout before falling back to manual setup. | **Delete** |
| `autodiscover` | CNAME | `mail.habitat.org.in` | Outlook's equivalent (Autodiscover over HTTPS). Same problem. | **Delete** |
| `ua-auto-config` | CNAME | `mail.habitat.org.in` | Hostname for a newer, still-draft client auto-configuration scheme that Stalwart supports, also fetched over HTTPS. Same problem. | **Delete** |
| `_ua-auto-config` | TXT | `v=UAAC1; a=sha256; d=…` | The DNS half of that draft scheme (a hash that apps use to verify the downloaded settings). Useless without the HTTPS half. | **Delete** |

Without the deleted records, apps either use the two SRV records or you type the settings once (README section 5).
That's one-off, for a single mailbox.

## 2. What Stalwart didn't create (your side)

| What | Where | Value | Why it's needed |
|---|---|---|---|
| **MX** record | Cloudflare | `@` → `mail.habitat.org.in`, priority 10, DNS only | **The most important record.** It tells the world "mail for @habitat.org.in goes to this server". Without it, nobody can send you mail (Gmail etc. bounce or fall back to the A record of the bare domain, which is the Cloudflare proxy). It must be the **only** MX: delete any others, and keep Cloudflare Email Routing off, because it installs its own MX records. |
| **PTR** (reverse DNS) | Hostinger hPanel → VPS → Settings → PTR | `201.18.203.51` → `mail.habitat.org.in` | The reverse of the A record: IP → name. Receivers check that the sending IP's name matches the name it uses (HELO) and resolves back to the same IP. Without it, Gmail and Outlook treat the mail as spam or reject it. Only the owner of the IP (Hostinger) can set it, which is why it's not in Cloudflare. |
| DMARC fix | Cloudflare | see `_dmarc` above | Start at `p=none` (watch only). Read the reports at dmarc@ for 2–4 weeks; when every legitimate source passes, move to `p=quarantine`, then `p=reject`. |
| Deletions | Cloudflare | the **Delete** rows above | They advertise services this server doesn't offer publicly. |
| Stop automatic DNS from undoing this | Stalwart admin → domain / DNS settings | manual, or disable auto-management | Stalwart may re-create deleted records or set DMARC back to `reject` on its next sync. Recheck Cloudflare about 10 minutes after editing. |

## 3. Open question: who else sends as @habitat.org.in?

SPF `-all` plus DMARC means **only this mail server** may send mail from @habitat.org.in. If the Habitat app (OTP,
sign-up, notifications) or any tool (newsletters, Google Workspace, a CRM) sends with a `From:` @habitat.org.in
through another provider, that mail will fail. Fix: add the provider to the one SPF record, e.g.
`v=spf1 mx include:<provider's SPF domain> -all`, and set up DKIM with that provider for habitat.org.in.

**Status (2026-10-31):** nothing else sends yet. The backend will send mail later. Decide then:

- **Through this server** (no DNS change): create a sending account in Stalwart (e.g. `noreply@habitat.org.in`)
  and have the backend log in with SMTP on `mail.habitat.org.in:587` (STARTTLS) or `465` (TLS). SPF and DKIM
  already cover it. Free; deliverability depends on this one IP's reputation.
- **Through a provider** (SES, Resend, Postmark, …): add its `include:` to SPF and its DKIM records, ideally on a
  subdomain such as `notify.habitat.org.in`, so OTP traffic and support@ mail don't share reputation. Costs a
  little; better delivery tracking, and it keeps OTPs flowing if this server is down.

## Later: tightening, once basic mail works

Do these in order, one at a time, only after Gmail "Show original" shows SPF, DKIM and DMARC all PASS. Dates
assume DMARC moves to `p=none` around 2026-10-31.

| When | What | How | Why wait |
|---|---|---|---|
| Weekly from now | Read DMARC reports | Mails to dmarc@ (zipped XML from Google, Microsoft, …). A viewer such as dmarcian's free XML-to-human converter helps. Look for any source that fails, and work out whether it's yours. | This is how you find senders you forgot (the app, a newsletter tool) before blocking them. |
| ~2026-11-14 (2 weeks of clean reports) | DMARC → **quarantine** | `_dmarc` TXT: `v=DMARC1; p=quarantine; rua=mailto:dmarc@habitat.org.in` | Failing mail goes to spam instead of being refused. A mistake is still recoverable. |
| ~2026-11-28 (2 more clean weeks) | DMARC → **reject** | `v=DMARC1; p=reject; rua=mailto:dmarc@habitat.org.in` | Full protection: forged @habitat.org.in mail is refused outright. This is what Stalwart set on day one; it's the goal, just not the starting point. |
| After DMARC reject (December) | **MTA-STS** in `testing` | 1. Cloudflare: `mta-sts` → A `201.18.203.51`, **proxied (orange)**, replacing the grey CNAME. 2. Caddy (habitat-edge, Habitat monorepo): a site for `mta-sts.habitat.org.in` returning `https://mta-sts.habitat.org.in/.well-known/mta-sts.txt` as plain text: `version: STSv1` / `mode: testing` / `mx: mail.habitat.org.in` / `max_age: 86400`. 3. TXT `_mta-sts`: `v=STSv1; id=<new number, e.g. 20261201>`. | Forces encrypted delivery to you. In testing mode senders only report problems (via TLS-RPT to postmaster@), they still deliver. |
| ~4 weeks after testing, clean TLS-RPT reports | MTA-STS → **enforce** | Policy `mode: enforce`, `max_age: 604800`; change the `_mta-sts` `id`. | Senders refuse to deliver unencrypted or to a wrong certificate. If the certificate ever fails to renew, inbound mail stops, so only enforce once ACME renewal has worked at least once (Let's Encrypt certificates renew after about 60 days, so around late December). |
| Every few months | Check the certificate | `openssl s_client -connect mail.habitat.org.in:993 </dev/null 2>/dev/null \| openssl x509 -noout -dates` | ACME DNS-01 depends on the Cloudflare token staying valid. If the token is rolled or deleted, renewal silently fails. |

## 4. Records that aren't about mail (leave alone)

`@`, `www`, `api`, `staging`: A records, **proxied (orange)**. They're the website and API behind Cloudflare.
Cloudflare warns that `mail` (grey) exposes the same IP as these. That's expected and accepted: mail can't go
through Cloudflare's proxy, and ports 80/443 on the VPS only accept Cloudflare's IPs anyway.

## 5. Check it

From the Mac (remove the `127.0.0.1 mail.habitat.org.in` line from `/etc/hosts` first, or run on the server):

```bash
dig +short MX habitat.org.in                                   # 10 mail.habitat.org.in.
dig +short TXT habitat.org.in | grep spf                       # exactly one line
dig +short TXT _dmarc.habitat.org.in                           # p=none
dig +short TXT v1-rsa-20261029._domainkey.habitat.org.in       # the RSA key
dig +short A mail.habitat.org.in                               # 201.18.203.51
dig +short -x 201.18.203.51                                    # mail.habitat.org.in.
dig +short TXT _mta-sts.habitat.org.in                         # nothing (deleted)
```

Then the end-to-end checks in README section 6: Gmail "Show original" (SPF, DKIM and DMARC all PASS) and
mail-tester.com.

## Glossary

- **SPF**: which IPs may send for the domain. Checked against the envelope sender and the HELO name.
- **DKIM**: a cryptographic signature on each mail; the public key lives in DNS.
- **DMARC**: ties SPF/DKIM to the visible `From:` domain, says what to do on failure, and asks for reports.
- **PTR / reverse DNS**: IP → hostname; set by whoever owns the IP.
- **MTA-STS / TLS-RPT**: "always deliver to me encrypted" policy and the reports about it.
- **SRV**: "service X for this domain is at host:port".
- **Selector**: the `v1-rsa-20261029` part of a DKIM name, so a domain can have several keys and rotate them.
