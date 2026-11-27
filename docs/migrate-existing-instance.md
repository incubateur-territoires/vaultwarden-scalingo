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

## Rehearse first

The rehearsal is the whole migration done once into a throwaway app, so that the cutover is a repetition. Do it on a copy of the data, and never with the real `DOMAIN`: until the cutover, the real address must keep answering from the source, and two live instances cannot share one.

Create the throwaway app with the deploy button, as the README says ([One-click deployment](../README.md#one-click-deployment)), and give it:

- a `DOMAIN` of its own, of the form `https://<throwaway-app>.osc-fr1.scalingo.io`;
- a bucket of its own: the app always stores its files under the prefix `vaultwarden/` of its bucket ([`scripts/start.sh`](https://github.com/incubateur-territoires/vaultwarden-scalingo/blob/main/scripts/start.sh)), so a second prefix in the real bucket is not possible, and the rehearsal must not touch real data;
- `SIGNUPS_ALLOWED=false`: the form proposes `true` ([`scalingo.json`](https://github.com/incubateur-territoires/vaultwarden-scalingo/blob/main/scalingo.json)).

Then do each step below, in order, on the copies the provider gave you: [Load the database](#load-the-database), [Copy the files to the bucket](#copy-the-files-to-the-bucket), [Set the settings](#set-the-settings). The checks that follow tell you the rehearsal is done.

### Rehearsal checks

1. Read the line `Starting Vaultwarden <version>` in the logs (`scalingo --app <app> logs -n 1000`) and compare it with the version of the source: the target must not be older (see [Check the versions](#check-the-versions)). If you uploaded a `config.json`, look for the warning `[WARNING] The following environment variables are being overridden by the config.json file.` ([`src/config.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/config.rs#L299-L303)): note whether it is there, and read the settings it lists.
2. Log in to the web vault of the throwaway app as a user of the source, with the same master password, and compare the number of items with the source's.
3. Download an attachment and the file of a Send that exist on the source. For a Send, use its link with the address of the throwaway app in place of the source's: not verified, try it.
4. Log in as a user who has two-factor authentication, with the method they already use. A security key or a passkey registered for the address of the source is not expected to work on another address: Vaultwarden derives the WebAuthn identity from `DOMAIN` ([`webauthn.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/api/core/two_factor/webauthn.rs#L36-L41)). Check those at the cutover.
5. Open the organisations as an owner, and compare the organisation, its collections and its members with the source's.
6. Skip this one in the rehearsal and do it at the cutover. It would show that a Bitwarden client that was logged in to the source stays logged in when its server URL already equals the target's `DOMAIN`, which proves that the key and `DOMAIN` were kept. The throwaway app has another `DOMAIN`, so it cannot show it. At the cutover, make it the first step of the verification, with the rollback as the safety net.
7. Write down how long each step took, for the cutover plan.

If the target is newer than a SQLite or MySQL source, checks 2 to 5 are the proof that [Check the versions](#check-the-versions) asks for.

## Load the database

Use the sub-section of the database type the provider named in point 1. If you do not know it, stop and ask: this guide has no way to guess it.

These steps are the same for every type. The commands use the [Scalingo CLI](https://doc.scalingo.com/tools/cli/features) and your app name in place of `<app>`.

- **Stop the web process while the data loads**, and start it after, as the README does for a restore ([Upgrade](../README.md#upgrade)). Note first the number of `web` containers (`scalingo --app <app> scale`, column `AMOUNT`) and use it for `<n>`. `--synchronous` waits until the change is done ([CLI source](https://github.com/Scalingo/cli/blob/1640dd5/cmd/scale.go#L20)).

  ```
  scalingo --app <app> scale --synchronous web:0
  scalingo --app <app> scale --synchronous web:<n>
  ```

- **Check that the target holds no accounts.** This guide does not merge two sources: a load adds to what is there. Open the console with `scalingo --app <app> pgsql-console` ([Accessing](https://doc.scalingo.com/databases/postgresql/shared-resources/getting-started/accessing)), run this query, expect `0`, and leave with `\q`:

  ```
  SELECT count(*) FROM users;
  ```

- **Compare the row counts after the load.** Run this query in `pgsql-console` on the target, and on the source's copy (each sub-section says how). The five tables hold the accounts, the vault items, the organisations, the attachments and the Sends, and exist in [`src/db/schema.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/schema.rs). The query is plain SQL that SQLite, MySQL, MariaDB and PostgreSQL all run. If a number differs, stop: do not go on, do not cut over.

  ```
  SELECT 'users', count(*) FROM users UNION ALL SELECT 'ciphers', count(*) FROM ciphers UNION ALL SELECT 'organizations', count(*) FROM organizations UNION ALL SELECT 'attachments', count(*) FROM attachments UNION ALL SELECT 'sends', count(*) FROM sends;
  ```

- **Open the tunnel.** Every load reaches the target's database from your workstation through a tunnel, which needs the SSH key of your Scalingo account ([Accessing](https://doc.scalingo.com/databases/postgresql/shared-resources/getting-started/accessing)). Leave this command running in its own terminal; `CTRL+C` closes the tunnel, and the default local port is `10000`. The user, the password and the database name are in the URL that `scalingo --app <app> env-get SCALINGO_POSTGRESQL_URL` prints ([Connecting](https://doc.scalingo.com/databases/postgresql/shared-resources/getting-started/connecting)). Open the tunnel again whenever that URL changes. Whether pgloader works through the tunnel, and whether the add-on's plan allows its connections, is not verified: the rehearsal proves it.

  ```
  scalingo --app <app> db-tunnel SCALINGO_POSTGRESQL_URL
  ```

**Back up before a SQLite or MySQL load**, so that a failed load can be redone. `backups-create` waits until the backup is finished ([CLI source](https://github.com/Scalingo/cli/blob/1640dd5/db/backup_create.go#L16-L54)). The PostgreSQL source has no backup: its add-on is replaced.

```
scalingo --app <app> --addon postgresql backups-create
```

**Restore the backup** after a failed SQLite or MySQL load. The CLI has no command that restores a backup: its features page lists `backups` and `backups-download` only ([CLI features](https://doc.scalingo.com/tools/cli/features)). Scalingo's procedure is to download the backup, unpack it and run `pg_restore` ([Restoring a database](https://doc.scalingo.com/databases/postgresql/shared-resources/guides/restoring)), with the web process stopped and the tunnel open. The last command is the one of [PostgreSQL source](#postgresql-source), with the unpacked backup as the file:

```
scalingo --app <app> --addon postgresql backups
scalingo --app <app> --addon postgresql backups-download --backup <backup-id>
tar -xvzf <archive>
```

### PostgreSQL source

A restore with `--clean --if-exists` only drops and recreates what the dump contains ([Upgrade](../README.md#upgrade)), and Vaultwarden has already created its tables in the target's database when the app first started. A dump older than the target would leave the tables of the newer migrations in place, next to the dump's own list of migrations, and the next start would fail on tables that already exist. This is our reading of how the restore works, not something tested. So this source is always loaded into a fresh add-on, and the version rule of [Check the versions](#check-the-versions) (target at least as new as the source) is the only one. The procedure is not verified: the rehearsal proves it.

1. Check that the target holds no accounts (the query above), then stop the web process.
2. Replace the add-on. `addons` lists its ID and its plan. `addons-remove` asks you to type the ID, and destroys the add-on and its data ([CLI source](https://github.com/Scalingo/cli/blob/1640dd5/addons/destroy.go#L31-L44)). `addons-add` takes the same plan; Scalingo then sets `SCALINGO_POSTGRESQL_URL` and `DATABASE_URL` again ([Provisioning](https://doc.scalingo.com/databases/postgresql/shared-resources/getting-started/provisioning), [Connecting](https://doc.scalingo.com/databases/postgresql/shared-resources/getting-started/connecting)). Wait until the add-on is provisioned (a few seconds, says Scalingo), then open the tunnel again.

   ```
   scalingo --app <app> addons
   scalingo --app <app> addons-remove <addon-id>
   scalingo --app <app> addons-add postgresql <plan>
   ```

3. Compare the PostgreSQL version of the source (point 1 of the message) with the new add-on's: run `select version();` in `pgsql-console`. Scalingo provisions the default version, the latest 18 at the time of writing, and another one only through its support ([PostgreSQL versions](https://doc.scalingo.com/databases/postgresql/about/overview)). A dump is expected to load into a server of the same or a newer major version, and is not guaranteed to load into an older one ([`pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html), Notes). If the source is newer, stop and ask Scalingo's support.
4. Restore the dump into the empty database: this is Scalingo's own command, run from your workstation ([Restoring a database](https://doc.scalingo.com/databases/postgresql/shared-resources/guides/restoring)). Use a `pg_restore` at least as new as the `pg_dump` that made the dump (`pg_restore --version`): this is a precaution, the PostgreSQL pages do not state it. `--clean` drops what is there, which is nothing in a fresh add-on.

   ```
   export SCALINGO_DATABASE_URL="postgresql://<user>:<password>@127.0.0.1:10000/<dbname>"
   pg_restore --clean --if-exists --no-owner --no-privileges --no-comments --dbname "${SCALINGO_DATABASE_URL}" <dump_file>
   ```

5. Start the web process. Vaultwarden runs the migrations the dump lacks at its first start ([Check the versions](#check-the-versions)).

Check: the row counts of the five tables equal the ones your provider counted on its database when it made the dump (ask for them: the message does not), and the log, `scalingo --app <app> logs -n 1000`, shows `Starting Vaultwarden <version>` and no `Error running migrations` ([`src/db/mod.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/mod.rs#L533)).

If it fails: do not retry on top. Repeat steps 2 to 5: removing the add-on and adding a new one gives an empty database each time. If the same dump fails again, ask your provider for a new one.

### SQLite source

Upstream documents this conversion and calls it unsupported and not robustly tested. Back up first, and rehearse. ([Using the PostgreSQL Backend](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-PostgreSQL-Backend), "Migrating from SQLite to PostgreSQL".) The steps below are the wiki's, with Scalingo's tunnel in place of a local server.

1. Take the `.backup` copy of point 2 of the message, and work on a copy of it. If the provider sent a straight copy with a `db.sqlite3-wal` file, keep the two together under matching names, as the wiki says ([Backing up your vault](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)): loading only the main file loses the recent writes.
2. Turn the write-ahead log off on your copy ([Running without WAL](https://github.com/dani-garcia/vaultwarden/wiki/Running-without-WAL-enabled#1-disable-wal-on-old-db)). Open the copy with `sqlite3 <copy>`, type the line below (the answer is `delete`), then `.quit`:

   ```
   PRAGMA journal_mode=delete;
   ```

3. Let the target create its tables, and do nothing else: the app must have started once on its empty database (no account created, nobody logged in), and then be stopped ([wiki](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-PostgreSQL-Backend), step 3). An app made with the button has done it. To check, run this query in `pgsql-console` and expect more than `0` (the README uses it: [Upgrade](../README.md#upgrade)):

   ```
   SELECT count(*) FROM __diesel_schema_migrations;
   ```

4. Stop the web process, check that the target holds no accounts, take the backup, open the tunnel (all above).
5. Install [pgloader](https://pgloader.readthedocs.io/en/latest/install.html) and write `bitwarden.load`, as the wiki gives it (read on 2026-11-27: check the wiki for a newer version of this file). Replace the `<...>` parts: the path of your copy, the user, password and database name of the target, and the tunnel's port.

   ```
   load database
        from sqlite:///<path of the copy>
        into postgresql://<user>:<password>@127.0.0.1:<port>/<dbname>
        WITH data only, include no drop, reset sequences
        EXCLUDING TABLE NAMES LIKE '__diesel_schema_migrations'
        ALTER SCHEMA 'bitwarden' RENAME TO 'public'
   ;
   ```

   The file excludes the list of migrations, so the target keeps its own. In pgloader's code the tables of a SQLite file have no schema of their own ([`sqlite.lisp`](https://github.com/dimitri/pgloader/blob/v3.6.10/src/sources/sqlite/sqlite.lisp#L82)), so the `ALTER SCHEMA` line probably changes nothing: it is kept as upstream gives it.

6. Run `pgloader bitwarden.load` ([command line](https://pgloader.readthedocs.io/en/latest/pgloader.html)). The wiki says you may see warnings and that the load should complete. Then start the web process.

Check: the row counts of the five tables on the target equal the ones of your copy: run the query above with `sqlite3 <copy> "<query>"` ([SQLite shell](https://www.sqlite.org/cli.html)).

If it fails: pgloader reports errors, not only warnings: restore the target backup you took before the load (see "Restore the backup" above) and run the load again from the beginning. If the row counts differ from the source: do not go on. Restore the backup, and load again from a fresh copy.

### MySQL or MariaDB source

Upstream documents this conversion and calls it unsupported and not robustly tested. Back up first, and rehearse. ([Using the PostgreSQL Backend](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-PostgreSQL-Backend), "Migrating from MySQL to PostgreSQL".) pgloader reads a running database, not a dump file, so the dump goes first into a throwaway local server of the same family and version as the source (point 1 of the message).

1. Start the local server with Docker, in the family of your source ([MySQL image](https://github.com/docker-library/docs/blob/master/mysql/README.md), [MariaDB image](https://github.com/docker-library/docs/blob/master/mariadb/README.md), [`docker run`](https://docs.docker.com/reference/cli/docker/container/run/)). The database is named `vaultwarden`, and the port is published on your machine only ([port publishing](https://docs.docker.com/engine/network/port-publishing/)). For MariaDB, use the image `mariadb:<version>` and the variables `MARIADB_ROOT_PASSWORD` and `MARIADB_DATABASE`.

   ```
   docker run --name vaultwarden-source-copy -e MYSQL_ROOT_PASSWORD=<password> -e MYSQL_DATABASE=vaultwarden -p 127.0.0.1:3306:3306 -d mysql:<version>
   ```

2. Load the dump into it, as the image's page shows ([MySQL image](https://github.com/docker-library/docs/blob/master/mysql/README.md), "Restoring data from dump files"; for the database name, [MariaDB, restoring dumps](https://mariadb.com/docs/server/clients-and-utilities/backup-restore-and-import-clients/mariadb-dump#restoring-dumps)). If it cannot connect, wait a few seconds and run it again. For MariaDB, the client is `mariadb`. If the dump names a database of its own, the tables went there: use that name in step 5, in place of `vaultwarden`.

   ```
   docker exec -i vaultwarden-source-copy sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" vaultwarden' < <dump file>
   ```

3. Let the target create its tables, and do nothing else, as in step 3 of the SQLite source.
4. Stop the web process, check that the target holds no accounts, take the backup, open the tunnel (all above).
5. Install the latest 3.x of [pgloader](https://pgloader.readthedocs.io/en/latest/install.html): the wiki warns that the official Ubuntu package is outdated and fails with newer PostgreSQL, and points to the [PostgreSQL Apt Repository](https://www.postgresql.org/download/linux/ubuntu/). `pgloader --version` shows what you have; pgloader's site also offers a 4.x build, which this guide does not cover. Write `vaultwarden.load`, as the wiki gives it (read on 2026-11-27: check the wiki for a newer version of this file). The `ALTER SCHEMA` name is that of the MySQL database ([pgloader, MySQL](https://pgloader.readthedocs.io/en/latest/ref/mysql.html)). The wiki adds `?sslmode=require` to the PostgreSQL address if the connection needs SSL.

   ```
   load database
        from mysql://<mysql user>:<mysql password>@127.0.0.1:3306/vaultwarden
        into postgresql://<user>:<password>@127.0.0.1:<port>/<dbname>
        WITH data only
        EXCLUDING TABLE NAMES MATCHING '__diesel_schema_migrations'
        ALTER SCHEMA 'vaultwarden' RENAME TO 'public'
   ;
   ```

6. Run `pgloader vaultwarden.load`. The wiki says you may see warnings and that the load should complete; errors mean pgloader is probably outdated. Then start the web process. When the load is checked, remove the local server and its copy of your data: `docker rm --force vaultwarden-source-copy` ([`docker container rm`](https://docs.docker.com/reference/cli/docker/container/rm/)).

Check: the row counts of the five tables on the target equal the ones of the local server: save the query above in `counts.sql` and run it as in step 2, with `< counts.sql` in place of the dump.

If it fails: pgloader reports errors, not only warnings: restore the target backup you took before the load (see "Restore the backup" above) and run the load again from the beginning. First check that pgloader is the latest 3.x. If the row counts differ from the source: do not go on. Restore the backup, and load again from a fresh copy.

## Copy the files to the bucket

The database holds the accounts and the vault; the signing key, the saved settings, the attachments and the Sends are files, and the app reads them from its bucket. Copy them with the AWS CLI ([install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)); another S3 tool does as well, this guide does not cover it. How `aws s3 sync` behaves against each S3 provider is not verified: the rehearsal shows it for yours.

The prefix must be exactly `vaultwarden/`: the app builds its storage address from it ([`scripts/start.sh`](https://github.com/incubateur-territoires/vaultwarden-scalingo/blob/main/scripts/start.sh)), and the README says the same ([Storage](../README.md#storage)). Under it, the app expects `rsa_key.pem`, `config.json`, `attachments/<item id>/<file id>` and `sends/…`, so keep the sub-folders. Do not copy `icon_cache/`: it is not needed. Copy only `rsa_key.pem` of the `rsa_key*` files: it is the only one Vaultwarden 1.37.5 reads ([`initialize_keys`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/auth.rs#L74-L95)).

**Read `config.json` first.** What it holds wins over the app's environment ([`src/config.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/config.rs#L287-L307)), and it can hold secrets: the admin token, the mail password ([wiki](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)). Look for a `domain` key (the keys are the lowercase names of the settings): in the rehearsal it must not name the real address, so remove it from the copy; at the cutover it must equal the real `DOMAIN`. A `signups_allowed` or `admin_token` key overrides the app's `SIGNUPS_ALLOWED` and `ADMIN_TOKEN`. The log tells what it overrode (rehearsal check 1).

Give the AWS CLI the access key of the app and the region of its bucket ([environment variables](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)): `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are the app's, `AWS_REGION` is its `S3_REGION`, and `S3_BUCKET` and `S3_ENDPOINT` are read the same way (`scalingo --app <app> env-get S3_BUCKET`). If the app has `S3_PATH_STYLE=true`, set the addressing style once ([S3 configuration](https://docs.aws.amazon.com/cli/latest/topic/s3-config.html)):

```
export AWS_ACCESS_KEY_ID=<access key>
export AWS_SECRET_ACCESS_KEY=<secret key>
export AWS_REGION=<S3_REGION>
aws configure set default.s3.addressing_style path
```

Copy the two files and the two folders ([`cp`](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html), [`sync`](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html), which copies new and updated files recursively, so running it again is safe; `--endpoint-url` is the S3 endpoint of your provider). If the provider keeps the attachments in a bucket, bring them down first with `aws s3 sync s3://<source bucket>/<prefix>/attachments attachments`, with the source's own `--endpoint-url`.

```
aws s3 cp rsa_key.pem s3://<S3_BUCKET>/vaultwarden/rsa_key.pem --endpoint-url <S3_ENDPOINT>
aws s3 cp config.json s3://<S3_BUCKET>/vaultwarden/config.json --endpoint-url <S3_ENDPOINT>
aws s3 sync attachments s3://<S3_BUCKET>/vaultwarden/attachments --endpoint-url <S3_ENDPOINT>
aws s3 sync sends s3://<S3_BUCKET>/vaultwarden/sends --endpoint-url <S3_ENDPOINT>
```

If the app started before the key was there, it made its own `rsa_key.pem`, and the commands above overwrite it. The key and `config.json` are read only at start, so restart the app ([CLI features](https://doc.scalingo.com/tools/cli/features)); the attachments and the Sends need no restart.

```
scalingo --app <app> restart
```

Check: list the bucket ([`ls`](https://docs.aws.amazon.com/cli/latest/reference/s3/ls.html)) and count: the lines under `vaultwarden/attachments/` and `vaultwarden/sends/` are as many as the files in your two folders, and `vaultwarden/rsa_key.pem` and `vaultwarden/config.json` are there. The app adds its own files, such as `icon_cache/`: leave them.

```
aws s3 ls s3://<S3_BUCKET>/vaultwarden/ --recursive --summarize --endpoint-url <S3_ENDPOINT>
```

If it fails:

- Wrong prefix: downloads of attachments and Sends fail, and nothing changes in the database. The path must be exactly `vaultwarden/`: copy the files again to the right place. Attachments and Sends need no restart; the key and `config.json` do.
- The log shows `Private key '<path>' created correctly` ([`src/auth.rs`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/auth.rs#L94)): the app made a new signing key because it did not find `vaultwarden/rsa_key.pem`. Upload the right file and restart.
- An S3 error in the log (`AccessDenied`, `NoSuchBucket`, a connection error): see Troubleshooting in the [README](../README.md#troubleshooting).

## Set the settings

The provider's answer to point 5 says which settings the source changed. Set them in the environment of the app with `env-set` ([CLI features](https://doc.scalingo.com/tools/cli/features)); it does not restart the app, and says so ([CLI source](https://github.com/Scalingo/cli/blob/1640dd5/env/edit.go#L56-L57)), so restart it after. A value that `config.json` also holds is overridden by `config.json`.

```
scalingo --app <app> env-set SMTP_HOST=<host> SMTP_FROM=<sender> SMTP_PORT=<port>
scalingo --app <app> restart
```

- `DOMAIN`: the same as the source's. In the rehearsal, keep the throwaway app's own.
- `SIGNUPS_ALLOWED`: it stays `false` during the migration.
- The names of the README's [Optional settings](../README.md#optional-settings): `SMTP_HOST`, `SMTP_FROM`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`. The provider did not send the mail password: take it from your own mail account.
- Push notifications, not in the form: `PUSH_ENABLED`, `PUSH_INSTALLATION_ID`, `PUSH_INSTALLATION_KEY` ([`.env.template`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/.env.template#L119-L121), which says the id and the key come from `https://bitwarden.com/host`).
- Yubico, not in the form: `YUBICO_CLIENT_ID`, `YUBICO_SECRET_KEY`, and `YUBICO_SERVER` if you use your own server ([`.env.template`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/.env.template#L576-L578)).
- Duo, not in the form: `DUO_IKEY`, `DUO_SKEY`, `DUO_HOST` ([`.env.template`](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/.env.template#L586-L588)).
