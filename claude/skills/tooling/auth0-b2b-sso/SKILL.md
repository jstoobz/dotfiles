# Auth0 B2B SSO Skill Guide

This file defines an expert-level Auth0 skill focused on **B2B SSO integrations**, structured for progressive disclosure: each level builds on the previous one. Use it as a rubric, training path, or internal doc skeleton.

---

## How to Use This Guide

- Start at Level 1 and move down; do not skip levels.
- Treat each level as a checklist for knowledge, behaviors, and artifacts.
- For onboarding, target Level 3–4 as “ready for production work” for most engineers; Level 5–6 are staff+ responsibilities.

---

## Level 1 – Core B2B / Enterprise SSO Concepts

**Goal:** Understand how Auth0 models B2B customers, organizations, and enterprise connections, and how identities flow through the system.[web:24][web:25][web:11]

### What You Should Know

- **B2B architecture basics**
  - Auth0 tenant vs application vs **organization** (org = a customer account boundary for B2B).[web:24][web:25]
  - Database vs social vs **enterprise** connections (SAML, OIDC, AD/LDAP, etc.).[web:11]
- **Federated SSO in B2B**
  - Customer’s IdP (Okta, Entra ID, Ping, ADFS, etc.) is the source of truth, Auth0 acts as SP (SAML) or OIDC client and federates into your app.[web:11][web:24]
- **Organizations (Org model)**
  - Organizations represent your business customers and provide:
    - Org-specific federation (per-org enterprise connections).
    - Org-aware login URLs and branding.
    - Org-level membership and roles.[web:25]
- **High-level flows**
  - “User from ACME hits your SaaS, types email, is routed to ACME’s IdP, then back through Auth0 into your app” – be able to narrate that end‑to‑end with correct terms.[web:24][web:25]

### Self‑Check

You are at Level 1 if you can:

- Explain to a non-auth engineer what “enterprise SSO with Auth0” means in a B2B SaaS context.
- Draw a simple sequence diagram: Browser → Auth0 → Customer IdP → Auth0 → App, naming Auth0 roles (SP, OIDC client).[web:24][web:11]

---

## Level 2 – Tenant, orgs, and enterprise connections (Dashboard)

**Goal:** Configure B2B tenants, organizations, and enterprise connections correctly using the dashboard.[web:24][web:25][web:11][web:10]

### What You Should Know

- **B2B tenant & architecture scenarios**
  - Recognize the “B2B IAM with a SaaS application” scenario and why a centralized login domain is recommended.[web:24][web:16]
- **Organizations configuration**
  - Create organizations, set branding, invite members, and assign roles.[web:25]
  - Understand how orgs connect to applications and which org features require specific plans.[web:25]
- **Enterprise connections (SAML/OIDC)**
  - Create SAML / OIDC enterprise connections under Authentication → Enterprise.[web:11]
  - Configure IdP metadata, certificates, callback URLs, and attribute mappings as required by the customer.[web:11]
  - Enable enterprise connections per application via the Applications view.[web:10]
- **Login routing**
  - Understand how org‑aware login URLs and connection parameters (`connection`, `organization`, etc.) change behavior.[web:24][web:10]

### Self‑Check

You are at Level 2 if you can:

- Onboard a new B2B customer by hand: create an org, configure their SAML/OIDC connection, hook it to your production app, and give them a working login URL.[web:25][web:11]
- Explain when you’d create a dedicated org vs reuse an existing one for the same business.[web:25]

---

## Level 3 – Management API for B2B / SSO Automation

**Goal:** Automate creation and lifecycle of orgs and connections via the Auth0 Management API.[web:24][web:25][web:11][web:19]

### What You Should Know

- **Management API fundamentals**
  - Register a machine‑to‑machine application, authorize it on the “Auth0 Management API,” and assign scopes such as:
    - `create:organizations`, `update:organizations`, `delete:organizations`.
    - `create:connections`, `update:connections`, `delete:connections`.
    - `create:organization_invitations`, `create:organization_member_roles`, etc.[web:24][web:25]
