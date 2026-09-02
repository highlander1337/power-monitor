# Design REST API contract

This document should answer: 
- "What are the architectural rules that every REST endpoint in the IEAP must follow?"

## Purpose and Scope

### Purpose

This document defines the architectural contract for the REST API exposed by the Industrial IoT Energy Analytics Platform (IEAP).

The REST API is the public integration boundary between client applications and the platform. It exposes business capabilities, infrastructure management, historical telemetry, and analytical information while preserving the internal separation between telemetry ingestion, aggregation, and business services established by SD-001 through SD-005.

This document establishes the conventions, constraints, and resource model that every REST endpoint must follow. It intentionally defines architectural behavior before specifying individual endpoint implementations.

### Scope

SD-006 defines:

- public resource boundaries;
- URI conventions;
- HTTP semantics;
- authentication and authorization expectations;
- request and response conventions;
- query behavior;
- filtering, sorting, and pagination rules;
- concurrency expectations;
- API versioning strategy;
- error representation;
- OpenAPI compatibility.

This document does not define:

- MQTT communication;
- firmware contracts;
- telemetry persistence;
- aggregation algorithms;
- internal event messaging;
- database implementation details.

Those concerns remain governed by SD-001 through SD-005.

## Architectural Principles

The REST API shall adhere to the following architectural principles.

### Principle 1 — Business Capabilities over Persistence

The public API represents business capabilities rather than database structures.

Internal persistence models are implementation details and shall not dictate the public REST surface.

For example:
```txt
TelemetryMinute
TelemetryHourly
TelemetryDaily
```

are implementation artifacts and are not automatically exposed as REST resources.

Instead, clients consume analytical capabilities such as:
```txt
Channel Analytics
Room Consumption
Historical Energy
```
This preserves implementation flexibility while maintaining a stable public contract.

### Principle 2 — Stable Resource Identity

Every public resource shall expose a stable identifier that remains valid independently of persistence implementation.

Clients must never depend on internal database relationships or composite keys.

### Principle 3 — Explicit Ownership Boundaries

The REST API exposes business operations.

Telemetry ingestion, aggregation, MQTT messaging, checkpoint management, and event publication remain internal implementation concerns.

Resources such as:

```txt
OutboxMessage
AggregationCheckpoint
```

are intentionally excluded from the public API.

### Principle 4 — Read/Write Separation

Resources are classified as either:

```txt
configuration resources;
operational resources;
analytical resources.
```

Analytical resources are derived from telemetry and are read-only.

Configuration resources support modification through REST operations.

Operational resources expose infrastructure state but do not expose internal processing mechanics.

### Principle 5 — UTC Everywhere

Every timestamp exchanged through the REST API shall be represented in UTC using ISO-8601.

The API never accepts or returns local time.

All temporal filtering and aggregation boundaries are interpreted in UTC.

### Principle 6 — Explicit Units

All numerical values shall expose explicit engineering units through property names.

Examples:

```txt
powerW
voltageVrms
currentArms
energyConsumedWh
```

Units are never implied.

### Principle 7 — Completeness is Part of the Contract

Analytical responses must expose data completeness.

Consumers must be able to distinguish:

- complete observations
- partially observed windows
- unavailable observations

Projection completeness is represented explicitly rather than inferred.

### Principle 8 — Internal Architecture Remains Encapsulated

Clients interact with REST resources.

They do not interact with:

- MQTT
- Outbox events
- Aggregation checkpoints
- Internal worker services

Internal implementation may evolve without affecting public contracts.

### Principle 9 — Resource-Oriented Capabilities

The API may expose computed or analytical resources that do not directly correspond to persisted entities. A REST resource represents a stable concept within the business domain, regardless of whether it is persisted, computed, or composed from multiple internal services.

### Principle 10 — Progressive Analytical Abstraction

The REST API exposes information through successive levels of abstraction. Observation resources expose factual measurements, consumption resources expose descriptive summaries of energy usage, and analytics resources expose interpretations and insights derived from those observations. Each layer builds upon the previous one without altering its meaning.

### Principle 11 - Channel as the Analytical Root

