# System Design Iteration 02

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