- **Organizations via API**
  - Use `POST /api/v2/organizations` to create orgs and configure metadata or display names from internal customer records.[web:25][web:19]
  - Manage membership and roles using the organizations endpoints so provisioning tools (CRM, billing, admin portal) can drive org state.[web:25][web:19]
- **Enterprise connections via API**
  - Use `POST /api/v2/connections` for SAML/OIDC enterprise connections, supplying options (e.g., `metadataUrl`, `signingCert`, `entityId`).[web:11][web:19]
  - Attach connections to apps and orgs programmatically as part of customer onboarding flows.[web:19][web:10]

### Self‑Check

You are at Level 3 if you can:

- Implement a backend job that, given a new customer record, automatically:
  - Creates an org.
  - Creates or reuses an enterprise connection.
  - Enables it on the right application(s).[web:19][web:25]
- Document the least‑privilege scopes needed for that job and justify them.[web:24]

---

## Level 4 – Actions & Extensibility for B2B SSO

**Goal:** Use Auth0 Actions to enforce B2B policies, enrich tokens, and integrate with external systems in org/connection‑aware ways.[web:23][web:12][web:6]

### What You Should Know

- **Actions overview**
  - Actions are tenant‑specific, versioned Node.js functions that run on specific triggers (login, machine‑to‑machine, password reset, etc.).[web:23]
  - Multiple Actions can be added to a trigger and run in order, synchronously or asynchronously, depending on the trigger.[web:23]
- **Login and post‑login Actions**
  - Use `onExecutePostLogin` to:
    - Read `event` (user, org, connection, IdP claims).[web:12][web:23]
    - Shape tokens via `api.idToken.setCustomClaim` / `api.accessToken.setCustomClaim`.[web:12]
    - Permit/deny based on allow/deny lists, domains, org membership, or IdP group claims.[web:12]
- **Risk and step‑up**
  - Implement role‑based MFA using `api.multifactor.enable("any")` for privileged users or specific orgs.[web:6]
- **Integration points**
  - Call external APIs from Actions to:
    - Sync profile or group data.
    - Notify provisioning/entitlement systems on login.
    - Enforce business rules not modeled directly in Auth0.[web:23]

### Self‑Check

You are at Level 4 if you can:

- Write an Action that blocks login for users whose email domain doesn’t match the org’s allowed domains, with clear error messaging.[web:12][web:25]
- Write an Action that:
  - Reads IdP attributes.
  - Normalizes them into consistent claims for your API.
  - Triggers MFA for certain roles.[web:6][web:23]

---

## Level 5 – B2B SSO Architecture, Provisioning, and UX at Scale

**Goal:** Design and evolve a robust B2B SSO architecture and customer experience with Auth0 at the center.[web:24][web:16][web:18][web:19][web:25]

### What You Should Know

- **B2B architecture scenarios**
  - Understand Auth0’s B2B architecture guidance:
    - Centralized auth domain across multiple products.
    - When to split tenants (e.g., region, environment, product line).[web:16][web:24]
- **Provisioning models**
  - B2B provisioning strategies:
    - Tenant‑side admin provisioning vs automated user provisioning.
    - Different patterns when orgs bring:
      - Only database users.
      - Their own IdP.
      - Multiple IdPs plus social connections.[web:19]
- **Auth & authorization flows**
  - How Auth0 issues access tokens (JWTs) to your APIs in B2B scenarios and how you can map org/role concepts into your service layer.[web:18]
- **UX patterns**
  - Org‑aware login entry points, HRD (home realm discovery), and handling users with multiple orgs.[web:24][web:25]
  - How to expose SSO configuration to customer admins in an admin portal driven by your own backend + Management API.[web:19]

### Self‑Check

You are at Level 5 if you can:

- Design a full B2B SSO architecture (tenants, orgs, connections, APIs, login flows) for a new SaaS product and justify each decision using Auth0’s scenarios.[web:16][web:24]
- Describe a customer SSO onboarding flow that is mostly self‑service (admin configures SAML/OIDC, tests, enables) with minimal manual Auth0 dashboard work.[web:19][web:25]

---

