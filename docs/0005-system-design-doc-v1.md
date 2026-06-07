# System Design Documentation

## SD-001 — Define MQTT Topic Structure

### Objective

Define a topic hierarchy that:

* Supports telemetry and heartbeat messages.
* Allows the Telemetry Ingestion Service to subscribe efficiently.
* Decouples MQTT routing from business configuration.
* Supports automatic device discovery and registration.
* Scales to multiple monitors without requiring topic redesign.

---

## Design Questions

### Q1 — What should MQTT topics represent?

Two alternatives were evaluated.

#### Option A — Physical Topology

```text
mqtt/room-01/monitor-01/telemetry
```

Advantages:

* Easy to understand.
* Mirrors physical deployment.

Disadvantages:

* Couples MQTT routing to business configuration.
* Renaming a room changes MQTT topics.
* Introduces unnecessary dependencies between infrastructure and user-defined names.

Decision:

❌ Rejected

---

#### Option B — Message Type

```text
telemetry/{publisher}
heartbeat/{publisher}
```

Advantages:

* Routing based on message purpose.
* Independent of room names and user configuration.
* Easier wildcard subscriptions.

Decision:

✅ Accepted

---

### Q2 — Are channels MQTT publishers?

Two alternatives were evaluated.

#### Option A — Channel-Based Topics

```text
monitor/channel/1
monitor/channel/2
```

Advantages:

* Direct mapping between topic and channel.

Disadvantages:

* Large topic explosion.
* Channels are not independent devices.
* Complicates subscriptions.

Decision:

❌ Rejected

---

#### Option B — Channels Embedded in Payload

```json
{
  "channels": [
    ...
  ]
}
```

Advantages:

* Monitor remains the publishing unit.
* Matches physical architecture.
* Simplifies topic hierarchy.

Decision:

✅ Accepted

---

### Q3 — Should schema version be part of the topic?

Example:

```text
mqtt/v1/telemetry/{monitor}
```

Advantages:

* Explicit versioning.

Disadvantages:

* Makes versioning a routing concern.
* Subscribers must manage multiple topic versions.
* Telemetry Ingestion Service should consume all telemetry regardless of version.

Decision:

❌ Rejected

✅ Schema version remains part of the payload contract.

---


### Q4 — Should the MQTT hierarchy include an application namespace?

Two alternatives were evaluated.

#### Option A — Generic Root Topics

```text
telemetry/{deviceIdentifier}

heartbeat/{deviceIdentifier}
```

Advantages:

* Shorter topic names.
* Slightly simpler subscriptions.

Disadvantages:

* Topics become generic and less descriptive.
* Difficult to share a broker with multiple applications.
* Increases the risk of topic collisions.
* Does not clearly identify the owning application domain.

Decision:

❌ Rejected

---

#### Option B — Application Namespace

```text
power-monitor/telemetry/{deviceIdentifier}

power-monitor/heartbeat/{deviceIdentifier}
```

Advantages:

* Clearly identifies the application domain.
* Supports multiple applications sharing the same MQTT broker.
* Reduces topic collision risks.
* Aligns with MQTT topic hierarchy best practices.
* Allows future expansion without restructuring the hierarchy.

Example:

```text
power-monitor/telemetry/AABBCCDDEEFF

power-monitor/heartbeat/AABBCCDDEEFF
```

Future extensions:

```text
power-monitor/command/{deviceIdentifier}

power-monitor/configuration/{deviceIdentifier}

power-monitor/firmware-update/{deviceIdentifier}
```

Decision:

✅ Accepted

---

## Final Topic Hierarchy

```text
power-monitor/
├── telemetry/
│   └── {deviceIdentifier}
└── heartbeat/
    └── {deviceIdentifier}
```

Examples:

```text
power-monitor/telemetry/AABBCCDDEEFF

power-monitor/heartbeat/AABBCCDDEEFF
```

The MQTT topic hierarchy should identify the application domain, message type, and device identity while remaining independent from business concepts such as rooms, monitor names, or channel assignments.