A Channel is the fundamental analytical unit of the platform because it represents the physical measurement point from which telemetry observations originate. Telemetry, consumption, and channel-level analytics are therefore anchored to the Channel resource. Higher-level analytical resources, such as room-level consumption and analytics, are compositions or interpretations of the channels belonging to that scope.

The API must preserve this hierarchy without exposing the underlying persistence model. A capability may be represented at multiple scopes, but its analytical origin remains the Channel.

### Principle 12 - Progressive Analytical Abstraction

The API exposes information through progressively higher levels of meaning:

```text
Observation → Consumption → Analytics
```

Observation exposes factual measurements, Consumption describes what happened, and Analytics provides interpretations or insights derived from those observations.

### Reasoning about principle 11 and 12

#### The core idea

We have two different hierarchies in the system.

**Physical/infrastructure hierarchy:**

```text
Room
  └── Monitor
        └── Channel
              └── Channel Assignment
```

This answers:

> **What physical infrastructure do I have, and where is it?**

But the **analytical hierarchy** is different:

```text
TelemetrySample
      ↓
Channel
      ↓
Consumption
      ↓
Analytics
```

This answers progressively richer questions:

| Layer       | Question                       |
| ----------- | ------------------------------ |
| Telemetry   | **What exactly was measured?** |
| Consumption | **What happened?**             |
| Analytics   | **Why did it happen?**         |

The important part is that **Channel is the boundary between the physical world and the analytical world**.

---

#### Why Channel is the analytical root

Look at the entire pipeline we've designed.

The device reports:

```text
physicalPort = 1
```

The ingestion service resolves:

```text
DeviceIdentifier + PhysicalPort
        ↓
Channel
```

Telemetry is stored as:

```text
TelemetrySample
    ↓
ChannelId
```

Aggregation produces:

```text
(ChannelId, MinuteUtc)
(ChannelId, HourUtc)
(ChannelId, DateUtc)
```

So every analytical calculation ultimately has this form:

```text
Channel
   ↓
Telemetry
   ↓
Aggregation
```

A room isn't the source of a measurement.

A monitor isn't the source of a measurement.

A **channel is**.

Room-level analytics are therefore compositions of channel-level information:

```text
Room
 ↓
Channels
 ↓
Telemetry
 ↓
Consumption
```

That's why I called Channel the **analytical root**.

---

#### Why this matters for the API

Without making this principle explicit, someone designing a future endpoint might reasonably ask:

> "Should consumption belong to the monitor or the room?"

The answer becomes straightforward.

For the fundamental measurement:

```text
/channels/{channelId}/consumption
```

For an aggregate:

```text
/rooms/{roomId}/consumption
```

The room endpoint is an **aggregation of channel capabilities**, not a competing source of truth.

Likewise:

```text
/channels/{channelId}/analytics
```

is the natural place for channel-specific interpretation.

A future room-level analytical capability can then aggregate or interpret those underlying channel observations.

---

####  It also protects us from a subtle architectural mistake

Imagine we eventually introduce:

```text
/anomalies
```

Someone might design:

```text
GET /anomalies?roomId=5
```

That's not necessarily wrong, but it loses the domain hierarchy.

The more natural model is:

```text
/channels/{channelId}/analytics/anomalies
```

because an anomaly is ultimately an interpretation of observations belonging to a channel.

Then:

```text
/rooms/{roomId}/analytics/anomalies
```

can answer:

> "Which channels in this room exhibit anomalous behavior?"

That scales naturally.

---

#### It also explains why raw telemetry is bounded

We decided that raw telemetry is queryable, but not a CRUD resource.

So:

```text
GET /channels/{channelId}/telemetry
```

makes sense.

The API is saying:

> "Give me the observations belonging to this analytical subject."

It doesn't need:

```text
GET /telemetrySamples/{id}
```

because an individual database row isn't really a meaningful business resource.

That's another consequence of the principle.

---

Together, these two principles give SD-006 a very strong foundation:

```text
                    Room
                     │
              aggregates over
                     ↓
                  Channel
                     │
                 observes
                     ↓
              TelemetrySample
                     │
                  derives
                     ↓
                Consumption
                     │
               interprets
                     ↓
                 Analytics
```

