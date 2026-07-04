# SD-004 — Design Ingestion Worker Service Contract

## Objective

Define the responsibilities, boundaries, reliability model, validation strategy, persistence strategy, and transaction model of the Telemetry Ingestion Service.

The Telemetry Ingestion Service is responsible for moving telemetry and heartbeat messages from MQTT into the persistent storage layer while preserving device observations and supporting automatic device registration.

The service is not responsible for business interpretation, analytics, forecasting, reporting, or user configuration.

---

## Design Questions

### Q1 — What are the responsibilities of the Telemetry Ingestion Service?

Several responsibilities were evaluated.

#### Option A — Persistence Only

```text
Receive
Persist
```

Advantages:

* Simple implementation.

Disadvantages:

* No contract validation.
* No device registration.
* No operational traceability.

Decision:

❌ Rejected

---

#### Option B — Capture Pipeline

```text
Receive
Validate
Register
Persist
```

Advantages:

* Supports automatic device discovery.
* Supports contract validation.
* Preserves telemetry observations.
* Keeps service focused on ingestion concerns.

Decision:

✅ Accepted

---

#### Option C — Business Processing

```text
Receive
Validate
Persist
Interpret
Analyze
Forecast
```

Advantages:

* Centralized processing.

Disadvantages:

* Violates separation of concerns.
* Couples ingestion to analytics.
* Increases complexity.

Decision:

❌ Rejected

---

## Accepted Responsibilities

The Telemetry Ingestion Service owns:

```text
Receive MQTT Messages
Validate Contracts
Register Devices
Persist Telemetry
Persist Operational Failures
```

The Telemetry Ingestion Service must not:

```text
Manage User Configuration
Interpret Business Meaning
Perform Analytics
Perform Forecasting
Generate Reports
Generate Aggregations
```

---

### Q2 — What are the service inputs?

The service consumes:

```text
Heartbeat Contract V1
Telemetry Contract V1
```

MQTT subscriptions:

```text
power-monitor/heartbeat/#

power-monitor/telemetry/#
```

Decision:

✅ Accepted

---

### Q3 — What are the service outputs?

The service produces persistent records in:

```text
Monitor
Channel
TelemetrySample
TelemetryRejection
```

The service does not generate:

```text
TelemetryMinute
TelemetryHourly
TelemetryDaily
```

Those projections belong to the Telemetry Aggregation Service.

Decision:

✅ Accepted

---

### Q4 — How should device registration work?

#### Device Discovery

When the service receives a heartbeat from an unknown device:

```text
Heartbeat Received
        ↓
Unknown Device
        ↓
Register Monitor
        ↓
Create Channels
        ↓
Commit
```

The monitor is identified by:

```text
Monitor.DeviceIdentifier
```

which is derived from:

```text
power-monitor/heartbeat/{deviceIdentifier}
```

Decision:

✅ Automatic Registration

✅ Heartbeat Driven

✅ Idempotent

---

### Q4.1 — Can monitor topology change after registration?

Example:

```text
Initial Registration

DeviceIdentifier = AABBCCDDEEFF
NumberOfChannels = 3
```

Later:

```text
DeviceIdentifier = AABBCCDDEEFF
NumberOfChannels = 4
```

Should the topology be modified?

#### Option A — Immutable Topology

The monitor topology is fixed at registration time.

Advantages:

* Simpler implementation.
* Consistent with the current home automation hardware strategy.
* Eliminates topology synchronization concerns.

Decision:

✅ Accepted

---

#### Option B — Dynamic Topology

The service updates topology when channel count changes.

Decision:

❌ Rejected

---

## Architectural Principle

```text
Monitor topology is immutable after registration.
```

A monitor cannot gain or lose channels after registration.

---

### Q5 — What happens when validation fails?

Validation failures are considered operational events.

---

### Q5.1 — Should validation failures be persisted?

#### Option A — Application Logs Only

Decision:

❌ Rejected

---

#### Option B — Database Persistence

Decision:

✅ Accepted

---

### Q5.2 — What information should be stored?

#### Option A — Minimal Record

```text
Topic
Reason
CreatedAtUtc
```

Decision:

❌ Rejected

---

#### Option B — Rich Record

```text
Id
DeviceIdentifier
Topic
Reason
Payload
CreatedAtUtc
```

Decision:

✅ Accepted

---

### Q5.3 — What type of data is a validation failure?

Validation failures are:

```text
Operational Data
```

used for:

```text
Diagnostics
Troubleshooting
Supportability
Traceability
```

Decision:

✅ Accepted

---

## Candidate Table

```text
TelemetryRejection
------------------
Id
DeviceIdentifier
Topic
Reason
Payload
CreatedAtUtc
```

---

## Architectural Principle

```text
Validation failures are first-class operational data.
```

---

### Q6 — What is the transaction boundary?

The worker follows a simple processing model:

```text
MQTT Message
      ↓
Validate
      ↓
Begin Transaction
      ↓
Persist Domain Data
      ↓
Persist Outbox Event Intent
      ↓
Commit
      ↓
Acknowledge Broker
```

Decision:

✅ Accepted

---

### Q6.1 — Should device registration be transactional?

Example:

```text
Create Monitor
Create Channels
```

If channel creation fails:

Should Monitor remain?

#### Option A — Rollback Everything

Decision:

✅ Accepted

---

#### Option B — Partial Registration

Decision:

❌ Rejected

---

## Architectural Principle

```text
Monitor registration is atomic.
```

A monitor cannot exist without its channels.

---

### Q6.2 — What happens if telemetry references an unknown channel?

Example:

```json
{
  "physicalPort": 99
}
```

while the monitor only owns:

```text
Port 1
Port 2
Port 3
```

#### Option A — Reject Message

Decision:

✅ Accepted

---

#### Option B — Auto Create Channel

Decision:

❌ Rejected

---

## Architectural Principle

```text
Topology is immutable after registration.
```

Telemetry processing must not modify monitor topology.

---

### Q7 — How should aggregation be executed?

Two alternatives were evaluated.

#### Option A — Inline Aggregation

```text
Receive
Persist
Aggregate
```

Decision:

❌ Rejected

---

#### Option B — Background Aggregation

```text
Receive
Persist
```

Later:

```text
Aggregate
```

Decision:

✅ Accepted

---

### Q7.1 — Are aggregated tables primary data?

#### Option A — Primary Data

Decision:

❌ Rejected

---

#### Option B — Disposable Projections

```text
TelemetryMinute
TelemetryHourly
TelemetryDaily
```

are projections derived from:

```text
TelemetrySample
```

Decision:

✅ Accepted

---

## Architectural Principle

```text
TelemetrySample is the system of record.
```

All aggregate tables can be rebuilt from raw telemetry.

---

### Q7.2 — Should aggregation be a separate service?

#### Option A — Single Worker

```text
Ingestion
Aggregation
```

Decision:

❌ Rejected

---

#### Option B — Separate Services

```text
Telemetry Ingestion Service
Telemetry Aggregation Service
```

Decision:

✅ Accepted

---

## Architectural Principle

```text
Capture and projection generation are separate concerns.
```

---

### Q8 — How should the system recover from failures?

---

### Q8.1 — Aggregation Service Crash

Decision:

✅ Continue from checkpoint.

---

### Q8.2 — Is AggregationCheckpoint critical data?

Decision:

❌ No

✅ Optimization state

Checkpoint loss only requires reprocessing.

---

### Q8.3 — What happens if a projection becomes corrupted?

Recovery strategy:

```text
Delete Projection
        ↓
Reset Checkpoint
        ↓
Replay TelemetrySample
```

Decision:

✅ Accepted

---

### Q8.4 — What happens if SQL Server becomes unavailable?

The MQTT Broker acts as the durability layer.

```text
ESP32
 ↓
MQTT Broker
 ↓
Telemetry Ingestion Service
 ↓
SQL Server
```

