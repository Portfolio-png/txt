# Plan: Mitigate Side Effects of Relaxed Item Name Constraints

## Problem Context
By allowing multiple items to share the exact same `name` (as long as they differ in group, unit, or variation tree), we've introduced potential ambiguities in areas of the system that assumed item names were strictly unique. We need to patch these edge cases to ensure the system remains stable and user-friendly.

## Proposed Changes

### 1. Inventory Auto-Mapping Conflicts (`inventory_screen.dart`)
**Issue:** When adding inventory, the system tries to auto-link it to an item by matching the name. If multiple items have the same name, it currently just picks the last one in the list arbitrarily.
**Fix:** Update `inventory_screen.dart` auto-linking logic (`exactMatches`).
- If exactly 1 match is found: automatically map it.
- If multiple matches are found: return `null` (skip auto-mapping) and force the user to manually select the correct variation/group from the UI. This prevents silent mismatches.

### 2. Search / Dropdown Ambiguity (`orders_screen.dart` and `delivery_challan_screen.dart`)
**Issue:** If two items are named "Copper" and have no variations, their `displayName` will both be "Copper". They will appear identically in item selection dropdowns.
**Fix:** Append contextual information to the dropdown label.
- Update `SearchableSelectOption` label generators for items to include the primary group and/or unit if the display name is simple. 
- Example: `label: '${item.displayName} (${primaryGroup})'` so the user sees "Copper (Raw Materials)" vs "Copper (Hardware)".

### 3. Backend Upsert / Import Quirks (`server.js`)
**Issue:** The backend has `findItemByDisplayName` which is used to prevent duplicates during item upserts. 
**Fix:** Since `displayName` might now have duplicates if variations are empty, we should ensure `findItemByDisplayName` is used safely. Actually, if users keep `displayName` unique (or we append the group to it), it's safe. I will update `findItemByDisplayName` to also optionally take `groupId` and `unitId` if available, to narrow down the correct item during imports.

### 4. Variation Tree Ordering Flaws (`server.js`)
**Issue:** In `server.js`, the duplicate check converts the variation tree to a string and compares it. If a user submits `[Size, Color]` and another submits `[Color, Size]`, the backend treats them as different. (The frontend `items_provider.dart` already sorts them correctly).
**Fix:** Update `comparableTree` inside `server.js` to sort nodes alphabetically by `name` before JSON serialization. This ensures structural equality regardless of the array order.

## User Review Required
Please review the plan. The most impactful change is for Inventory: if you upload a sheet with "Copper" and you have 5 different items named "Copper", the system will NO LONGER guess. You will have to manually map it in the UI. Are you okay with this? 

Once approved, I will implement these fixes.
