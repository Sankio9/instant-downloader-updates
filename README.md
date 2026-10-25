# Instant Downloader — Official Update Feed

This public repository distributes **code-only update packages** for Instant Downloader. Development sources remain in the separate private repository `Sankio9/instant-downloader`.

## Preview (RC) channel — active

- [Update manifest](https://raw.githubusercontent.com/Sankio9/instant-downloader-updates/main/latest.json)
- [Current ZIP package](https://raw.githubusercontent.com/Sankio9/instant-downloader-updates/main/releases/Instant_Downloader_v1.8_RC7_code_only.zip)
- Current published version: **1.8.0-rc.7** (preview, not stable).
- The manifest contains an SHA-256 digest, verified against the uploaded package by the release workflow.

## First activation on older installations

RC5–RC7 were shipped before the HTTPS feed was configured. Their local `config.json` must receive these two settings **once** (preserve all other configuration keys):

```json
{
  "updateManifestSource": "https://raw.githubusercontent.com/Sankio9/instant-downloader-updates/main/latest.json",
  "updateChannel": "rc"
}
```

After this activation, use **Instant Downloader → Updates → Check for updates → Install update** for a *newer* preview release. If RC7 is already installed and latest.json advertises RC7, the application should display “up to date.”

## Safety

Never upload Skool sessions, cookies, user configs, archived lessons, videos or personal information to the update repository. A public update channel is required because the app must fetch releases over HTTPS without GitHub account tokens. Release files are code-only. Stable releases must pass real Windows install and download testing.
