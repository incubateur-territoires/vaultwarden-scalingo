# Deploy Vaultwarden on Scalingo

## Upgrade

1. Deploy: `scalingo --app my-app deploy https://github.com/incubateur-territoires/vaultwarden-scalingo/archive/refs/heads/main.tar.gz`
2. Back up: `scalingo --app my-app --addon postgresql backups-create`
3. Roll back with `scalingo --app my-app deploy https://github.com/incubateur-territoires/vaultwarden-scalingo/archive/<previous-commit>.tar.gz`
