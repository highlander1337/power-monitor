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
Execute Atomic Operation
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