# Deploy Vaultwarden on Scalingo

[![Deploy](https://cdn.scalingo.com/deploy/button.svg)](https://my.scalingo.com/deploy?source=https://github.com/incubateur-territoires/vaultwarden-scalingo)

Vaultwarden is an unofficial, lightweight server compatible with Bitwarden clients.

## Before you deploy

You need:

- a Scalingo account;
- an S3-compatible bucket, and an access key that can read and write that bucket only. Scalingo has no S3 add-on: you bring the bucket (the examples use Scaleway Object Storage, any provider works).

Why the bucket: Scalingo's disk is erased at every restart, so attachments, Sends and the signing key cannot live on it.

Supported stacks: `scalingo-24` and `scalingo-26`. `scalingo-22` is deprecated and not supported.

## One-click deployment

Click the button at the top and fill the form. It asks for six values:

| Field | What to enter |
| --- | --- |
| `DOMAIN` | The public HTTPS address of the app, for example `https://my-vault.osc-fr1.scalingo.io` (use the app name you chose). |
| `S3_BUCKET` | The name of your bucket. |
| `S3_ENDPOINT` | The S3 endpoint of your provider, for example `https://s3.fr-par.scw.cloud`. |
| `S3_REGION` | The region of the bucket, for example `fr-par`. |
| `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` | The access key and its secret. |

The form also shows three settings with a default: `ADMIN_TOKEN` (generated for you), `SIGNUPS_ALLOWED` (`true`) and `S3_PATH_STYLE` (`false`; set it to `true` if your provider needs `https://endpoint/bucket` addresses).

Open the app URL, click Create account.

To use your own domain, follow the [Scalingo custom domain guide](https://doc.scalingo.com/platform/app/domain), then set `DOMAIN` to the new address and restart the app.

## Storage

- PostgreSQL (the Scalingo add-on) holds the accounts and the encrypted vault items.
- The S3 bucket holds, under the prefix `vaultwarden/`, the attachments, the Sends, the icon cache, the signing key and the settings you save in the admin page (`config.json`).

Enable versioning on the bucket. Never delete the prefix `vaultwarden/`: it contains the signing key, and deleting it logs everyone out.

## First admin and users

- The admin page is at `<DOMAIN>/admin`. Its token is the `ADMIN_TOKEN` variable, in the environment of the app in the Scalingo dashboard. To rotate it, change the variable and restart. The token is stored in clear text, which Vaultwarden warns is weaker than a hashed token. Leave it empty to disable the admin page.
- Register your own account first, then set `SIGNUPS_ALLOWED=false` so nobody else can create one.
- Invite the other users from `/admin`. If you closed signups before creating any account, set `SIGNUPS_ALLOWED=true` again for a moment, or invite from `/admin`.
- Moving from another Vaultwarden or Bitwarden instance: export your vault there and import it here. This is yours to do, nothing migrates automatically.

## Connect a Bitwarden client

In the Bitwarden app or browser extension, open the login screen, choose Settings (the gear), then Self-hosted, and set Server URL to your `DOMAIN`.

## Upgrade

New versions arrive as pull requests in this repository, and the maintainer merges them:

1. A pull request named `chore(deps): bump Vaultwarden from A to B` updates the upstream versions. Once it is merged, the maintainer publishes a release.
2. The release is built and checked on both stacks, then a second pull request, `chore(release): deploy <tag> ...`, pins it. Once the maintainer has merged it, the new version is on the `main` branch and your app can take it.

To take it, with the [Scalingo CLI](https://doc.scalingo.com/tools/cli/start) and your app name in place of `<app>`:

1. Take a PostgreSQL backup first. Database migrations run automatically at start and cannot be reversed.

   ```
   scalingo --app <app> --addon postgresql backups-create
   ```

   Then count the migrations the database has already run, and write the number down: it is how you will know, after a failed deployment, whether a migration ran. Open the database console with `scalingo --app <app> pgsql-console`, run this query, and leave with `\q`:

   ```
   SELECT count(*) FROM __diesel_schema_migrations;
   ```

2. Deploy the `main` branch of this repository to your app:

   ```
   scalingo --app <app> deploy https://github.com/incubateur-territoires/vaultwarden-scalingo/archive/refs/heads/main.tar.gz
   ```

   Restarting the app or redeploying its last deployment does not upgrade it: both reuse the version already deployed. This command is how Scalingo documents [updating an app created with the deploy button](https://doc.scalingo.com/platform/deployment/one-click-deploy#update-the-application).

If the deployment fails, Scalingo keeps the previous version running ([boot errors](https://doc.scalingo.com/platform/app/troubleshooting/boot-errors)), and the app is not down. But the new version may have started a migration before it failed, so the old version can be running against a database that has already changed. To roll back:

1. Find out whether a migration ran. Vaultwarden does not say: it applies the pending migrations silently when it starts, and a failure is the only thing it reports (`Error running migrations`, in the application logs: `scalingo --app <app> logs --lines 200`). So ask the database. Run the query of the backup step again, in `pgsql-console`: if the count is higher than the number you wrote down, a migration ran.
2. If the count is the same, no migration ran:
   - for a build error, or one of the start messages in Troubleshooting, nothing else changed either: fix the cause (the deployment logs are `scalingo --app <app> deployment-logs`) and deploy again;
   - for `Error running migrations`, do not restore: each migration runs in its own transaction, so the one that failed left nothing behind, and a restore would only lose what users saved for nothing. Do not deploy again either: it would fail the same way, for example because a table the migration creates is already there, left by an earlier restore (a restore does not empty the database, see step 3). Stop there: the old version keeps running, so nothing is down. Contact the maintainer of this repository, or Scalingo support (support@scalingo.com), and send them the logs;
   - for any other failure, go to step 3: the count only records migrations, and Vaultwarden also rewrites some data when it starts (two-factor entries, for example), which the count does not show.
3. If the count is higher, if you did not write it down, or if step 2 sent you here, restore the backup and start the app again, without deploying. This is the safe choice when you cannot tell.
   - Stop the app first. Scalingo requires the database to be completely stopped while a backup is restored ([restoring](https://doc.scalingo.com/databases/postgresql/shared-resources/guides/restoring)), and a restore under a running app would let users write into tables while it reloads them: what they write into a table the restore has not reached yet is overwritten, and what they write into a table it has already reloaded survives, so the database would match no single moment. Note the number of `web` containers, in the `AMOUNT` column (`n` below), then scale the app to 0 and wait for it to finish:

     ```
     scalingo --app <app> scale
     scalingo --app <app> scale --synchronous web:0
     ```

   - [Restore the database backup](https://doc.scalingo.com/databases/postgresql/shared-resources/guides/restoring) you took before the upgrade, and, see Backups, the bucket from the same moment. Everything written after the backup is lost, such as items created or edited, new accounts and changed passwords, including what users saved while the old version kept running. The sooner you restore, the less is lost. The app is down from the scale-down to the scale-up below.
   - The restore does not empty the database. Scalingo's procedure runs `pg_restore --clean --if-exists`, which only drops and recreates what the backup contains: a table created by the failed upgrade stays. The next upgrade may then fail with `Error running migrations` while the count is unchanged. If that happens, see step 2: do not restore again, because the backup you took before that upgrade holds the same table, and do not deploy again. Scalingo's documentation gives no command to empty the database.
   - Scale the app back to the number you noted, and do not deploy again. Scalingo kept the previous version as the running release, so the containers started now run it against the restored database, and no migration runs again ([scaling](https://doc.scalingo.com/platform/app/scaling)). Run `scalingo --app <app> scale` to check that the `web` line shows your number again.

     ```
     scalingo --app <app> scale --synchronous web:<n>
     ```

Scalingo itself warns that a rollback after a migration can create more problems than it solves ([rolling back](https://doc.scalingo.com/platform/app/rollback)): the backup is what you rely on.

## Backups

- PostgreSQL: use the Scalingo backups of the add-on.
- S3: keep versioning enabled on the bucket.

A restore needs both from the same moment: the database and the bucket must agree.

## Optional settings

Set these as environment variables of the app. None is in the deploy form.

| Variable | Meaning |
| --- | --- |
| `SMTP_HOST` | Mail server, to send invitations and password hints. |
| `SMTP_FROM` | Sender address of those emails. |
| `SMTP_PORT` | Mail server port, for example `587`. |
| `SMTP_USERNAME` | Mail server user. |
| `SMTP_PASSWORD` | Mail server password. |
| `DATABASE_MAX_CONNS` | Maximum database connections. Default `5`, which fits the starter PostgreSQL plans. Raise it with a bigger plan. |

## Troubleshooting

Messages starting with ` !     ` come from this repository's scripts: the last four rows appear in the build log, the two before them in the application logs. S3 problems are only visible in the application logs (`scalingo logs`), at start or at the first file write.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Bucket unreachable: the log shows an S3 error such as `NoSuchBucket`, and attachments fail to upload | The bucket does not exist, or its name is wrong | Fix `S3_BUCKET` and restart. |
| Wrong credentials: the log shows `AccessDenied`, `InvalidAccessKeyId` or `SignatureDoesNotMatch` | The access key is wrong, or may not use this bucket | Fix `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and check the key can read and write the bucket. |
| Wrong endpoint: the log shows a connection, DNS or redirect error | The endpoint or the region is not the one of the bucket | Fix `S3_ENDPOINT` and `S3_REGION`; try `S3_PATH_STYLE=true` if your provider needs it. |
| NO DATABASE_URL FOUND! Please provision a PostgreSQL addon. | The app has no PostgreSQL add-on, or it is still provisioning | Add a PostgreSQL add-on, wait for it, restart. |
| DOMAIN is not set, or DOMAIN must start with https:// | `DOMAIN` is missing or does not start with `https://` | Set `DOMAIN` to the public HTTPS address of the app. |
| VERSIONS pins no release yet (RELEASE_TAG is empty). | No release of this repository is pinned in `VERSIONS` | The maintainer publishes a release and merges the pin pull request. |
| Could not download `<url>`. Check that release `<tag>` exists and has its assets. | The pinned release or its assets do not exist | Check the release named in `VERSIONS` exists and has its assets. |
| Checksum mismatch for `<asset>`: expected `<pin>`, got `<actual>`. Refusing to install. | The downloaded file is not the one that was pinned, so it is not installed | Do not work around it: check the release assets, or ask the maintainer. |
| The Vaultwarden binary does not run on stack `<stack>`. Supported stacks: scalingo-24, scalingo-26. | The app is on an unsupported stack, or the pinned release holds a binary that fails on a supported one | If the stack is not `scalingo-24` or `scalingo-26`, move the app to one of them ([Scalingo stacks](https://doc.scalingo.com/platform/internals/stacks/overview)). If it is, the release is faulty: do not work around it, ask the maintainer. |

## Security

Keep this instance up to date: Vaultwarden publishes security fixes regularly.