If persistence fails:

```text
No Commit
      ↓
No Acknowledgement
      ↓
Broker Retains Message
```

Decision:

✅ Broker-managed durability

❌ Local worker buffering

---

## Architectural Principle

```text
Durability belongs to the MQTT broker.
```

---

### Q8.5 — How does worker restart recovery work?

Recovery flow:

```text
Worker Restart
      ↓
Broker Restores Session
      ↓
Broker Redelivers Unacknowledged Messages
```

Decision:

✅ Accepted

---

### Q8.6 — What delivery guarantee is required?

#### Option A — At Most Once

Decision:

❌ Rejected

---

#### Option B — At Least Once

Decision:

✅ Accepted

---

#### Option C — Exactly Once

Decision:

❌ Rejected

---

## Architectural Principle

```text
No data loss is preferred over duplicate message delivery.
```

---

### Q8.7 — How should duplicate telemetry be handled?

Duplicate telemetry is expected behavior under an at-least-once delivery model.

Duplicate messages are not validation failures.

A telemetry observation is uniquely identified by:

```text
ChannelId
TimestampUtc
```

Future implementations may enforce:

```sql
UNIQUE(ChannelId, TimestampUtc)
```

to guarantee idempotent persistence.

Decision:

✅ Accepted

---

## Final Architecture

```text
ESP32
  ↓
MQTT Broker
  ↓
Telemetry Ingestion Service
  ↓
SQL Server
  ├─ Monitor
  ├─ Channel
  ├─ TelemetrySample
  └─ TelemetryRejection

Telemetry Aggregation Service
  ↓
SQL Server
  ├─ TelemetryMinute
  ├─ TelemetryHourly
  ├─ TelemetryDaily
  └─ AggregationCheckpoint

Energy Analytics API
```

---

## Architectural Principles Summary

```text
TelemetrySample = System Of Record

Aggregated Tables = Disposable Projections

AggregationCheckpoint = Optimization State

MQTT Broker = Durability Layer

Recovery = Session Based

Delivery Guarantee = At Least Once

Telemetry Persistence = Idempotent

Monitor Registration = Atomic

Topology = Immutable After Registration

Validation Failures = Operational Data
```

---

## AR-003 Alignment — Durable Telemetry Persistence Notification

### Context

SD-004 established the Telemetry Ingestion Service as the boundary responsible for:

```text
Receive
Validate
Register
Persist
Acknowledge
```

SD-005 later established that analytical projections are disposable and may need to be recomputed when late telemetry changes a previously processed aggregation window.

The cross-iteration architecture review identified a detection gap:

```text
Late Telemetry Persisted
        ↓
Previously Processed Window Becomes Stale
        ↓
Aggregation Service Must Discover the Change
```

A forward-moving aggregation checkpoint cannot, by itself, discover that an older window has become stale.

AR-003 resolved this gap through durable event notification.

---

# Q — How should persisted telemetry notify downstream aggregation?

## Option A — `CreatedAtUtc` overlap scan

The Telemetry Aggregation Service periodically scans newly persisted telemetry and derives affected historical windows.

Advantages:

- Uses existing telemetry data.
- Requires no event notification contract.

Disadvantages:

- Requires an additional scan watermark.
- Couples detection latency to polling frequency.
- Repeated scans may rediscover the same stale windows.

Decision:

❌ Rejected

---

## Option B — Dirty-window table

The Telemetry Ingestion Service records minute, hourly, and daily windows that require recomputation.

Advantages:

- Explicit invalidation state.
- Efficient targeted recomputation.

Disadvantages:

- Makes ingestion aware of aggregation window semantics.
- Couples ingestion to minute, hourly, and daily projection design.
- Weakens separation of concerns.

Decision:

❌ Rejected

---

## Option C — Event notification

After telemetry is durably persisted, the system emits a notification representing the newly available observation.

Conceptually:

