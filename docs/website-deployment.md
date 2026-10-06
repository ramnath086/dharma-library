# Website deployment

The repository stays private. The public website is deployed as a Cloudflare Worker with static assets.

## One-time GitHub setup

Add these repository secrets under **Settings → Secrets and variables → Actions**:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

The API token should be scoped only to the Cloudflare account used for this site and have permission to deploy Workers. Keep the token only in GitHub Secrets.

## Automatic flow

After a successful CI run on `main`, the release workflow:

1. Downloads the signed APK produced by CI.
2. Builds the website bundle with the current app version.
3. Creates the GitHub Release tag (only when that version does not already exist).
4. Deploys the website and APK to Cloudflare automatically.

The public APK path is:

`/downloads/dharma-library-latest.apk`

The Worker name is `dharma-library-website`.

No scripture content is changed by the website/release workflow.