**That's much more than a URL convention.** It gives us a rule for deciding where future API capabilities belong. If we later add anomaly detection, forecasting, efficiency analysis, power-quality analysis, or other capabilities, we can ask: *what is the analytical subject, and at what abstraction level does this answer a user question?* The API structure then follows from the domain rather than from whatever tables happen to exist in SQL Server.

## Resource Model

### Purpose

The Resource Model defines the public domain concepts exposed by the Energy Analytics API.

A resource represents a stable business concept that clients can discover, reference, and interact with through the REST API.

Resources are intentionally independent of the internal persistence model. A resource may represent:

- a persisted business entity;
- a computed analytical capability;
- a bounded historical query;
- a composition of multiple internal services.

The API therefore models the platform's capabilities rather than its database schema.

### Resource Classification

All resources belong to one of four categories.

```txt
Infrastructure
Configuration
Observations
Analytics
```

Each category has a clearly defined responsibility.

### Infrastructure Resources

Infrastructure resources describe the physical monitoring topology.

Infrastructure resources describe the physical monitoring topology.

They answer questions such as:

What devices exist?
What channels do they expose?
Where are they installed?

These resources primarily represent infrastructure identity.

Resources
```txt
/rooms
/monitors
/channels
/channel-assignments
``` 
Responsibilities include:

- monitor discovery
- channel discovery
- room organization
- installation metadata
- historical channel assignment

These resources are primarily CRUD-oriented.

### Configuration Resources

Configuration resources define how the platform interprets telemetry.

Unlike infrastructure resources, they represent business configuration rather than physical devices.

Resources
```txt
/energy-tariffs
```

Future examples may include:

```txt
/notification-policies
/user-preferences
/reporting-profiles
```

Configuration resources are writable.

### Observation Resources

Observation resources expose the platform's permanent system of record.

They represent historical measurements captured from the firmware.

Observation resources are intentionally read-only.

Current resource:

```txt
/channels/{channelId}/telemetry
```

This resource provides bounded historical access to TelemetrySample.

It exists because raw telemetry is valuable for:

- diagnostics
- auditing
- aggregation validation
- future analytical experimentation

Observation resources never expose ingestion mechanics such as MQTT messages, validation pipelines, or event publication.

### Analytics Resources

Analytics resources expose information derived from telemetry.

Unlike observation resources, they do not represent the original measurements.

Instead, they expose higher-level analytical capabilities.

#### Channel Analytics

```txt
/channels/{channelId}/analytics
/channels/{channelId}/consumption
```

These resources provide information derived from one channel.

#### Room Analytics

```txt
/rooms/{roomId}/analytics
/rooms/{roomId}/consumption
```

These resources aggregate information across every channel assigned to a room.

#### Characteristics

Analytics resources are:

- computed;
- read-only;
- deterministic;
- derived from TelemetrySample;
- independent of projection implementation.

Clients do not know whether responses originate from:

- TelemetryMinute

- TelemetryHourly

- TelemetryDaily

or a future analytical engine.

This separation preserves implementation flexibility.

### Resource Hierarchy

The public API hierarchy is organized around ownership relationships.

```txt
/rooms
    └── /{roomId}
            ├── /analytics
            ├── /consumption
            └── /channel-assignments

/monitors
    └── /{monitorId}
            └── /channels

/channels
    └── /{channelId}
            ├── /telemetry
            ├── /analytics
            └── /consumption

/energy-tariffs
```

The hierarchy represents navigation convenience rather than persistence relationships.

For example:

A channel belongs to one monitor from an infrastructure perspective, yet its analytical information may be queried independently.

### Resource Characteristics

| Resource            | Category       | Mutable | Canonical | Derived |
| ------------------- | -------------- | :-----: | :-------: | :-----: |
| Room                | Infrastructure |    ✔    |     ✔     |    ✖    |
| Monitor             | Infrastructure | Partial |     ✔     |    ✖    |
| Channel             | Infrastructure | Partial |     ✔     |    ✖    |
| Channel Assignment  | Infrastructure |    ✔    |     ✔     |    ✖    |
| Energy Tariff       | Configuration  |    ✔    |     ✔     |    ✖    |
| Telemetry           | Observation    |    ✖    |     ✔     |    ✖    |
| Channel Analytics   | Analytics      |    ✖    |     ✖     |    ✔    |
| Channel Consumption | Analytics      |    ✖    |     ✖     |    ✔    |
| Room Analytics      | Analytics      |    ✖    |     ✖     |    ✔    |
| Room Consumption    | Analytics      |    ✖    |     ✖     |    ✔    |

