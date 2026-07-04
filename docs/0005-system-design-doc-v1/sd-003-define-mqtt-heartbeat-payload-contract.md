# SD-003 — Define MQTT Heartbeat Payload Contract

## Objective

Define a heartbeat contract that:

* Supports device liveness monitoring.
* Supports automatic device discovery.
* Supports automatic monitor registration.
* Supports topology discovery.
* Supports firmware tracking.
* Remains independent from business configuration.
* Minimizes payload size while preserving infrastructure metadata.

---

## Design Questions

### Q1 — What information belongs in a heartbeat?

Three alternatives were evaluated.

#### Option A — Liveness Only

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z"
}
```

Heartbeat means:

```text
I am alive.
```

Advantages:

* Extremely simple.
* Small payload.

Disadvantages:

* Cannot support device discovery.
* Cannot support automatic registration.
* Cannot support topology discovery.
* Cannot support firmware tracking.

Decision:

❌ Rejected

---

#### Option B — Liveness + Infrastructure Metadata

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0",
  "numberOfChannels": 3
}
```

Heartbeat means:

```text
I am alive.
Here is my infrastructure state.
```

Advantages:

* Supports device discovery.
* Supports automatic registration.
* Supports topology discovery.
* Supports firmware tracking.
* Remains independent from business configuration.

Decision:

✅ Accepted

---

#### Option C — Liveness + Business Metadata

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "roomName": "Office",
  "monitorName": "Setup PC"
}
```

Advantages:

* None for the current architecture.

Disadvantages:

* Couples firmware to business configuration.
* Duplicates information owned by the API.
* Creates synchronization concerns.
* Violates separation of concerns.

Decision:

❌ Rejected

---

## Q2 — Should heartbeat contain topology information?

Two alternatives were evaluated.

### Option A — Device State Only

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0"
}
```

Advantages:

* Simpler payload.

Disadvantages:

* Auto-registration cannot determine monitor topology.
* Channel creation requires manual intervention.
* Device discovery becomes incomplete.

Decision:

❌ Rejected

---

### Option B — Device State + Topology Metadata

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0",
  "numberOfChannels": 3
}
```

Advantages:

* Supports automatic monitor registration.
* Supports automatic channel creation.
* Keeps hardware topology owned by the device.
* Enables infrastructure discovery without user intervention.

Decision:

✅ Accepted

---

## Q3 — How should topology be represented?

Two alternatives were evaluated.

### Option A — Channel Count

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0",
  "numberOfChannels": 3
}
```

Advantages:

* Simple payload.
* Supports automatic channel creation.
* Sufficient for current hardware architecture.
* Avoids transmitting redundant information.

Decision:

✅ Accepted

---

### Option B — Explicit Channel Declaration

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0",
  "channels": [
    { "physicalPort": 1 },
    { "physicalPort": 2 },
    { "physicalPort": 3 }
  ]
}
```

Advantages:

* More flexible.

Disadvantages:

* More complex payload.
* Transmits information that can be derived.
* Provides no additional value for the current monitor architecture.

Decision:

❌ Rejected

---

## Q4 — Who owns the heartbeat timestamp?

Two alternatives were evaluated.

### Option A — Telemetry Ingestion Service

```text
LastHeartbeat = DateTime.UtcNow
```

Advantages:

* Simple implementation.
* No dependency on device time.

Disadvantages:

* Loses temporal accuracy.
* Prevents latency analysis.
* Reduces troubleshooting capabilities.

Decision:

❌ Rejected

---

### Option B — Device

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z"
}
```

Advantages:

* Consistent with telemetry timestamps.
* Preserves actual event time.
* Enables latency and connectivity analysis.

Decision:

✅ Accepted

---

## Q5 — What fields are mandatory versus optional?

### Mandatory Fields

| Field           | Rationale                                                    |
| --------------- | ------------------------------------------------------------ |
| timestampUtc    | Required for traceability and device timeline reconstruction |
| firmwareVersion | Required for firmware tracking and compatibility management  |

Decision:

✅ Accepted

---

### Optional Fields

| Field            | Rationale                                              |
| ---------------- | ------------------------------------------------------ |
| numberOfChannels | Required only during discovery/configuration workflows |

Decision:

✅ Accepted

---

### Rationale

Once a monitor has been registered and its channels created, topology information does not need to be continuously retransmitted.

