# Kezai Forum

Kezai Forum is the source package for 科仔交流社区. It contains the Discourse plugin used for the forum registration flow, the Android app wrapper, branding assets, and server-side deployment helpers.

## Contents

- `plugin/innox-lan`: Discourse plugin for username/password registration, real-name office profile fields, member IDs, login page, app download route, and branded assets.
- `android`: Android app project for 科仔交流社区.
- `brand`: Source branding images used by the forum and app.
- `server`: Deployment helper files for the Jetson/Discourse host.
- `Kezai-Community-v1.3.apk` and `科仔交流社区-v1.3.apk`: Current Android install package copies.

## Server Notes

The real Cloudflare Tunnel config is intentionally not committed. Start from `server/cloudflared-config.example.yml` and fill in the tunnel ID and credentials path for the target server.

The Discourse app config is in `server/app.yml`. The custom plugin should be mounted into the Discourse container at:

```text
/var/www/discourse/plugins/innox-lan
```

## Android Build

Open the `android` folder with Android Studio, or build from the command line:

```powershell
cd android
.\gradlew.bat assembleRelease
```

The current public forum URL is:

```text
https://kezaiforum.xyz
```

The current LAN fallback URL is:

```text
http://10.10.24.116
```