```text
Telemetry Persisted
        ↓
Durable Event Intent Recorded
        ↓
Event Published
        ↓
Telemetry Aggregation Service
        ↓
Affected Windows Derived
        ↓
Required Projections Recomputed
```

Decision:

✅ Accepted

---

# Architectural Principle

```text
The Telemetry Ingestion Service announces durable observation availability.

The Telemetry Aggregation Service decides which analytical projections are affected.
```

The ingestion boundary does not emit commands such as:

```text
Recompute Minute 12:15
Recompute Hour 12:00
Recompute Day 2026-05-30
```

Those decisions remain owned by the Telemetry Aggregation Service.

---

# Telemetry Persisted Event

A conceptual event contains enough information for downstream consumers to identify the persisted observation and derive affected windows.

Example:

```json
{
  "telemetrySampleId": 123456,
  "channelId": 42,
  "timestampUtc": "2026-05-30T12:15:30Z",
  "persistedAtUtc": "2026-05-30T14:30:00Z"
}
```

The event communicates:

```text
A telemetry observation now exists durably.
```

It does not communicate business interpretation or projection commands.

The exact event envelope and transport technology remain separate implementation decisions.

---

# Q — How is event publication made reliable?

## Rejected naive dual-write

A naive flow would be:

```text
Persist TelemetrySample
        ↓
Commit SQL Transaction
        ↓
Publish Event
```

This creates a failure window:

```text
TelemetrySample committed
        ↓
Process crashes
        ↓
Event never published
```

The observation would exist durably, but downstream aggregation might never discover that a historical projection became stale.

Decision:

❌ Rejected

---

## Accepted strategy — Durable Outbox

Telemetry persistence and event intent are committed atomically.

```text
Begin Transaction
        ↓
Insert TelemetrySample
        ↓
Insert OutboxMessage
        ↓
Commit Transaction
        ↓
Acknowledge MQTT Broker
```

A separate publisher process performs:

```text
Read Pending Outbox Messages
        ↓
Publish Event
        ↓
Mark Outbox Message as Published
```

Decision:

✅ Accepted

---

# Updated Transaction Boundary

The accepted SD-004 transaction boundary becomes:

```text
MQTT Message
      ↓
Validate
      ↓
Begin Transaction
      ↓
Execute Atomic Domain Operation
      ↓
Persist Outbox Event Intent When New Telemetry Is Created
      ↓
Commit
      ↓
Acknowledge Broker
```

For telemetry persistence specifically:

```text
MQTT Telemetry Message
      ↓
Validate Contract
      ↓
Resolve Monitor
      ↓
Resolve Channel
      ↓
Begin Transaction
      ├── Insert TelemetrySample
      └── Insert OutboxMessage
      ↓
Commit
      ↓
Acknowledge Broker
```

The database transaction guarantees:

```text
TelemetrySample persisted
+
Event publication intent persisted
```

or:

```text
Neither persisted
```

---

# Registration Transaction Boundary

The previously accepted registration rule remains unchanged.

Heartbeat-driven registration is atomic:

```text
Heartbeat Received
      ↓
Unknown Device
      ↓
Begin Transaction
      ├── Create Monitor
      └── Create Channels
      ↓
Commit
```

If any registration operation fails:

```text
Rollback Everything
```

AR-003 does not require monitor registration to emit a telemetry-persisted event.

---

# Validation Failure Boundary

The previously accepted validation behavior remains unchanged.

Invalid telemetry or heartbeat messages are:

```text
Rejected
+
Persisted as Operational Traceability Data
```

using:

```text
TelemetryRejection
```

A rejected message does not produce a `TelemetryPersisted` event because no valid telemetry observation was created.

---

# Duplicate Telemetry Semantics

SD-004 established at-least-once MQTT delivery and database idempotency through:

```text
UNIQUE (
    ChannelId,
    TimestampUtc
)
```

Duplicate telemetry remains:

```text
Not a validation failure
```

When a duplicate delivery is detected:

```text
Existing TelemetrySample
        ↓
No New TelemetrySample Inserted
        ↓
No New TelemetryPersisted Event Intent Required
```

