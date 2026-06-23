# Project Accomplishments (June 22 - June 23, 2026)

This document tracks the core architectural enhancements, feature flags, and auto-updater implementations developed over the recent work sessions.

## 1. Dual-Layered Machine Activation
The Machine Activation layer has been fully implemented, securing the application at the hardware level while decoupling it from the day-to-day user login process. 

### Node.js Control Plane
- **`sandbox_client_pins` & `sandbox_activated_machines` tables**: The database now tracks which hardware fingerprints are allowed per client, up to a maximum of 3 activated machines.
- **PIN Auto-Generation**: Whenever a client is registered on the dashboard, a secure 6-digit `Activation PIN` is randomly generated and permanently linked to that `client_id`.
- **Dashboard Visibility**: The dashboard UI (`dashboard.html`) now prominently displays the client's Activation PIN right below the Client ID. 

### Flutter Hardware Fingerprinting & Secure Storage
Added `device_info_plus` and `flutter_secure_storage` to precisely identify devices and securely store tokens:
- **`ActivationService.dart`**: Evaluates the platform (`Platform.isWindows`, `isMacOS`, `isAndroid`, etc.) and creates a composite string of motherboard details, computer names, and memory. It hashes this into a SHA-256 string, creating an irreversible, privacy-preserving machine fingerprint.
- **Local JWT Validation**: The server generates a unique crypto token upon successful activation, which `ActivationService` locks into `flutter_secure_storage`. 

### The Activation UI & App Boot Flow
- **The Gatekeeper**: Modified `_AuthGate` in `main.dart` to check `ActivationService.isActivated()` *before* attempting any user authentication or displaying the login screen.
- **Activation Screen**: If the machine isn't activated, the user lands on a secure `ActivationScreen` asking for the `client_id` and the `Activation PIN`.
- **The Bypass**: If the machine *is* already activated, the `ActivationScreen` is skipped entirely, taking the worker straight to the standard `LoginScreen`.

### User Synchronisation
- **`DataSyncService.syncUser()`**: Added a lightweight background POST mechanism.
- **`AuthProvider.createUser()` Hook**: When the Owner uses the app to create a new Worker (or Admin), it saves to the local SQLite database *and* fires `syncUser()` up to the cloud.
- **`sandbox_client_users` table**: The dashboard now aggregates and displays the emails and roles of every person working under that `client_id`.

---

## 2. Dynamic Feature Toggles & Remote Config
Built a comprehensive toggle architecture to seamlessly turn features on/off per client.

### Client Config API
- **Endpoint `GET /api/config/:client_id`**: Serves a JSON map of configuration settings for specific clients, including `modules`, `features`, and `update` logic.
- **Dashboard UI Control**: You can explicitly turn features on/off in the backend dashboard and update them instantly.

### Flutter ConfigService
- **`ConfigService.dart`**: Fetches the configuration JSON from the backend during boot. Falls back to a local `SharedPreferences` cached string or global defaults if the network is down.
- **Centralized Toggles (`FeatureFlags.dart`)**: Checks configuration keys cleanly throughout the UI (`ConfigService.instance.disableMachineCustomFields`).
- Verified its capability to seamlessly rewrite UI states (e.g., hiding Custom Fields on the Machine form).

---

## 3. Silent Windows Auto-Updater
Replaced the failing `auto_updater` package with a native, robust, zero-downtime updater specifically engineered to defeat the Windows file lock constraint.

### The Challenge
Windows file locks prevent a running `.exe` from being replaced by an updater while it is still running, which normally causes background updaters to fail silently without elevating privileges.

### The Solution (`AutoUpdaterService.dart`)
We engineered a robust `.bat` script that uses the `.old` extension trick. 

1. `ConfigService` detects a new version via `http://.../api/config/:clientId`.
2. `AutoUpdaterService` downloads the update payload silently in the background via HTTP.
3. A script named `updater.bat` is generated and executed in an independent cmd process.
4. The Flutter app terminates itself cleanly.
5. `updater.bat` waits using a system `ping` delay, renames `paper.exe` to `paper.exe.old`, copies the new payload to `paper.exe`, starts the newly updated executable, and deletes itself.

**Test Status:** ✅ The complete update cycle was live-tested locally on a compiled `.exe` and performed flawlessly without UAC prompts or lock errors.

---

## 4. CI/CD Backend Triggers
- **`POST /api/build/:clientId`**: Added a Node endpoint to programmatically trigger the `workflow_dispatch` event on the GitHub Actions REST API.
- Integrated into the Dashboard so administrators can instantly request new binary generation for clients.

## 5. Sentry Integration & Session Replays
- **`SessionReplayService.dart`**: Successfully bootstrapped the `sentry_flutter` package.
- Injected user contexts, client IDs, and enabled 100% video session replays inside Sentry for rigorous telemetry tracking.
