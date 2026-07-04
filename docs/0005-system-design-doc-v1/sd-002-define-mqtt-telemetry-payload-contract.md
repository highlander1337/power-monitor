# SD-002 — Define MQTT Telemetry Payload Contract

## Objective

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