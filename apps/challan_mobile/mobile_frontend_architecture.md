# Paper Mobile App - Frontend Architecture

This document describes the current frontend architecture of the `challan_mobile` Flutter application and how it connects to the backend server.

## Overview
The `challan_mobile` application is a streamlined mobile interface designed specifically for quick, on-the-go data entry (like creating Delivery Challans). Rather than duplicating business logic and network requests, it heavily relies on the shared `core_erp` package, which houses all the data models, API repositories, and state management providers.

## Connection to the Backend

The mobile app connects to the Express.js backend using HTTP REST APIs.

### 1. Base URL Configuration
In `lib/main.dart`, the API Base URL is defined globally:
```dart
const _apiBaseUrl = 'http://localhost:18080';
```
*(Note: During local physical device testing, we use `adb reverse tcp:18080 tcp:18080` to forward the device's localhost to the Mac's localhost where the Node.js backend is running).*

### 2. Authentication Flow
The connection is secured using JWT authentication managed by the `AuthProvider` from `core_erp`.
1. The `AuthProvider` is instantiated in `main.dart`.
2. It initializes with `baseUrl: _apiBaseUrl`.
3. An automatic login is triggered for testing: `provider.login(email: '...', password: '...')`.
4. If successful, it receives a JWT token and updates `auth.isAuthenticated`.
5. The `AuthGate` widget listens to this state. While unauthenticated, it shows a loading screen (or an error if it fails). Once authenticated, it renders the main UI (`ChallanMobileEditorScreen`).

### 3. HTTP Clients & Repositories
The authenticated token is passed into an `AuthenticatedHttpClient` (from `core_erp`), which automatically injects the `Authorization: Bearer <token>` header into all subsequent API requests.
This client is passed to various API repositories (e.g., `ApiDeliveryChallanRepository`, `ApiClientsRepository`), ensuring every module is authenticated.

## State Management & Providers

The app uses the **Provider** package (`ChangeNotifierProvider`) for state management. All providers are initialized in `main.dart` at the root of the app.

- **`ClientsProvider` & `VendorsProvider`**: Load the list of customers and vendors respectively.
- **`ItemsProvider`**: Loads the global inventory items catalog.
- **`DeliveryChallanProvider`**: Handles the submission and fetching of Challans.

### How the UI consumes State
In `ChallanMobileEditorScreen`, the UI interacts with these providers in two ways:
- **Watching for changes (Reads)**: `context.watch<ClientsProvider>().clients` is used in the `build()` method to populate the Dropdowns for selecting a client/vendor. If the backend data updates, the UI automatically rebuilds.
- **Triggering actions (Writes)**: When the user hits "Create Challan", the UI calls `context.read<DeliveryChallanProvider>().createChallan(draft)`. It does this without triggering a rebuild, waiting for the async `Future` to complete and return the generated challan from the backend.

## UI Components & Shared Widgets

To keep the mobile app lightweight and easy to maintain, it reuses widgets from the desktop application where it makes sense.

### `VariationPathSelectorDialog`
When adding an item to a challan, the app opens `VariationPathSelectorDialog`. This complex UI widget is imported entirely from `package:core_erp`. It handles the recursive logic of fetching category schemas, picking variation paths (like Size -> Color -> Finish), and returns a neat `VariationPathSelectionResult` to the mobile app.

### Mobile-Specific Interactive UI
Unlike the desktop app (which uses a data grid/excel-like view), the mobile frontend uses native mobile interactions:
- **Floating Action Button**: Prominent `+` button for adding items.
- **Bottom Sheets (`showModalBottomSheet`)**: Used for selecting items from a list and inputting numeric quantities using native stepper buttons.
- **Swipe-to-Dismiss**: Allows users to quickly delete added items using gestures.
- **Cards & ListTiles**: Information is spaced out vertically using Cards for high touch-target visibility.