This prevents broker redelivery from creating semantically new observation notifications.

---

# MQTT Acknowledgement Rule

The accepted ordering remains:

```text
Commit
    ↓
Acknowledge Broker
```

With the outbox strategy, commit now includes durable event intent.

Therefore:

```text
TelemetrySample
+
OutboxMessage
```

must be committed before the MQTT message is acknowledged.

If the transaction fails:

```text
No Commit
    ↓
No Broker Acknowledgement
    ↓
Message Remains Eligible for Redelivery
```

---

# Event Delivery Semantics

The internal event boundary must tolerate:

```text
At Least Once Delivery
```

Therefore downstream consumers must be idempotent.

The Telemetry Aggregation Service may receive the same persisted-observation event more than once without corrupting projections.

This aligns with the broader system reliability model:

```text
MQTT Delivery
=
At Least Once
```

```text
Internal Event Delivery
=
At Least Once Compatible
```

```text
Persistence and Projection Operations
=
Idempotent
```

---

# Updated Service Responsibilities

The Telemetry Ingestion Service is responsible for:

```text
Receive MQTT Messages
Validate Contracts
Register Devices
Resolve Channels
Persist Telemetry
Persist Validation Rejections
Record Durable Event Intent
Acknowledge Broker After Commit
```

The service is not responsible for:

```text
Determine Stale Aggregation Windows
Generate Minute Projections
Generate Hourly Projections
Generate Daily Projections
Calculate Business Metrics
Forecast
Manage User Configuration
```

---

# Updated Service Outputs

The service produces or maintains:

```text
Monitor
Channel
TelemetrySample
TelemetryRejection
OutboxMessage
```

`OutboxMessage` is operational integration state. It is not business data and is not a public API resource.

---

# Failure Recovery Consequences

## Ingestion process crashes before commit

Result:

```text
TelemetrySample not committed
OutboxMessage not committed
MQTT message not acknowledged
```

The broker may redeliver the message.

---

## Ingestion process crashes after commit but before MQTT acknowledgement

Result:

```text
TelemetrySample committed
OutboxMessage committed
MQTT message may be redelivered
```

The unique telemetry constraint prevents duplicate observation creation.

No new event intent is required for the duplicate.

---

## Process crashes after commit but before event publication

Result:

```text
TelemetrySample committed
OutboxMessage pending
```

The outbox publisher later resumes publication.

The event intent is not lost.

---

## Event is published more than once

Result:

```text
Aggregation consumer receives duplicate notification
```

The Telemetry Aggregation Service must process notifications idempotently.

---

# Database Consequence

The persistence model requires an outbox table.

Conceptual structure:

```text
OutboxMessage
-------------
Id
EventType
Payload
CreatedAtUtc
PublishedAtUtc
```

The exact schema, indexing strategy, retry metadata, and event transport remain implementation-level refinements unless separately promoted into system-design decisions.

---

# Consequences for SD-005

SD-005 gains an additional service input:

```text
Telemetry Persisted Events
```

The Telemetry Aggregation Service uses the event observation timestamp to derive potentially affected:

```text
Minute Window
Hourly Window
Daily Window
```

The ingestion service remains unaware of those projection semantics.

---

# Final Decision Summary

| Decision | Result |
|---|---|
| Late telemetry notification | Event-driven |
| Event intent durability | Outbox Pattern |
| Telemetry + event intent | Same database transaction |
| MQTT acknowledgement | After commit |
| Projection-window derivation | Aggregation Service |
| Duplicate telemetry | Not a validation failure |
| Duplicate telemetry event | No new event required when no new sample is inserted |
| Event delivery | At-least-once compatible |
| Aggregation consumer | Idempotent |
| Event transport technology | Deferred |

---

# Final Architectural Principle

```text
The Telemetry Ingestion Service atomically preserves valid observations and durable notification intent.

It announces that telemetry exists.

It does not decide what analytics must be recomputed.
```