- Canonical
    - These are the fundamental, authoritative values of a resource. 
    - They represent the “ground truth” that doesn’t change depending on context. 
- Mutable
    - These are values that can change over time or be updated.
    - They reflect the current state of the resource rather than its permanent identity.
- Derived
    - These are calculated or inferred values based on canonical and/or mutable data.
    - They don’t exist independently but are outputs of formulas or models.

### Public vs Internal Resources

The following internal implementation concepts are intentionally not public REST resources.

| Internal Concept        | Reason                    |
| ----------------------- | ------------------------- |
| `TelemetryMinute`       | Internal projection       |
| `TelemetryHourly`       | Internal                  |
| `TelemetryDaily`        | Internal projection       |
| `AggregationCheckpoint` | Worker optimization state |
| `OutboxMessage`         | Internal integration mechanism  |
| `TelemetryRejection`    | Operational diagnostics, not part of the business API |
| MQTT Topics             | Transport protocol, not a REST resource |

### Resource-Oriented Capabilities

A REST resource is not required to correspond to a database table.

Resources such as:

```txt
/channels/{channelId}/analytics

/channels/{channelId}/consumption

/rooms/{roomId}/analytics

/rooms/{roomId}/consumption
```

represent stable business capabilities rather than persisted entities.

This principle allows the platform to evolve its internal storage, aggregation strategy, or analytical engine without introducing breaking changes to the public API.

# Authentication & Authorization

## Purpose

Authentication establishes **who or what is accessing the REST API**.

Authorization establishes **which operations and resources that authenticated principal is permitted to access**.

The two concerns are intentionally separated:

```text
Client
  ↓
Authentication
  ↓
Authenticated Principal
  ↓
Authorization
  ↓
Resource / Capability
```

Authentication and authorization are part of the **MVP API contract**. Anonymous access is not supported by the production API.

The API security model follows the public resource and capability boundaries established in SD-006 rather than the underlying database schema.


## Authentication Requirement

All REST API endpoints require authentication unless an endpoint is explicitly designated as part of a future public infrastructure surface.

For the MVP, no business, infrastructure, observation, consumption, or analytics endpoint is anonymously accessible.

A client must provide a valid bearer access token:

```http
Authorization: Bearer <access-token>
```

The API is responsible for validating the token and establishing the authenticated principal before evaluating authorization.

The concrete identity provider and token implementation are intentionally deferred.

The architecture therefore specifies the contract:

```text
Authenticated API
+
Bearer Access Token
```

without coupling the system to a specific identity provider.


## Authentication Failures

The API shall return:

```http
401 Unauthorized
```

when the request cannot be associated with a valid authenticated principal.

Examples include:

* missing access token;
* malformed access token;
* invalid access token;
* expired access token;
* token issued by an untrusted authority.

Authentication failures must not expose unnecessary information about the identity system.

The API should avoid revealing whether a particular user, token, or identity exists when such information is not required by the client.


## API Actors

The initial authorization model recognizes three conceptual actors.

### Administrator

An administrator is responsible for managing platform infrastructure and configuration.

Typical capabilities include:

* managing rooms;
* managing monitors;
* managing channels;
* managing channel assignments;
* managing energy tariffs;
* viewing telemetry;
* viewing consumption;
* viewing analytics.

### Operator

An operator interacts with the platform operationally without necessarily having full infrastructure-management privileges.

Typical capabilities include:

* viewing infrastructure;
* managing channel assignments;
* managing energy tariffs;
* viewing telemetry;
* viewing consumption;
* viewing analytics.

### Viewer

A viewer has read-only access to platform information.

Typical capabilities include:

* viewing infrastructure;
* viewing telemetry;
* viewing consumption;
* viewing analytics.

The Viewer role is intentionally separate from Operator because consuming energy information should not require permission to modify platform configuration.

## Initial Authorization Matrix

The initial conceptual authorization model is:

| Resource            | Administrator | Operator | Viewer |
| ------------------- | :-----------: | :------: | :----: |
| Rooms               |       RW      |     R    |    R   |
| Monitors            |       RW      |     R    |    R   |
| Channels            |       RW      |     R    |    R   |
| Channel Assignments |       RW      |    RW    |    R   |
| Energy Tariffs      |       RW      |    RW    |    R   |
| Telemetry           |       R       |     R    |    R   |
| Consumption         |       R       |     R    |    R   |
| Analytics           |       R       |     R    |    R   |

Where:

* **R** = Read
* **RW** = Read and Write

Delete is intentionally excluded from the initial authorization model.

This does not imply that every resource is immutable. It means that destructive deletion is not a normal capability of the MVP API.

## Authorization Failure

The API shall return:

```http
403 Forbidden
```

when:

1. the caller is successfully authenticated; but
2. the authenticated principal does not have permission to perform the requested operation.

The distinction is therefore:

```text
401 Unauthorized
    ↓
Identity cannot be established.

403 Forbidden
    ↓
Identity is known, but access is not permitted.
```

This distinction shall be consistent across all API resources.

## Capability-Based Authorization

Authorization shall be expressed in terms of **business capabilities**, not database permissions.

For example, the authorization model should express:

```text
CanViewChannelConsumption
```

rather than:

```text
CanReadTelemetryMinuteTable
```

Similarly:

```text
CanManageEnergyTariffs
```

is preferable to:

```text
CanWriteEnergyTariffTable
```

The API authorization model must remain independent of the database implementation.

This allows the underlying storage and analytical projections to change without requiring a redesign of the security model.

## Resource-Scoped Authorization

Role-based permissions establish what a principal is generally allowed to do.

Resource scope establishes **where** those permissions apply.

For example:

```text
User
  ↓
Viewer
  ↓
Room A
  ├── Channel 1
  ├── Channel 2
  └── Channel 3
```

does not necessarily imply access to:

```text
Room B
  ├── Channel 4
  └── Channel 5
```

The architecture therefore allows authorization to evolve from role-only permissions toward resource-scoped permissions.

Potential future scope hierarchy:

```text
Tenant
  ↓
Site
  ↓
Room
  ↓
Channel
```

This is not required for the current MVP but should not be prevented by the API design.

## Analytical Authorization

Analytical resources follow the same authorization model as their underlying business scope.

For example:

```text
GET /channels/{channelId}/consumption
```

requires permission to view the corresponding channel.

Likewise:

```text
GET /rooms/{roomId}/consumption
```

requires permission to view the corresponding room.

The API must not introduce independent authorization concepts for:

* `TelemetryMinute`;
* `TelemetryHourly`;
* `TelemetryDaily`.

These are internal projections and are not public security boundaries.

Authorization follows the **business capability**, not the projection used to satisfy it.

## Raw Telemetry Authorization

Raw telemetry is exposed through a bounded, read-only query capability:

```http
GET /channels/{channelId}/telemetry
```

Access to this endpoint requires read permission for the corresponding channel.

Raw telemetry cannot be:

* created through the REST API;
* modified through the REST API;
* deleted through the REST API.

Telemetry enters the system through the MQTT ingestion architecture defined by SD-004.

This maintains the separation:

```text
MQTT
 ↓
Telemetry Ingestion
 ↓
TelemetrySample
```

while the REST API provides controlled historical access:

```text
TelemetrySample
 ↓
GET /channels/{channelId}/telemetry
```

## Destructive Operations

The MVP API does not expose generic deletion for the telemetry system of record.

In particular:

```text
TelemetrySample
```

must not be deleted through the normal REST API.

This is consistent with the architectural principle that telemetry is retained permanently.

The same consideration applies to resources whose deletion could compromise historical interpretation.

Where lifecycle management is required, the preferred approach is to introduce an explicit domain operation or state transition rather than silently destroying historical data.

For example, a future resource may support:

```text
Deactivate
Archive
Retire
```

rather than:

```text
DELETE
```

This decision can be refined during the Resource Definitions chapter.

## Service-to-Service Authentication

Internal service communication is outside the public REST authentication contract.

Examples include:

```text
Telemetry Ingestion Service
        ↓
SQL Server
```

