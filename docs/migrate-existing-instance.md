# Migrate an existing instance to Scalingo

This guide moves a Vaultwarden you already run, for example at a hosting company, onto an app made from this repository. It starts with what to ask your provider, because the data you do not get cannot be recovered later.

## Before you start

The migration keeps accounts, vaults, organisations, attachments, Sends and two-factor setups. Devices stay logged in only if three things are unchanged: the `DOMAIN` setting, the signing key `rsa_key.pem`, and the data. Vaultwarden signs its login tokens with that key and names the `DOMAIN` origin as their issuer ([`src/auth.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/auth.rs#L54-L67), tag 1.37.5), so a different key or a different address logs every device out once. The same address should also keep two-factor keys (passkeys, WebAuthn) working: that is an assumption, check it in the rehearsal.

Two things to know:

- Converting a SQLite or MySQL/MariaDB database to PostgreSQL is documented upstream, which calls it "unsupported" and says it "has not been robustly tested" ([Using the PostgreSQL Backend](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-PostgreSQL-Backend)). Back up first, and rehearse.
- The rehearsal (the whole migration into a throwaway app) and the cutover (switching the real address) are your acts. Nothing in this repository runs them for you.

Check the versions of the source and of this project before anything else: see [Check the versions](#check-the-versions).

## What to ask your hosting provider

Send this message as it is. The `<...>` parts are yours to fill in.

> Hello,
>
> We are moving our Vaultwarden instance to another platform and we need the following. Please answer each numbered point, even with "none". Send secrets through an encrypted channel.
>
> 1. The Vaultwarden version we run, and the database it uses: SQLite, PostgreSQL or MySQL/MariaDB, with the database server version.
> 2. If you can, stop the instance, then give us a consistent copy of the database:
>    - SQLite: a copy made with `sqlite3 <database file> ".backup '<new file>'"`, not a copy of the running file.
>    - PostgreSQL: a dump made with `pg_dump --format=custom --no-privileges <database>`.
>    - MySQL or MariaDB: a full dump of the Vaultwarden database made with `mysqldump`.
> 3. These items from the Vaultwarden data folder, with their sub-folders:
>    - every file whose name starts with `rsa_key` (this is the signing key: without it, every user is logged out);
>    - the folder `attachments/`;
>    - the folder `sends/`;
>    - the file `config.json`, if it exists;
>    - if you changed the settings `RSA_KEY_FILENAME`, `ATTACHMENTS_FOLDER` or `SENDS_FOLDER`: their values, and the key file and the folders they name instead of the ones above.
> 4. Where the attachments and the Sends are stored: on the server's disk, or in an S3 bucket (then the bucket name and the prefix).
> 5. The address the instance answers on (the `DOMAIN` setting), and the settings that are not default: mail server (host, port, sender; not the password), whether signups, invitations, emergency access, push notifications, Duo or Yubico are used.
> 6. When we agree on a date: stop the instance (stop it, do not delete it), give us a last copy of items 2 and 3 taken after the stop, and keep the instance and its data untouched for at least 30 days after the switch.
>
> You do not need to send: the folders `icon_cache/` and `tmp/`, the file `db.sqlite3-shm`, the admin token, or any log.
>
> Thank you.

Where each request comes from:

- Point 2, SQLite: the `.backup` command uses SQLite's online backup API, which the wiki recommends for a database that may be in use ([Backing up your vault](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault), [SQLite command-line shell](https://www.sqlite.org/cli.html)).
- Point 2, PostgreSQL: `--format=custom` and `--no-privileges` are options of `pg_dump`. The message leaves out `--no-owner`: the same page says it is ignored with `--format=custom` ([pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)).
- Point 2, MySQL or MariaDB: `mysqldump` is the dump client; MariaDB's own is `mariadb-dump`, formerly `mysqldump` ([MariaDB documentation](https://mariadb.com/kb/en/mysqldump/)). The message names no option: your provider knows how it runs its server.
- Point 3: the data folder items and what each is for ([Backing up your vault](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)). The wiki marks `sends/` optional; this guide asks for it so that existing Sends keep working. The wiki lists several `rsa_key*` files. In 1.37.5 only `rsa_key.pem` is read, and when it is missing a new key is generated and written ([`initialize_keys`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/auth.rs#L74-L95)); the message asks for every file starting with `rsa_key` so that nothing is left behind. In 1.37.5 the key file name and the attachments and Sends folders can be changed (`RSA_KEY_FILENAME`, `ATTACHMENTS_FOLDER`, `SENDS_FOLDER`: [`src/config.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/config.rs#L527-L535)), so the message also asks for their values: a provider who renamed the key would otherwise have no file starting with `rsa_key`, and every user would be logged out without notice.

### If this is missing

| Item | If it is missing |
| --- | --- |
| Database copy | Missing: nothing can be migrated, use [the per-user fallback](#if-the-provider-gives-you-nothing). Older than the stop: accounts, vaults, organisations, two-factor setups and devices are as of the date of the copy, and nothing created after it exists. |
| rsa_key files | A new signing key is created silently at the first start. Every device and web session is logged out once, and open invitations stop working. The data is intact. |
| attachments/ | Items keep their attachment entries, but downloading an attachment fails. |
| sends/ | Sends that carry a file still exist, but downloading the file fails. Text Sends are not affected. |
| config.json | The settings saved from the admin page are lost. The values set as environment variables on the app apply. |
| Vaultwarden version | STOP. The version rule in "Check the versions" cannot be applied, and a rehearsal does not prove it: do not rehearse or cut over until the provider gives the version. |
| Same DOMAIN | Devices are logged out and must be given the new server URL; passkeys and WebAuthn keys, and email links, of the old address stop working (check this in the rehearsal). |

The `rsa_key` row follows the wiki, which says deleting these files logs each user out and invalidates open invitation tokens ([Backing up your vault](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)), and the source above.

### Keep the copies secret

- Send nothing by email unencrypted: ask for an encrypted channel, as the message does.
- The database copy and `rsa_key.pem` are secrets: the copy holds password hashes and two-factor data (the `users` and `twofactor` tables, [schema](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/migrations/postgresql/2019-09-12-100000_create_tables/up.sql)), and the wiki says `rsa_key.pem` could be used to forge login sessions. `config.json` can hold the admin token and mail credentials (wiki, same page as above).
- Delete these copies after the cutover.

### What you do not need

- `icon_cache/`: cached site icons, "probably not worth backing up" ([Backing up your vault](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)).
- `tmp/`: Vaultwarden's temporary files; this app keeps them on its local disk ([`scripts/start.sh`](https://github.com/incubateur-territoires/vaultwarden-scalingo/blob/main/scripts/start.sh)).
- `db.sqlite3-shm`: the wiki says you do not need to back it up or restore it (same page).
- The source's `ADMIN_TOKEN`: the new app has its own, set in its environment.

## If the provider gives you nothing

If the provider will not hand over the data, or you cannot reach it, each user migrates alone:

1. Each user exports their vault as an encrypted JSON that is password protected, or as the `.zip (with attachments)` when the client offers it, and imports the file into an account they create on the new instance. An encrypted JSON that is "account restricted" can only be imported into the account that made it, so it is of no use here.
2. Each organisation owner exports the organisation separately: an individual export does not include organisation-owned items.

Source: [Bitwarden, export your data](https://bitwarden.com/help/export-your-data/). The help says that, unless an export is encrypted, you must not store or send it over insecure channels such as email, and must delete it immediately after use. It does not list the `.zip` as encrypted, so treat it that way: do not email it, and delete it right after importing it. The help states what an export contains, not how each client imports it: this guide does not promise that an attachments zip imports on a given client, so test it in the rehearsal.

What is lost this way:

- Sends and the trash: the help says no export format includes them.
- The structure of an organisation, unless an owner exports it and imports it again.
- Attachments, unless the zip format is used (the help says it only covers an individual vault).
- Two-factor setups: each user sets them up again.
- Logged-in devices: every device is logged out.
- Account recovery and emergency access: set them up again. The export help does not list them among what an export contains.

## Check the versions

The target must not be older than the source. Vaultwarden updates the database schema at every start and cannot undo it, so an older Vaultwarden cannot read a database a newer one has changed.

Target version: the `VAULTWARDEN_VERSION` line of [`VERSIONS`](https://github.com/incubateur-territoires/vaultwarden-scalingo/blob/main/VERSIONS) on the `main` branch of this repository. Until the maintainers pin the next release, `VERSIONS` can name a newer version than the one your app runs: the line `Starting Vaultwarden <version>` in your app's logs is the one that counts. The app prints it at each start ([`scripts/start.sh`](https://github.com/incubateur-territoires/vaultwarden-scalingo/blob/main/scripts/start.sh)); read it with `scalingo --app <app> logs -n 1000` ([Scalingo CLI, "Read and watch the logs"](https://doc.scalingo.com/tools/cli/features)). The rehearsal checks that line against the source version.

Source version: the answer to point 1.

- If the source is newer than the target, stop: wait for the maintainers' next release. Do not edit `VERSIONS` yourself.
- Same version: go on.
- The target is newer: for a PostgreSQL source this is fine, Vaultwarden updates the schema at its first start. For SQLite and MySQL the data is loaded without Vaultwarden's own upgrade steps: ask your provider to upgrade the source to the target version first, or prove it in the rehearsal.
- Version unknown, or newer than the target: stop. Ask the provider for the version, and if it is newer, wait for a release at least as new.

Why this rule exists: the migrations are embedded in the program and run at every start ([`DbPool::from_config`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/mod.rs#L182-L206), [`run_pending_migrations`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/mod.rs#L480-L533)), and the program only ever runs them forward. The rule is derived from that: upstream does not state it. For SQLite and MySQL the load is data only, so it skips the data changes some migrations make: that is our inference, not stated upstream, which is why an equal version is the safe case. The README says the same of an upgrade: [Upgrade](../README.md#upgrade).
