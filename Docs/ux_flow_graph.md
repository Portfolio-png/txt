# Paper ERP - UX & Navigation Flow

As a Product Manager, this graph maps out the high-level User Experience (UX) architecture, layout structure, and typical user navigation flows within the application.

```mermaid
graph TD
    %% Entry Point
    Login([Login Screen]) --> |Authenticated| AppShell

    %% Core Application Shell
    subgraph "Main Application Shell"
        AppShell[App Shell]
        Sidebar[Left Sidebar Navigation]
        TopBar[Top Search & User Menu]
        ContentArea[Dynamic Content Area]
        
        AppShell --> Sidebar
        AppShell --> TopBar
        AppShell --> ContentArea
    end
    
    %% Sidebar Navigation Links
    Sidebar -->|Navigates to| ActionCenter[Action Center]
    Sidebar -->|Navigates to| InventoryNav[Inventory & Materials]
    Sidebar -->|Navigates to| ProductionNav[Production Pipelines]
    Sidebar -->|Navigates to| OrderNav[Orders & Challans]
    Sidebar -->|Navigates to| PeopleNav[People & Departments]
    
    %% Content Area Interactions (Example Flow: Inventory)
    InventoryNav -.->|Renders in| ContentArea
    
    subgraph "Typical Data View (e.g., Component Groups)"
        direction TB
        ListView[Data Table / List View]
        ListView -->|Click Row| SideSheet[Side Sheet Details Panel]
        ListView -->|Primary Action| CenteredDialog[Centered Form Dialog]
        
        SideSheet -->|Edit Action| CenteredDialog
    end
    
    %% Connect Content Area to standard views
    ContentArea --> ListView
    
    %% Top Bar Interactions
    TopBar --> GlobalSearch([Global Search Overlay])
    TopBar --> ProfileSettings([User Preferences / Logout])
    
    %% Global Interactions
    GlobalSearch -->|Select Result| SideSheet
    
    classDef shell fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef nav fill:#fff3e0,stroke:#e65100,stroke-width:1px;
    classDef modal fill:#f3e5f5,stroke:#4a148c,stroke-width:1px;
    
    class AppShell,Sidebar,TopBar,ContentArea shell;
    class ActionCenter,InventoryNav,ProductionNav,OrderNav,PeopleNav nav;
    class SideSheet,CenteredDialog,GlobalSearch modal;
```

## UX Architecture Principles
1. **The 'L' Shape Layout**: The app utilizes a fixed left sidebar for primary navigation and a persistent top bar for global actions (Search, Profile). The remaining screen real estate is dedicated to the dynamic content area.
2. **Progressive Disclosure (Side Sheets)**: Instead of navigating the user away to a new page to view details, clicking a record (like a Component Group) opens a responsive **Side Sheet** anchored to the right. This keeps the user in context with the underlying list view.
3. **Focused Data Entry (Centered Dialogs)**: Creation and editing actions are typically handled via **Centered Form Dialogs** (`showErpFormDialog`) to ensure the user's focus is captured exclusively for data entry, before returning them to their previous context.
4. **Global Accessibility**: The global search is accessible from anywhere via the top bar, allowing users to jump directly to specific item side sheets without traversing the traditional sidebar hierarchy.