This approach preserves routing stability and supports future system expansion without requiring topic redesign.

---

## Subscription Strategy

Telemetry Ingestion Service:

```text
power-monitor/telemetry/#
power-monitor/heartbeat/#
```

The service subscribes by message type and processes messages from all monitors.

---

## Device Identifier

### Definition

A stable firmware-supplied identifier that uniquely identifies a monitoring device.

Example:

```text
AABBCCDDEEFF
```

The identifier is derived from the ESP32 MAC address without separators.

---

### Properties

The identifier must be:

* Unique
* Immutable
* Firmware supplied
* Available before database registration
* Available before API configuration

---

### Database Impact

The Monitor entity must store the device identifier.

```text
Monitor
--------
Id
DeviceIdentifier
RoomId
Name
FirmwareVersion
LastHeartbeat
CreatedAtUtc
```

Rules:

* DeviceIdentifier is unique.
* DeviceIdentifier is immutable.
* DeviceIdentifier is used for MQTT routing.
* Id remains the internal database key.

---

## Device Discovery and Registration

### Discovery Flow

When a new ESP32 device is powered on:

1. The device starts publishing heartbeat messages.
2. The Telemetry Ingestion Service receives:

```text
power-monitor/heartbeat/AABBCCDDEEFF
```

3. The service attempts to locate the monitor using DeviceIdentifier.
4. If the monitor does not exist, automatic registration occurs.

---

### Registration Metadata

Heartbeat messages provide the metadata required to build the monitor topology.

Example:

```json
{
  "firmwareVersion": "1.0.0",
  "numberOfChannels": 3
}
```

---

### Auto-Registration Process

The Telemetry Ingestion Service creates:

```text
Monitor
-------
DeviceIdentifier = AABBCCDDEEFF
Name = AABBCCDDEEFF
RoomId = NULL
FirmwareVersion = 1.0.0
```

and:

```text
Channel
-------
PhysicalPort = 1

Channel
-------
PhysicalPort = 2

Channel
-------
PhysicalPort = 3
```

---

## Monitor Lifecycle

### State 1 — Discovered

A monitor exists in the system but has not yet been assigned to a room.

Example:

```text
Monitor.RoomId = NULL
```

---

### State 2 — Configured

The user assigns the monitor to a room and provides meaningful labels.

Example:

```text
Room.Name = Office

Monitor.Name = Setup PC

ChannelAssignment.Label = Monitor SFRAME 24 Pol
```

---

### State 3 — Operational

Telemetry is continuously associated with:

* Monitor
* Room
* Channel
* Channel Assignment

through the DeviceIdentifier contained in the MQTT topic.

---

## Architectural Decisions

### Accepted

✅ Topics represent message types.

✅ Monitor is the MQTT publisher.

✅ Channels are embedded in telemetry payloads.

✅ DeviceIdentifier is derived from the ESP32 MAC address.

✅ DeviceIdentifier is stored in the Monitor table.

✅ Unknown devices are automatically registered.

✅ Monitor.RoomId is nullable.

✅ Heartbeat messages provide monitor registration metadata.

---

### Rejected

❌ Topics based on room names.

❌ Topics based on channel identifiers.

❌ Schema version embedded in topic hierarchy.

❌ Auto-generated temporary rooms.

❌ MonitorAssignment table.

---

## Outputs Produced by SD-001

### MQTT Topic Hierarchy

```text
power-monitor/telemetry/{deviceIdentifier}

power-monitor/heartbeat/{deviceIdentifier}
```

### Device Registration Strategy

Automatic registration through heartbeat messages.

### Monitor Lifecycle

``Unknown → Discovered → Configured → Operational``

### Database Changes

Monitor now includes:

```text
DeviceIdentifier
```

and:

```text
RoomId
```

is nullable.

---

## Inputs for SD-002 MQTT Telemetry Payload Contract
 
Open questions:

1. Should telemetry identify channels using ChannelId or PhysicalPort?
2. Should timestamps be generated by firmware or by the ingestion service?
3. How should schema evolution be handled?
4. What validation rules are required?
5. How should telemetry batching be represented?
6. How should heartbeat and telemetry contracts relate to each other?