## Level 6 – Operations, Observability, and Migration

**Goal:** Operate B2B SSO as a product: monitor, troubleshoot, evolve, and (if needed) migrate with minimal customer disruption.[web:24][web:19][web:21][web:20]

### What You Should Know

- **Operational maturity**
  - How to structure tenants for separate environments and risk domains, aligning with Auth0 architecture scenarios and internal SDLC.[web:16][web:21]
  - Playbooks for:
    - Certificate rotation.
    - IdP outages.
    - Connection misconfiguration and rollback.[web:19][web:20]
- **Monitoring and alerting**
  - Which signals to track:
    - Login success/failure rates per connection/org.
    - Latency across IdPs.
    - Error codes and spikes around rollouts.[web:20]
- **Connections as code**
  - Why managing connections and orgs via Management API + IaC yields better consistency, rollback, and review processes.[web:20][web:19]
- **Migration patterns**
  - High‑level strategies for:
    - Moving customers from passwords to enterprise SSO.
    - Migrating from or to Auth0 while keeping SSO available (parallel connections, staged cutover).[web:19][web:20]

### Self‑Check

You are at Level 6 if you can:

- Propose an “SSO reliability and risk” roadmap that covers:
  - Monitoring.
  - Runbooks.
  - IaC for connections/orgs.
  - Tenant topology changes.[web:20][web:21]
- Design a migration plan where enterprise SSO remains available while underlying connection or even platform changes are rolled out gradually.[web:19][web:20]

---

## Progressive Disclosure Artifacts

Below are ready‑to‑use artifacts that support progressive disclosure when teaching or assessing this skill.

### 1. Skill Matrix Table

| Level | Focus Area                               | Primary Activities                                                           |
| ----- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| 1     | Core B2B & SSO concepts                  | Explain flows, name components, whiteboard diagrams.[web:24][web:25]         |
| 2     | Dashboard configuration                  | Configure orgs & connections for a single customer.[web:25][web:11]          |
| 3     | Management API automation                | Programmatically create orgs and enterprise connections.[web:19][web:11]     |
| 4     | Actions & extensibility                  | Enforce policies, enrich tokens, integrate external systems.[web:23][web:12] |
| 5     | Architecture, provisioning & UX at scale | Design tenant topology, onboarding flows, admin UX.[web:24][web:16]          |
| 6     | Operations, observability & migration    | Runbooks, monitoring, changes and migrations.[web:19][web:20]                |

### 2. Progressive Learning Path Template

Use this for yourself or new engineers:

1. **Week 1 – Level 1–2**
   - Read B2B and organizations overviews.[web:24][web:25]
   - Manually onboard a “test customer” org with an enterprise connection in a sandbox tenant.[web:11][web:10]
2. **Week 2 – Level 3**
   - Build a small internal service that:
     - Creates orgs.
     - Links them to a test application.
     - Attaches a pre‑configured SAML connection.[web:19][web:11]
3. **Week 3 – Level 4**
   - Implement a Post‑Login Action enforcing:
     - Domain allowlist.
     - Role‑based MFA.[web:23][web:6][web:12]
4. **Week 4+ – Level 5–6**
   - Propose a B2B SSO architecture for a multi‑product SaaS, with:
     - Tenant topology.
     - Org strategy.
     - Operational runbooks.[web:16][web:19][web:21]

### 3. Checklist Snippet (Drop‑in for PRD / Onboarding Docs)

```markdown
## Auth0 B2B SSO Readiness Checklist

- [ ] B2B concepts: orgs, connections, tenant, apps clearly understood (L1).[1][2]
- [ ] Can configure an org + enterprise connection end‑to‑end via dashboard (L2).[3][4]
- [ ] Can create orgs and connections via Management API, wired to internal systems (L3).[4][5]
- [ ] Has at least one production‑ready Action enforcing B2B rules (org, domain, roles) (L4).[6][7]
- [ ] Can reason about tenant topology, provisioning patterns, and UX trade‑offs (L5).[5][8][1]
- [ ] Can design operational runbooks and migration paths for SSO (L6).[9][10][5]
```
