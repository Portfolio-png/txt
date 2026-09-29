# Paper ERP - Product Architecture & Project Map

As a Product Manager, here is the high-level functional and architectural map of the Paper ERP ecosystem. It outlines the primary user interfaces, core functional modules, the backend infrastructure, and the deployment environments.

```mermaid
graph TD
    %% Core Nodes
    User([End User / Admin])
    
    subgraph "Flutter Client (Frontend - 'Paper')"
        UI[UI Shell: Sidebar + Content Area]
        
        subgraph "Core ERP Features (packages/core_erp)"
            Auth[Authentication & Users]
            ActionCenter[Action Center]
            
            %% Functional Domains
            subgraph "Supply & Production"
                Inventory[Inventory Management]
                Items[Items & Materials]
                Groups[Component Groups]
                Pipelines[Production Pipelines]
            end
            
            subgraph "Fulfillment & External"
                Orders[Orders]
                Challans[Delivery Challans]
                Clients[Clients]
                Vendors[Vendors]
            end
            
            subgraph "Operations"
                Payroll[Payroll]
                Departments[Departments]
                Units[Units of Measurement]
            end
            
            Search[Global Search]
        end
        
        %% State Management / Core
        Providers[State Providers]
        Theme[Soft ERP Theme System]
    end

    subgraph "Backend Infrastructure (Node.js)"
        API[Express REST API]
        AuthService[Auth & Session Service]
        DB[(SQLite Database - paper.db)]
        PM2[PM2 Process Manager]
    end
    
    subgraph "Deployment & Environments"
        Demo[Local Demo Mode - No Backend]
        EC2[AWS EC2 / Ubuntu]
        Railway[Railway Cloud]
    end

    %% Relationships
    User -->|Interacts via Desktop/Web| UI
    UI --> Auth
    UI --> ActionCenter
    UI --> Inventory
    UI --> Orders
    UI --> Search
    
    %% Internal dependencies
    ActionCenter -.-> Orders
    ActionCenter -.-> Inventory
    Inventory -.-> Items
    Pipelines -.-> Items
    Groups -.-> Items
    Orders -.-> Clients
    
    %% Client to Backend
    Auth -->|HTTP/REST| API
    Inventory -->|HTTP/REST| API
    Orders -->|HTTP/REST| API
    Items -->|HTTP/REST| API
    
    %% Backend internals
    API --> AuthService
    API --> DB
    AuthService --> DB
    PM2 -->|Manages| API
    
    %% Deployment links
    API -.->|Deployed to| EC2
    API -.->|Deployed to| Railway
    UI -.->|Demo Mode| Demo
```

## Module Breakdown
1. **Frontend (`packages/core_erp`)**: The application leverages a modular architecture. Core domains like `Inventory`, `Orders`, `Production Pipelines`, and `Groups` are isolated into feature folders. They plug into a primary UI shell that uses a Sidebar + Main Content Area pattern.
2. **Backend**: A lean Node.js + SQLite stack managed via PM2. Handles strict role-based authentication, retention management, and serves the core REST API to the Flutter client.
3. **Environments**: The project supports a pure local "Demo Mode" with seeded data (no backend required), alongside robust production deployment strategies for AWS EC2 and Railway.