## SD-002 — Define MQTT Telemetry Payload Contract

### Objective

Define a telemetry contract that:

* Represents the smallest meaningful measurement unit in the system.
* Remains independent from database implementation details.
* Preserves device observations with minimal transformation.
* Supports future firmware evolution through backward-compatible changes.
* Provides sufficient information for persistence, analytics, and future forecasting use cases.

---

## Design Questions

### Q1 — How should channels be identified?

Two alternatives were evaluated.

#### Option A — Database Channel Identifier

```json
{
  "channelId": 17
}
```

Advantages:

* Direct mapping to database records.

Disadvantages:

* Couples firmware to database implementation.
* Requires synchronization between device and backend.
* Database identifiers are unknown during device discovery.

Decision:

❌ Rejected

---

#### Option B — Physical Port

```json
{
  "physicalPort": 1
}
```

Advantages:

* Native hardware concept.
* Independent of database implementation.
* Available before device registration.
* Stable throughout the device lifetime.

Decision:

✅ Accepted

---

### Q2 — Who owns the measurement timestamp?

Two alternatives were evaluated.

#### Option A — Ingestion Service Timestamp

```text
CreatedAtUtc = DateTime.UtcNow
```

Advantages:

* Simple implementation.
* No dependency on device clock.

Disadvantages:

* Loses temporal accuracy during connectivity failures.
* Prevents accurate reconstruction of historical events.
* Reduces usefulness of future forecasting and analytics.

Decision:

❌ Rejected

---

#### Option B — Device Timestamp

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z"
}
```

Advantages:

* Preserves when the measurement actually occurred.
* Supports offline buffering.
* Supports future forecasting and analytics.

Decision:

✅ Accepted

---

### Q3 — What is the telemetry granularity?

Two alternatives were evaluated.

#### Option A — Monitor Snapshot

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "channels": [
    ...
  ]
}
```

Advantages:

* Fewer MQTT messages.
* Represents a complete monitor snapshot.

Disadvantages:

* More complex buffering and retransmission.
* Failure affects multiple channel measurements.
* Increased firmware complexity.

Decision:

❌ Rejected

---