Topology discovery is considered a registration concern rather than a runtime concern.

---

## Q6 — What validation rules apply?

Validation rules mirror the telemetry contract principles established in SD-002.

The Telemetry Ingestion Service validates contract integrity, not business meaning.

### Accepted Validation Rules

| Rule                                  | Action                                     |
| ------------------------------------- | ------------------------------------------ |
| timestampUtc missing                  | Reject message and record validation error |
| timestampUtc cannot be parsed         | Reject message and record validation error |
| timestampUtc is not UTC               | Reject message and record validation error |
| firmwareVersion missing               | Reject message and record validation error |
| firmwareVersion empty                 | Reject message and record validation error |
| numberOfChannels <= 0 (when supplied) | Reject message and record validation error |

Decision:

✅ Accepted

---

## Q7 — Should heartbeat support capability discovery?

Two alternatives were evaluated.

### Option A — Explicit Capability Declaration

```json
{
  "firmwareVersion": "2.0.0",
  "capabilities": [
    "powerMeasurement",
    "powerFactor"
  ]
}
```

Advantages:

* Explicit capability advertisement.

Disadvantages:

* Duplicates information already represented by firmware version.
* Adds contract complexity.
* Introduces another versioning mechanism.

Decision:

❌ Rejected

---

### Option B — Firmware Version as Capability Authority

```json
{
  "firmwareVersion": "2.0.0"
}
```

Advantages:

* Simpler contract.
* Single source of truth.
* Consistent with SD-002 versioning strategy.

Decision:

✅ Accepted

---

## Architectural Principles

### Device Owns Infrastructure Metadata

The monitoring device is the authoritative source of:

```text
Firmware Version
Number Of Channels
Hardware Topology
Device Timestamp
```

The API is not responsible for creating or maintaining hardware metadata.

---

### Heartbeat Does Not Contain Business Information

Heartbeat messages must not contain:

```text
Room Name
Monitor Name
Channel Assignment Labels
User Configuration
```

Business configuration belongs to the Energy Analytics API.

---

### Topology Discovery Is A Registration Concern

Topology information is primarily used during:

```text
Device Discovery
Device Registration
Channel Creation
```

and is not required for normal runtime operation.

---

## Heartbeat Contract V1

### Operational Mode

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0"
}
```

### Discovery / Configuration Mode

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0",
  "numberOfChannels": 3
}
```

---

## Device Discovery Workflow

### Unknown Device

The Telemetry Ingestion Service receives:

```text
power-monitor/heartbeat/AABBCCDDEEFF
```

Payload:

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "firmwareVersion": "1.0.0",
  "numberOfChannels": 3
}
```

The service:

1. Registers the monitor.
2. Stores the device identifier.
3. Creates the required channels.
4. Stores firmware information.
5. Marks the device as discovered.

---

## Architectural Decisions

### Accepted

✅ Heartbeat represents device liveness and infrastructure metadata.

✅ Heartbeat contains topology information.

✅ Topology is represented by `numberOfChannels`.

✅ Device owns heartbeat timestamps.

✅ `timestampUtc` is mandatory.

✅ `firmwareVersion` is mandatory.

✅ `numberOfChannels` is optional.

✅ FirmwareVersion is the authoritative capability indicator.

✅ Validation rules mirror SD-002 principles.

---

### Rejected

❌ Liveness-only heartbeat.

❌ Business metadata in heartbeat.

❌ Explicit channel declarations.

❌ Ingestion-generated heartbeat timestamps.

❌ Dedicated capability discovery contract.

---

## Outputs Produced By SD-003

### Heartbeat Contract V1

Supports:

```text
Device Liveness
Device Discovery
Topology Discovery
Firmware Tracking
```

### Registration Workflow

Supports automatic:

```text
Monitor Registration
Channel Creation
Firmware Tracking
```

### Validation Strategy

Contract validation with traceable rejection logging.

---

## Inputs For SD-004

Open questions:

1. What responsibilities belong to the Telemetry Ingestion Service?
2. What are the service inputs?
3. What are the service outputs?
4. How should device registration work?
5. What happens when validation fails?
6. What is the transaction boundary?
7. How should aggregation be executed?
8. How should the worker recover from failures?
9. What data transformations are allowed?
10. What is the worker's ownership boundary?