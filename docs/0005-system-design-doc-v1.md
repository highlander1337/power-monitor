# System Design Iteration 01

## SD-0001 — Define MQTT Topic Structure

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

## Final Topic Hierarchy

```text
mqtt/
├── telemetry/
│   └── {deviceIdentifier}
└── heartbeat/
    └── {deviceIdentifier}
```

Examples:

```text
mqtt/telemetry/AABBCCDDEEFF

mqtt/heartbeat/AABBCCDDEEFF
```

---

## Subscription Strategy

Telemetry Ingestion Service:

```text
mqtt/telemetry/#
mqtt/heartbeat/#
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
mqtt/heartbeat/AABBCCDDEEFF
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
mqtt/telemetry/{deviceIdentifier}

mqtt/heartbeat/{deviceIdentifier}
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


