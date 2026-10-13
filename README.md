# Oleafly Server

Oleafly Server lets the people in your lab, course or research group write together in [Oleafly](https://oleafly.com) at the same time. Everyone keeps each project as real files on their own computer. The server passes changes, comments and files between them. When someone's connection drops, or they work offline for a while, their changes catch up once they're back.

You run it yourself, on a machine your group or institution controls. If you run a server, this repository is where you get it, update it and report problems.

## Install

On a Linux machine with a domain name pointing at it:

```sh
curl -fsSL https://oleafly.com/server/install.sh | sh
```

The installer:

1. Checks the machine: Linux on x86-64 or ARM, and ports 80 and 443 free.
2. Checks for Docker. If it is missing, it asks before installing it.
3. Asks for your domain, a name for the server and how people sign in.
4. Writes its files to `/opt/oleafly-server`, with your settings in `.env` readable only by root. It never overwrites an existing `.env`.
5. Starts the server from the published image, with Caddy in front for HTTPS.
6. Waits until the server answers, then prints the setup code and what to do next.

To finish, open Oleafly, choose **Add server**, enter your server's address and use the setup code to become its first admin.

If your institution doesn't allow piping a script into a shell, download `install.sh` from the [latest release](https://github.com/Oleafly/oleafly-server/releases/latest), check it against `SHA256SUMS` and run it, or follow the manual steps below.

## What you need

- A Linux machine that stays on. A small virtual machine is enough to start. Keep an eye on its memory and disk as your projects grow.
- A domain name, such as `collab.example.org`, with a DNS record pointing at the machine, and ports 80 and 443 open to it.
- A way for people to sign in: GitHub, your institution's sign-in (OpenID Connect), or an email account the server can send from.

## Other ways to run it

| Option | When to use it |
| --- | --- |
| Docker Compose by hand | Download `docker-compose.yml`, `Caddyfile` and `.env.example` from the [latest release](https://github.com/Oleafly/oleafly-server/releases/latest), fill in `.env`, then run `docker compose up -d`. |
| Coolify | You already run a Coolify server. |
| Render or Railway | You'd rather pay a hosting service than look after a machine. |
| Linux without Docker | A university machine where you can't use Docker. Each server release on the [Oleafly releases page](https://github.com/Oleafly/Oleafly/releases) includes a single Linux program for x86-64 and ARM. |

The [server guide](https://oleafly.com/docs/collaboration/server/) walks through each one.

## Update

Run the installer again with `update`:

```sh
curl -fsSL https://oleafly.com/server/install.sh | sh -s -- update
```

It downloads the new release's files and image, keeps your `.env`, restarts the server and waits until it answers. People connected at the time reconnect by themselves.

## Back up

Everything the server keeps lives in one data folder, or in that folder plus an S3 bucket if you store files in a bucket. [Storage, backups and limits](https://oleafly.com/docs/collaboration/server-operations/) covers backups, a restore drill and continuous copies with Litestream.

## What the server keeps and who can read it

The server keeps accounts, signed-in devices, a security log, server settings and every shared project with its full history.

Projects are not encrypted on the server. Anyone who can read the data folder, the machine's disk or your backups can read every project stored there. Inside Oleafly the rules are stricter: no server role, admin included, can open a project unless its owner added them. Every member's computer also keeps a full copy of each project shared with them.

[Sign-in and access](https://oleafly.com/docs/collaboration/server-access/) covers sign-in providers, access rules, guests and the admin console. The [security page](https://oleafly.com/security/) explains how the server protects sign-ins and changes.

## Get help

- Something went wrong while installing or updating: [open an install problem](https://github.com/Oleafly/oleafly-server/issues/new/choose).
- The server misbehaves once it runs: open a server bug, with the server version and what you saw.
- Not sure how to set something up: ask a question in the issues.

Please don't report security problems in public issues. Follow the [security policy](https://github.com/Oleafly/Oleafly/security/policy) instead.

## Source code

The server's source code lives in the [Oleafly repository](https://github.com/Oleafly/Oleafly), in `crates/oleafly-server`, next to the desktop app it works with. Releases built from it are published here.

## License

Oleafly Server is free software under the [GNU Affero General Public License v3.0](LICENSE).
