# Kezai Forum

Kezai Forum is the source package for 科仔交流社区. It contains the Discourse plugin used for the forum registration flow, the Android app wrapper, branding assets, and server-side deployment helpers.

## Contents

- `plugin/innox-lan`: Discourse plugin for username/password registration, real-name office profile fields, member IDs, AI-approved anonymous posts, local content moderation, opt-in public-chat AI replies, login page, app download route, and branded assets.
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

After the plugin is loaded, run `server/enable_anonymous_community.rb` once in the production Discourse environment. It creates the “匿名社区” category, enables anonymous identity switching for registered members, lets the local safety model approve safe anonymous posts and reject unsafe ones, exposes the approved member profile fields to signed-in members, and enables forum and chat direct messages. If the safety model is unavailable, anonymous posts fail closed into the staff review queue. `server/verify_anonymous_community.rb` performs a rollback-only acceptance check without leaving test accounts or messages behind.

Run `server/enable_ai_chat.rb` after the general `qwen3:0.6b` model is installed in Ollama. It provisions a clearly labeled non-human “科仔 AI 助手” account. In public chat channels, members can trigger a concise reply with `@kezai_ai`, `科仔AI`, or `科仔助手`. Direct-message channels are deliberately excluded, and both the question and generated answer pass through the independent `qwen3guard:0.6b` safety model.

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