#### Option B — Single Channel Measurement

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "physicalPort": 1,
  ...
}
```

Advantages:

* Simpler firmware implementation.
* Simpler flash persistence.
* Simpler retransmission strategy.
* Failure isolation.
* Represents the smallest meaningful measurement unit.

Decision:

✅ Accepted

---

### Q4 — Who owns electrical calculations?

Two alternatives were evaluated.

#### Option A — Backend Calculates Measurements

Example:

```json
{
  "voltageVrms": 127.3,
  "currentArms": 1.82
}
```

Worker:

```text
powerW = voltageVrms × currentArms
```

Advantages:

* Smaller payload.

Disadvantages:

* Introduces business logic into the ingestion layer.
* Couples telemetry persistence to calculation strategies.
* Historical values may change when formulas evolve.

Decision:

❌ Rejected

---

#### Option B — Device Owns Measurements

Example:

```json
{
  "voltageVrms": 127.3,
  "currentArms": 1.82,
  "powerW": 231.6
}
```

Advantages:

* Preserves device observations.
* Keeps the ingestion service focused on ingestion responsibilities.
* Supports future measurement hardware and algorithms.

Decision:

✅ Accepted

---

### Q5 — Is schema versioning required?

Example:

```json
{
  "schemaVersion": 1
}
```

Advantages:

* Explicit payload versioning.

Disadvantages:

* Introduces a second versioning mechanism.
* FirmwareVersion already exists in the registration contract.
* Adds complexity without solving a current problem.

Decision:

❌ Rejected

FirmwareVersion remains the authoritative version identifier.

---

### Q6 — Should measurement units be transmitted?

Two alternatives were evaluated.

#### Option A — Units in Every Message

```json
{
  "voltage": {
    "value": 127.3,
    "unit": "V"
  }
}
```

Advantages:

* Self-describing payload.

Disadvantages:

* Increased payload size.
* Repeated metadata.
* Unnecessary for a stable contract.

Decision:

❌ Rejected

---

#### Option B — Units Defined by Contract

```json
{
  "voltageVrms": 127.3
}
```

Advantages:

* Smaller payload.
* Simpler firmware.
* Stable contract.

Decision:

✅ Accepted

---

## Telemetry Philosophy

### Architectural Principle — Telemetry Preservation

The Telemetry Ingestion Service is responsible for preserving device observations, not interpreting them.

Telemetry received from monitoring devices shall be persisted with minimal transformation.

Business calculations, analytics, forecasting, anomaly detection, and reporting are responsibilities of downstream consumers such as the Energy Analytics API and future analytics services.

---

## Validation Rules

The Telemetry Ingestion Service validates contract integrity, not business meaning.

### Accepted Validation Rules

| Rule                          | Action                                     |
| ----------------------------- | ------------------------------------------ |
| timestampUtc is missing       | Reject message and record validation error |
| timestampUtc cannot be parsed | Reject message and record validation error |
| timestampUtc is not UTC       | Reject message and record validation error |
| physicalPort <= 0             | Reject message and record validation error |

Validation failures must be persisted for traceability and troubleshooting.

---

## Required Fields

| Field        | Required |
| ------------ | -------- |
| timestampUtc | Yes      |
| physicalPort | Yes      |
| voltageVrms  | Yes      |
| currentArms  | Yes      |

---

## Optional Fields

| Field  | Required |
| ------ | -------- |
| powerW | No       |

Rationale:

The V1 monitoring hardware directly measures voltage and current through dedicated transducers.

Power may be calculated by firmware or measured through future hardware revisions and therefore is not guaranteed to be available.

---

## Measurement Units

Measurement units are defined by the telemetry contract.

| Field       | Unit            |
| ----------- | --------------- |
| voltageVrms | Volts RMS (V)   |
| currentArms | Amperes RMS (A) |
| powerW      | Watts (W)       |

Units are not transmitted within individual telemetry messages.

---

## Telemetry Contract V1

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "physicalPort": 1,
  "voltageVrms": 127.3,
  "currentArms": 1.82,
  "powerW": 231.6
}
```

---

## Database Mapping

Telemetry messages are translated by the Telemetry Ingestion Service into persistent observations.

Example:

```text
DeviceIdentifier + PhysicalPort
            ↓
        ChannelId
            ↓
     TelemetrySample
```

The telemetry contract remains independent from database identifiers and storage implementation details.

---

## Architectural Decisions

### Accepted

✅ Use PhysicalPort instead of ChannelId.

✅ Device owns measurement timestamps.

✅ One message represents one channel measurement.

✅ Preserve device observations without business interpretation.

✅ Use FirmwareVersion instead of schemaVersion.

✅ Measurement units are defined by contract.

✅ Validate contract integrity before persistence.

---

### Rejected

❌ ChannelId in telemetry payload.

❌ Ingestion-generated measurement timestamps.

❌ Monitor snapshot payloads.

❌ Backend-generated electrical measurements.

❌ schemaVersion field.

❌ Units transmitted in every telemetry message.

---

## Outputs Produced by SD-002

### Telemetry Contract V1

Single-channel measurement payload.

### Validation Strategy

Contract validation with traceable rejection logging.

### Measurement Ownership

Device is the source of truth.

### Timestamp Strategy

Device-generated UTC timestamps.

### Versioning Strategy

FirmwareVersion is the authoritative version identifier.

---

## Inputs for SD-003

The next iteration will define:

### MQTT Heartbeat Payload Contract

Open questions:

1. What metadata must a heartbeat contain?
2. Which fields are mandatory vs optional?
3. How should monitor topology changes be reported?
4. What heartbeat validation rules apply?
5. Should heartbeat support capability discovery?


## SD-003 — Define MQTT Heartbeat Payload Contract

### Objective

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

The next iteration will define:

# SD-004 — Design Ingestion Worker Service Contract

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