# Habitat mail

Self-hosted email for **habitat.org.in** with [Stalwart](https://stalw.art) 1.0: receiving (SMTP), sending from
phones and apps (SMTP submission), reading (IMAP), spam filtering, DKIM signing and a web admin, in one container
(about 150–250 MB of RAM). It runs on the Habitat VPS as its own Compose project, separate from the app.

- **One mailbox:** `support@habitat.org.in`.
- **Aliases** delivered to it: `sales@`, `partner@`, `grievance@`, `dmarc@`, `postmaster@` and `abuse@`.
  You can send as any of them.
- **Phone:** use any mail app (iOS Mail, Gmail app, Thunderbird, K-9).
- **Backups:** nightly, encrypted, to Cloudflare R2 (`habitat-backups/mail/`).

```
Internet ──25──▶ ┐
Phone ──465/587/993──▶ Stalwart (container) ── volumes: config, data
You ──SSH tunnel──▶ 127.0.0.1:8443 (web admin, never public)
```

## 1. Install (once, on the VPS)

```bash
scp -r ~/workspace/habitat-mail root@<vps-ip>:/root/      # on your Mac
bash /root/habitat-mail/setup.sh                            # on the server, as root
```

`setup.sh` copies the files to `/opt/habitat-mail`, opens ports 25, 465, 587 and 993, starts Stalwart and
schedules the 03:00 IST backup. Running it again is safe.

## 2. Admin access

The admin page only listens on the server itself, and Stalwart 1.0 only accepts sign-in at its own HTTPS hostname
(anything else says "Unknown client id"). So the browser has to reach `mail.habitat.org.in` through a tunnel.

**Normal access** (after the TLS certificate in section 3 is issued):

1. Once, on your Mac, point the hostname at the tunnel: `echo '127.0.0.1 mail.habitat.org.in' | sudo tee -a /etc/hosts`.
   Remove that line if you ever need to reach the real server by name from the Mac (e.g. the port checks in
   section 6, or a mail app on the Mac).
2. Open a tunnel and leave it running. It must use local port 443 (hence `sudo`, which asks for your Mac
   password, then the root password): sign-in redirects to `https://mail.habitat.org.in/login` with no port.

   ```bash
   sudo ssh -N -L 443:127.0.0.1:8443 root@<vps-ip>
   ```
3. Open **https://mail.habitat.org.in/admin**.

**Recovery mode** (first setup, before there is a certificate, or when locked out). On the server:

```bash
umask 077; printf 'STALWART_RECOVERY_MODE=1\nSTALWART_RECOVERY_ADMIN=admin:%s\n' "$(openssl rand -hex 16)" \
  > /opt/habitat-mail/stalwart.env
cat /opt/habitat-mail/stalwart.env          # note the password
docker compose -f /opt/habitat-mail/compose.yml up -d
```

Tunnel with `ssh -N -L 8080:127.0.0.1:8080 root@<vps-ip>` and open **http://localhost:8080/admin**. Mail may not
be served in recovery mode, so leave it as soon as you're done:

```bash
rm /opt/habitat-mail/stalwart.env && docker compose -f /opt/habitat-mail/compose.yml up -d
```

On a brand-new install, the first password for the setup wizard is in the logs:

```bash
docker compose -f /opt/habitat-mail/compose.yml logs stalwart | grep -i -A2 password
```

## 3. Configure (in the web admin)

Menu names may differ slightly in Stalwart 1.0. Look for these settings:

1. **Server hostname:** `mail.habitat.org.in`.
2. **TLS certificate:** add an ACME provider, **Let's Encrypt**, with:
   - challenge **DNS-01**, DNS provider **Cloudflare**;
   - a Cloudflare API token with **Zone → DNS → Edit**, limited to `habitat.org.in` (a new token, separate from
     the firewall one);
   - domain `mail.habitat.org.in`.

   Why DNS-01: the server only accepts web traffic (80/443) from Cloudflare, so Let's Encrypt can't check it the
   usual way. DNS-01 proves ownership through a DNS record instead.
3. **Domain:** add `habitat.org.in` and **generate DKIM keys**. Stalwart lists the DNS records the domain needs.
   Add them as in section 4.
4. **Account:** create `support@habitat.org.in` with a long password, and add the aliases `sales@`, `partner@`,
   `grievance@`, `dmarc@`, `postmaster@` and `abuse@`.
5. Check that **automatic banning** of repeated failed logins is on (Stalwart does this itself; no fail2ban needed).

## 4. DNS (Cloudflare, all **DNS only / grey cloud**: mail can't go through Cloudflare's proxy)

Every record explained, including the ones Stalwart creates automatically and which to delete: [DNS.md](DNS.md).

| Type | Name | Content | Notes |
|---|---|---|---|
| A | `mail` | VPS IP | DNS only |
| MX | `@` | `mail.habitat.org.in` | priority 10 |
| TXT | `@` | `v=spf1 mx ~all` | the **only** `v=spf1` record; remove any other |
| TXT | `<selector>._domainkey` | from Stalwart (step 3) | DKIM; usually two (RSA and Ed25519) |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@habitat.org.in` | change to `p=quarantine` after 2–4 weeks of passing reports |
| SRV | `_submissions._tcp` | priority 0, weight 1, port 465, `mail.habitat.org.in` | lets phone apps find the settings |
| SRV | `_imaps._tcp` | priority 0, weight 1, port 993, `mail.habitat.org.in` | lets phone apps find the settings |

- **Reverse DNS (PTR):** at Hostinger (hPanel → VPS → Settings → PTR / reverse DNS), set the VPS IP to
  `mail.habitat.org.in`. Without it, Gmail and Outlook distrust the mail.
- **Cloudflare Email Routing must be off**, or its MX records will compete with this server.
- The `mail` record publishes the VPS IP. The website and API stay behind Cloudflare: ports 80/443 accept
  Cloudflare only.

## 5. Phone and computer

| | Server | Port | Security | Username |
|---|---|---|---|---|
| Incoming (IMAP) | `mail.habitat.org.in` | 993 | SSL/TLS | `support@habitat.org.in` |
| Outgoing (SMTP) | `mail.habitat.org.in` | 465 | SSL/TLS | `support@habitat.org.in` |

- **Sending as an alias:** add an extra "identity" or "from address", e.g. `sales@habitat.org.in`, with the same
  login. iOS Mail, Thunderbird and K-9 support this.
- **Gmail app:** Add account → Other → IMAP.

## 6. Check it works

- **Inbound:** send a mail from your personal Gmail to `sales@habitat.org.in`. It should arrive in the `support@`
  mailbox.
- **Authentication:** reply to Gmail, then in Gmail open **⋮ → Show original**. You want **SPF: PASS, DKIM: PASS,
  DMARC: PASS**.
- **Deliverability score:** send a mail to the address shown at mail-tester.com. Aim for 9/10 or better.
- **Ports from outside:** `nc -vz mail.habitat.org.in 25` and `nc -vz mail.habitat.org.in 993` from your Mac.

## Backups

- **Schedule:** nightly at 03:00 IST.
- **How:** Stalwart is paused for a few seconds (senders retry, nothing is lost), its config and data are
  archived and encrypted, then copied to `r2:habitat-backups/mail/`. 5 days are kept on the server (for a quick restore without downloading); R2 keeps 30.
- **Setup:** fill `/opt/habitat-mail/backup.env` with the R2 keys, and keep `BACKUP_PASSPHRASE` in your password
  manager. Without the passphrase, the backups can't be opened.
- **Run now:** `/opt/habitat-mail/backup.sh`
- **Restore:** `/opt/habitat-mail/restore.sh <file>`. It asks for confirmation, then replaces all mail.

## Upgrades

Read the release notes, change the image tag in `compose.yml`, take a backup, then:

```bash
docker compose -f /opt/habitat-mail/compose.yml pull && docker compose -f /opt/habitat-mail/compose.yml up -d
```

Copy the updated `compose.yml` to the server first (or re-run `setup.sh`).
