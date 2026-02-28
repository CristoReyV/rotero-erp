<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://github.com/user-attachments/assets/0aa67016-6eaf-458a-adb2-6e31a0763ed6" />
</div>

# Run and deploy your AI Studio app

This contains everything you need to run your app locally.

View your app in AI Studio: https://ai.studio/apps/bf4c56d8-3715-4db5-b678-5a61922cc23d

## Run Locally

**Prerequisites:**  Node.js


1. Install dependencies:
   `npm install`
2. Set the `GEMINI_API_KEY` in [.env.local](.env.local) to your Gemini API key
3. Run the app:
   `npm run dev`

## App Modes (Config Gating)

This application supports different operational modes configured via the `VITE_APP_MODE` environment variable:

- **"prod"** (Default): Strict access mode. Modules lacking configuration will fully block the user and require manual setup via the administrative "Setup Center". Bypass actions are not allowed.
- **"demo"**: Enables a mock configuration bypass. When an admin user encounters a blocked screen, they will see a "Configurar (Demo)" button that seeds the configuration with fake data to unlock the module for demonstrations. This is only available if `allow_demo_mode` is also checked in the tenant settings.
- **"staging"**: Reserved for staging environments.

To change modes, add or edit the variable in your `.env` file (e.g. `.env.local` or `.env`):
```env
VITE_APP_MODE="demo"
```