and:

```text
Outbox Publisher
        ↓
Event Transport
```

These interactions shall use appropriate service identities and credentials at implementation time.

Internal services must not rely on a public user's REST access token as their service identity.

The specific mechanisms for:

* managed identities;
* service accounts;
* client credentials;
* database credentials;
* secret management;

are implementation decisions and are not defined by SD-006.

## Development and Test Environments

Although authentication is mandatory for the MVP architecture, development environments may provide simplified identity infrastructure for local testing.

For example:

```text
Development
    ↓
Local Identity Provider
    ↓
Test Users / Test Tokens
```

A development-only authentication bypass must **not** become part of the production API contract.

Production behavior remains:

```text
No valid identity
        ↓
401 Unauthorized
```

## Identity Provider Independence

SD-006 does not prescribe a specific identity provider.

The implementation may use an OAuth 2.0 / OpenID Connect-compatible identity provider or another standards-compliant authentication infrastructure.

The public API contract depends only on the authenticated principal and its authorization claims.

The following decisions remain implementation-level concerns:

| Decision                         | Status   |
| -------------------------------- | -------- |
| Identity provider                | Deferred |
| Token issuer                     | Deferred |
| JWT implementation details       | Deferred |
| Token lifetime                   | Deferred |
| Refresh token strategy           | Deferred |
| MFA                              | Deferred |
| Identity storage                 | Deferred |
| Service-account implementation   | Deferred |
| Tenant model                     | Future   |
| Fine-grained channel permissions | Future   |

## Security Architectural Principle

The following principle is added to the SD-006 architectural principles:

> **Authorization follows business capability and resource scope, not persistence structure.**

A user's permission is expressed in terms of what they can do within the platform rather than which database objects they can access.

For example:

```text
CanViewChannelConsumption
```

is an API-level capability.

The implementation may internally read:

```text
TelemetryMinute
TelemetryHourly
TelemetryDaily
```

but those tables are not authorization boundaries.

## Security Decision Summary

The accepted SD-006 security model is:

```text
Authentication
    ↓
Mandatory for MVP
    ↓
Bearer Access Token
    ↓
Authenticated Principal
    ↓
Role / Capability
    ↓
Resource Scope
    ↓
API Operation
```

The following behaviors are established:

| Scenario                                | Result             |
| --------------------------------------- | ------------------ |
| No credentials                          | `401 Unauthorized` |
| Invalid credentials                     | `401 Unauthorized` |
| Valid identity, insufficient permission | `403 Forbidden`    |
| Authorized read                         | `2xx`              |
| Authorized write                        | `2xx`              |
| Anonymous business API access           | Not permitted      |
| Public modification of telemetry        | Not permitted      |
| Public access to internal projections   | Not permitted      |

This establishes the security boundary for SD-006 while deliberately leaving identity-provider-specific implementation decisions open.

# 5. URI Design Conventions

## 5.1 Purpose

This chapter defines the URI conventions for the Energy Analytics REST API.

The URI structure must reflect the **public resource model** established in SD-006 rather than the underlying SQL Server schema.

The API should make the following distinctions clear:

```text
Infrastructure
    ↓
Observations
    ↓
Consumption
    ↓
Analytics
```

URI design must also preserve the architectural principle that **Channel is the analytical root** while allowing higher-level resources, such as Room, to expose aggregate capabilities.

## 5.2 API Base Path

The API will use an explicit versioned base path:

```text
/api/v1
```

Therefore, public resources follow the general form:

```text
/api/v1/{resource}
```

Examples:

```text
/api/v1/rooms
/api/v1/monitors
/api/v1/channels
/api/v1/energy-tariffs
```

This makes the version boundary explicit and avoids coupling versioning to individual resources.

## 5.3 Resource Naming

Resource names shall:

* use plural nouns;
* use lowercase;
* use kebab-case for multi-word resources;
* represent domain concepts rather than database table names;
* avoid implementation terminology.

Examples:

```text
/rooms
/monitors
/channels
/channel-assignments
/energy-tariffs
```

Avoid:

```text
/Room
/TelemetryMinute
/telemetry_minute
/GetRooms
/getTelemetry
```

The URI represents a resource or capability, not an implementation class or database object.

