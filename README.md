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

Click the button at the top and fill the form. It asks for five things:

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

New versions arrive as pull requests in this repository:

1. A pull request named `chore(deps): bump Vaultwarden from A to B` updates the upstream versions. The maintainer merges it and publishes a release.
2. The release is built and checked on both stacks, then a second pull request, `chore(release): deploy <tag> ...`, pins it.
3. Merge that one, then redeploy your app.

Before you redeploy, take a Scalingo PostgreSQL backup. Database migrations run automatically at start and cannot be reversed.

If an upgrade fails, the app stays down and the old version is not lost:

- if the migration did not run, redeploy the previous commit;
- if it did run, restore the database backup (and, see Backups, the bucket from the same moment), then redeploy the previous commit.

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

Messages starting with ` !     ` come from this repository's scripts. S3 problems are only visible in the application logs (`scalingo logs`), at start or at the first file write.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Bucket unreachable: the log shows an S3 error such as `NoSuchBucket`, and attachments fail to upload | The bucket does not exist, or its name is wrong | Fix `S3_BUCKET` and restart. |
| Wrong credentials: the log shows `AccessDenied`, `InvalidAccessKeyId` or `SignatureDoesNotMatch` | The access key is wrong, or may not use this bucket | Fix `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and check the key can read and write the bucket. |
| Wrong endpoint: the log shows a connection, DNS or redirect error | The endpoint or the region is not the one of the bucket | Fix `S3_ENDPOINT` and `S3_REGION`; try `S3_PATH_STYLE=true` if your provider needs it. |
| NO DATABASE_URL FOUND! Please provision a PostgreSQL addon. | The app has no PostgreSQL add-on, or it is still provisioning | Add a PostgreSQL add-on, wait for it, restart. |
| DOMAIN is not set, or DOMAIN must start with https:// | `DOMAIN` is missing or does not start with `https://` | Set `DOMAIN` to the public HTTPS address of the app. |
| VERSIONS pins no release yet (build) | No release of this repository is pinned in `VERSIONS` | The maintainer publishes a release and merges the pin pull request. |
| Could not download the release (build) | The pinned release or its assets do not exist | Check the release named in `VERSIONS` exists and has its assets. |
| Checksum mismatch (build) | The downloaded file is not the one that was pinned, so it is not installed | Do not work around it: check the release assets, or ask the maintainer. |
| The Vaultwarden binary does not run on stack (build) | The app is on an unsupported stack | Move the app to `scalingo-24` or `scalingo-26`. |

## Security

Keep this instance up to date: Vaultwarden publishes security fixes regularly.
