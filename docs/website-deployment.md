# Website deployment

The repository is public and the website is deployed with GitHub Pages. Android APK binaries are published as GitHub Release assets, so the large APK is not copied into the Pages site.

## Automatic flow

After a successful CI run on `main`, the release workflow:

1. Downloads the signed APK produced by CI.
2. Creates the GitHub Release tag when that version does not already exist.
3. Uploads the versioned APK and a `dharma-library-latest.apk` asset to that release.
4. Generates `version.json` for the website.
5. Deploys the static `website/` directory to GitHub Pages.

The download page reads `version.json` and links directly to the latest GitHub Release APK.

No scripture content is changed by the website/release workflow.