## 5.4 Resource Identifiers

Individual resources are addressed using their public identifier:

```text
/api/v1/rooms/{roomId}

/api/v1/monitors/{monitorId}

/api/v1/channels/{channelId}
```

Identifiers are opaque to API consumers.

Clients must not infer:

* database sequence behavior;
* relationships from numeric values;
* physical topology from identifiers;
* ordering from identifiers.

For example:

```text
/api/v1/channels/42
```

means:

> The channel identified as `42`.

It does not imply that `42` is the 42nd physical channel.

## 5.5 Infrastructure Resource URIs

The primary infrastructure resources are:

```text
/api/v1/rooms
/api/v1/monitors
/api/v1/channels
/api/v1/channel-assignments
```

Relationships may be represented through nested navigation where the relationship provides meaningful context.

For example:

```text
/api/v1/monitors/{monitorId}/channels
```

can represent:

> Channels belonging to this monitor.

Likewise:

```text
/api/v1/rooms/{roomId}/channels
```

may represent:

> Channels associated with this room.

Nested resources should not be introduced merely because a database foreign key exists.

The API should expose nesting when it improves the client's understanding of the domain.

# 5.6 Analytical Resource URIs

Analytical capabilities are subordinate to their analytical subject.

For channels:

```text
/api/v1/channels/{channelId}/telemetry

/api/v1/channels/{channelId}/consumption

/api/v1/channels/{channelId}/analytics
```

For rooms:

```text
/api/v1/rooms/{roomId}/consumption

/api/v1/rooms/{roomId}/analytics
```

This reflects the analytical hierarchy:

```text
Channel
   ↓
Observation
   ↓
Consumption
   ↓
Analytics
```

and:

```text
Room
   ↓
Aggregated Consumption
   ↓
Aggregated Analytics
```

## 5.7 Telemetry URI

Raw telemetry is exposed as a **bounded historical query capability**:

```http
GET /api/v1/channels/{channelId}/telemetry
```

It is intentionally not exposed as:

```text
/api/v1/telemetry-samples
```

and individual samples are not exposed as:

```text
/api/v1/telemetry-samples/{id}
```

The reason is architectural.

`TelemetrySample` is the system of record, but an individual database row is not considered a meaningful public business resource.

The public API instead answers:

> Give me the historical observations for this analytical subject within a bounded time range.

## 5.8 Consumption URI

Consumption represents the descriptive layer of the platform:

> **What happened?**

The primary channel-level capability is:

```http
GET /api/v1/channels/{channelId}/consumption
```

Room-level consumption is:

```http
GET /api/v1/rooms/{roomId}/consumption
```

Consumption responses may internally use:

```text
TelemetryMinute
TelemetryHourly
TelemetryDaily
```

but the client must not depend on those implementation projections.

The API contract describes consumption in domain terms.

## 5.9 Analytics URI

Analytics represents the interpretive layer:

> **Why did it happen?**

The initial channel-level capability is:

```http
GET /api/v1/channels/{channelId}/analytics
```

and room-level analytics:

```http
GET /api/v1/rooms/{roomId}/analytics
```

Analytics may evolve over time to incorporate:

* anomaly detection;
* forecasting;
* efficiency analysis;
* power-quality analysis;
* consumption pattern analysis;
* future ML capabilities.

The URI structure does not need to change merely because the underlying analytical capabilities become more sophisticated.

## 5.10 Actions vs Resources

The API should avoid verb-based URIs for ordinary CRUD operations.

Avoid:

```text
POST /api/v1/create-room
GET /api/v1/get-room/1
POST /api/v1/update-channel
```

Instead:

```http
POST /api/v1/rooms
GET /api/v1/rooms/1
PATCH /api/v1/channels/1
```

Domain actions may be introduced when an operation represents a meaningful state transition that cannot be naturally expressed as ordinary resource modification.

For example, a future lifecycle capability could potentially use:

```text
POST /api/v1/channels/{channelId}/retire
```

However, such action-oriented endpoints should be explicitly justified rather than becoming the default API style.

## 5.11 HTTP Methods

The URI identifies the resource; the HTTP method identifies the operation.

The initial conventions are:

| Method   | Meaning                                                 |
| -------- | ------------------------------------------------------- |
| `GET`    | Retrieve resource or query information                  |
| `POST`   | Create resource or initiate a domain operation          |
| `PUT`    | Replace a resource representation                       |
| `PATCH`  | Partially modify a resource                             |
| `DELETE` | Delete a resource when deletion is explicitly supported |

The API should prefer the least destructive operation appropriate to the domain.

For historical resources such as telemetry, `DELETE` is not supported.

## 5.12 Query Parameters

Query parameters are used for:

* filtering;
* time ranges;
* pagination;
* sorting;
* optional analytical dimensions.

They must not change the identity of the resource.

For example:

```http
GET /api/v1/channels/42/telemetry?fromUtc=2026-05-30T00:00:00Z&toUtc=2026-05-31T00:00:00Z
```

The resource remains:

```text
Channel 42 telemetry
```

The query parameters constrain the requested representation.

## 5.13 UTC Time Parameters

All temporal query parameters must use UTC ISO-8601 timestamps.

Example:

```text
fromUtc=2026-05-30T12:00:00Z
toUtc=2026-05-30T13:00:00Z
```

The API must not accept ambiguous timestamps such as:

```text
12/05/2026 12:00
```

or local-time values without an explicit offset.

This is consistent with the aggregation architecture, where UTC defines all analytical windows.

## 5.14 Time-Range Semantics

Where a query accepts `fromUtc` and `toUtc`, the API will use half-open intervals:

```text
[fromUtc, toUtc)
```

For example:

```text
fromUtc = 12:01:00
toUtc   = 12:02:00
```

means:

```text
12:01:00 ≤ timestamp < 12:02:00
```

This is consistent with SD-005 aggregation windows and avoids ambiguity when adjacent periods are queried.

## 5.15 Nested Resources and Canonical URIs

A nested URI may be used when it communicates scope:

```text
/api/v1/channels/{channelId}/telemetry
```

However, nested resources should not imply that the child resource has a different identity.

For example:

```text
/api/v1/monitors/{monitorId}/channels/{channelId}
```

does not create a second identity for the channel.

The canonical channel resource remains:

```text
/api/v1/channels/{channelId}
```

Nested routes are navigation mechanisms.

## 5.16 URI and Persistence Independence

The following database structures must not appear as public URI resources:

```text
/telemetry-minute
/telemetry-hourly
/telemetry-daily
/aggregation-checkpoints
/outbox-messages
/telemetry-rejections
```

They are implementation or operational structures.

The public API should instead expose:

```text
/channels/{channelId}/consumption
/channels/{channelId}/analytics
```

This allows the implementation to change from:

```text
SQL projection
```

to:

```text
materialized view
```

or:

```text
cache
```

or:

```text
analytical service
```

without changing the public API.

## 5.17 Canonical URI Summary

The initial URI model is therefore:

```text
/api/v1
│
├── /rooms
│   └── /{roomId}
│       ├── /channels
│       ├── /consumption
│       └── /analytics
│
├── /monitors
│   └── /{monitorId}
│       └── /channels
│
├── /channels
│   └── /{channelId}
│       ├── /telemetry
│       ├── /consumption
│       └── /analytics
│
├── /channel-assignments
│
└── /energy-tariffs
```

This is the **architectural URI model**, not yet the complete endpoint specification. Exact operations, request schemas, response schemas, filtering options, and status codes will be defined in subsequent chapters.

## 5.18 URI Design Principles

The following rules summarize the accepted conventions:

1. All public endpoints are rooted under `/api/v1`.
2. Resource names are plural, lowercase, and domain-oriented.
3. Identifiers are opaque.
4. CRUD resources use nouns rather than verbs.
5. Analytical capabilities may use capability-oriented subordinate resources.
6. Channel is the primary analytical subject.
7. Raw telemetry is accessed through a bounded channel-scoped query.
8. Consumption represents descriptive energy usage.
9. Analytics represents interpretation and insight.
10. Database tables are never exposed merely because they exist.
11. Query parameters refine representations rather than create new resources.
12. Time-based queries use UTC and half-open intervals.
13. Nested URIs provide scope and navigation, not alternate resource identities.
14. Internal operational state is excluded from the public URI space.

