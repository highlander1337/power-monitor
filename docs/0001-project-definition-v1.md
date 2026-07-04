# Industrial IoT Energy Analytics Platform

## Project Overview

### Working Title

**Industrial IoT Energy Analytics Platform (IEAP)**

### Purpose

The Industrial IoT Energy Analytics Platform is a portfolio project designed to demonstrate end-to-end engineering capabilities across embedded systems, IoT architecture, backend development, data modeling, and analytics.

The platform monitors electrical energy consumption at the outlet level, processes telemetry in real time, stores historical data, and provides actionable insights through a web dashboard.

The project is intentionally designed to showcase expertise in:

- Embedded Systems Engineering
- IoT Architecture
- Event-Driven Systems
- Backend Development
- Database Modeling
- Real-Time Telemetry Processing
- Analytics and Reporting
- System Design

---

# Problem Statement

Users often lack visibility into:

- Real-time power consumption
- Historical energy usage
- Energy cost attribution
- High-consumption devices
- Standby ("phantom") energy losses

The platform provides detailed insights into energy consumption by monitoring individual outlets and aggregating data at the room level.

---

# Product Vision

Create a room-based energy monitoring platform that:

1. Measures electrical consumption per monitored outlet.
2. Provides real-time visibility into power usage.
3. Maintains a permanent historical telemetry dataset.
4. Estimates energy costs using configurable energy tariffs.
5. Enables users to assign meaningful labels to monitored outlets.
6. Preserves assignment history through time-based outlet assignments.
7. Generates disposable minute, hourly, and daily analytical projections from the permanent telemetry dataset.
8. Preserves raw telemetry as the system of record to support future anomaly detection, usage pattern analysis, and machine learning experimentation.

---

# Core Design Principles

## Principle 1: Outlet-Centric Monitoring

Channels are the source of truth. Users may assign labels to channels to represent connected devices. Telemetry remains associated with the physical channel regardless of which device is connected.

## Principle 2: Historical Assignment Preservation

Assignments are modeled using StartDateUtc and EndDateUtc.

A channel may have only one active assignment at any given time. This rule is enforced by the Energy Analytics API.

Historical reports must reflect the assignment that was active when telemetry was collected.

## Principle 3: Room-Based Monitoring

One ESP32 monitor manages multiple monitored outlets (channels) within a room.

Benefits:

- Lower hardware cost
- Multi-channel telemetry processing
- Better portfolio value
- Simplified deployment

## Principle 4: Workload-Based Architecture

Telemetry ingestion and business configuration have different characteristics.

Telemetry:
- High-frequency
- Event-driven
- Machine-generated

Business Configuration:
- Low-frequency
- User-driven
- CRUD-oriented

## Principle 5: Raw Telemetry Preservation

TelemetrySample is the canonical dataset of the platform.

Raw telemetry is retained indefinitely and serves as the source of truth for:

- Historical analytics
- Aggregation projections
- Future anomaly detection
- Future machine learning experiments
- Consumption pattern analysis

## Principle 6: Disposable Analytics Projections

Analytics projections are derived exclusively from TelemetrySample, which serves as the system of record.

Minute, hourly, and daily projections are considered disposable and may be regenerated at any time from raw telemetry.

This design simplifies recovery, supports late-arriving telemetry, and allows aggregation algorithms to evolve without risking historical data loss.

---

## Principle 6: Disposable Analytical Projections

TelemetryMinute, TelemetryHourly, and TelemetryDaily are disposable projections derived from TelemetrySample.

They may be deleted and regenerated without telemetry loss.

Projection checkpoints are optimization state only and are not a source of truth.

## Principle 7: Explicit Service Ownership

The Telemetry Ingestion Service preserves valid observations and durable event intent.

The Telemetry Aggregation Service derives telemetry-only analytical projections.

The Energy Analytics API owns business interpretation, including tariff-based cost estimation.

---

# Architecture Decision

## Hybrid Telemetry and Business Architecture

Telemetry Flow:

```
ESP32 + FreeRTOS
    ↓
MQTT Broker
    ↓
Telemetry Ingestion Service
    ↓
TelemetrySample
    ↓
Telemetry Aggregation Service
    ↓
TelemetryMinute
TelemetryHourly
TelemetryDaily
```

Business Flow:

```
Dashboard → REST API → SQL Server
```

Telemetry ingestion and business configuration use different communication patterns while sharing a common data model and database.

# Projection Strategy

The platform distinguishes between permanent telemetry observations and disposable analytical projections.

TelemetrySample is the only permanent telemetry dataset and serves as the system of record.

Minute, hourly and daily projections are regenerated from TelemetrySample and exist solely to improve query performance.

Business information, such as energy cost estimation, is intentionally excluded from the aggregation layer and calculated by the Energy Analytics API.

---

# System Architecture

```
    Web Dashboard
            ↓ REST
    Energy Analytics API
            ↓
        SQL Server
        ↑     ↑
        │     │
    Telemetry   Telemetry
    Aggregation Ingestion
    Service      Service
        ↑
    TelemetrySample
        ↑
    MQTT Broker
        ↑
    ESP32 + FreeRTOS
```

---

# Solution Structure

EnergyAnalytics.sln

- Energy.Domain
- Energy.Infrastructure
- Energy.TelemetryIngestion
- Energy.TelemetryAggregation
- Energy.API
- Energy.Dashboard

---

# Shared Infrastructure Layer

## Energy.Domain

Contains:

- Room
- Monitor
- Channel
- ChannelAssignment
- TelemetrySample
- TelemetryMinute
- TelemetryHourly
- TelemetryDaily
- EnergyTariff
- TelemetryRejection
- AggregationCheckpoint
- OutboxMessage

## Energy.Infrastructure

Contains:

- DbContext
- EF Core Configurations
- Repositories
- Database Migrations

---

# Component Responsibilities

## ESP32 Room Monitor

- Sensor acquisition
- Voltage/current measurement
- Power calculation
- MQTT publishing
- Heartbeat reporting

## Telemetry Ingestion Service

- MQTT subscriptions
- Telemetry and heartbeat contract validation
- Heartbeat-driven monitor registration
- Channel resolution
- Telemetry persistence
- Heartbeat tracking
- Validation rejection persistence
- Durable outbox event-intent persistence
- MQTT acknowledgement after successful commit

Owns:

- TelemetrySample
- TelemetryRejection
- OutboxMessage
- Heartbeat-driven Monitor and Channel registration behavior

Does not own:

- Minute aggregation
- Hourly aggregation
- Daily aggregation
- Business cost calculations

## Telemetry Aggregation Service

- Consumes telemetry-persisted notifications
- Reads TelemetrySample as the canonical aggregation source
- Generates minute, hourly, and daily disposable projections
- Calculates energy through numerical integration of the available supported power curve
- Calculates time-weighted average power over observed duration
- Tracks projection completeness
- Maintains independent minute, hourly, and daily checkpoints
- Recomputes affected historical windows when late telemetry arrives
- Performs idempotent projection upserts

Owns:

- TelemetryMinute
- TelemetryHourly
- TelemetryDaily
- AggregationCheckpoint

Does not own:

- MQTT telemetry ingestion
- Telemetry contract validation
- Monitor registration
- Energy tariff interpretation
- Cost estimation
- Forecasting or machine learning
## Energy Analytics API

- Room management
- Monitor management
- Channel management
- Channel assignment management
- Energy tariff management
- Analytics APIs
- Reporting APIs
- Business calculations
- Cost estimation

---

# Telemetry Model

Telemetry Contract V1 represents one physical-port observation per MQTT message.

Example payload:

```json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "physicalPort": 1,
  "voltageVrms": 127.3,
  "currentArms": 1.82,
  "powerW": 231.6
}
```

Contract requirements:

- `timestampUtc` is mandatory and device-owned.
- `physicalPort` is mandatory and greater than zero.
- `voltageVrms` is mandatory.
- `currentArms` is mandatory.
- `powerW` is mandatory and firmware-supplied.
- Measurement units are explicit through contract-by-design field names.
- The backend does not derive missing power from voltage and current.

---

# Telemetry Aggregation Strategy

`TelemetrySample` is always the canonical source for all analytical projections.

```text
TelemetrySample → TelemetryMinute
TelemetrySample → TelemetryHourly
TelemetrySample → TelemetryDaily
```

Minute, hourly, and daily projections are disposable and may always be regenerated from `TelemetrySample`.

Aggregation windows use half-open UTC intervals:

```text
Minute: [MinuteUtc, MinuteUtc + 1 minute)
Hourly: [HourUtc, HourUtc + 1 hour)
Daily: [DateUtc 00:00:00Z, NextDateUtc 00:00:00Z)
```

Energy is calculated by numerical integration of the available supported power curve. Missing telemetry is not manufactured, and integration does not cross projection boundaries.

`AvgPowerW` is the time-weighted average power over `ObservedDurationSeconds` and is derived from the same integrated curve used for `EnergyConsumedWh`.

For projections where `ObservedDurationSeconds > 0`:

```text
AvgPowerW
=
EnergyConsumedWh × 3600
/
ObservedDurationSeconds
```

Projection completeness is represented by:

- `ObservedDurationSeconds`
- `ExpectedDurationSeconds`
- `CoverageRatio`

A projection row is not created when `ObservedDurationSeconds = 0`.

`AggregationCheckpoint` tracks forward-processing progress independently for minute, hourly, and daily jobs. Checkpoints are optimization state only.

Late telemetry is detected through durable telemetry-persisted events. The Aggregation Service derives affected historical windows and recomputes them from `TelemetrySample` using idempotent upserts.
---

# Data Model

## Room

- Id
- Name
- CreatedAtUtc

## Monitor

- Id
- DeviceIdentifier
- RoomId
- Name
- FirmwareVersion
- LastHeartbeatUtc
- CreatedAtUtc

## Channel

- Id
- MonitorId
- PhysicalPort
- CreatedAtUtc

Unique Constraint:

(MonitorId, PhysicalPort)

## ChannelAssignment

- Id
- ChannelId
- Label
- StartDateUtc
- EndDateUtc

Business Rule:

Only one active assignment may exist for a channel at a given point in time.

## TelemetrySample

- Id
- ChannelId
- TimestampUtc
- Voltage
- Current
- Power
- CreatedAtUtc

Unique Constraint

(ChannelId, TimestampUtc)

## TelemetryRejection

Operational telemetry persistence.

Stores messages rejected during ingestion.

- DeviceIdentifier
- Topic
- Reason
- Payload
- CreatedAtUtc

## TelemetryMinute
Minute-level analytics projection.

- SampleCount
- MinPowerW
- MaxPowerW
- AvgPowerW
- EnergyConsumedWh
- ObservedDurationSeconds
- ExpectedDurationSeconds
- CoverageRatio


Composite Key:

(ChannelId, MinuteUtc)

## TelemetryHourly

Hourly analytics projection.

- SampleCount
- MinPowerW
- MaxPowerW
- AvgPowerW
- EnergyConsumedWh
- ObservedDurationSeconds
- ExpectedDurationSeconds
- CoverageRatio

Composite Key:

(ChannelId, HourUtc)

## TelemetryDaily

Daily analytics projection.

- SampleCount
- MinPowerW
- MaxPowerW
- AvgPowerW
- EnergyConsumedWh

Composite Key:

(ChannelId, DateUtc)

## EnergyTariff

- Id
- Name
- CostPerKWh
- EffectiveFromUtc
- EffectiveToUtc

## AggregationCheckpoint

- AggregationName
- LastProcessedUtc
- UpdatedAtUtc

---

# MVP Scope

## Hardware

Included:

- ESP32
- FreeRTOS
- Multi-channel monitoring
- MQTT communication

## Telemetry Ingestion Service

- MQTT subscriptions
- Telemetry and heartbeat contract validation
- Heartbeat-driven monitor registration
- Channel resolution
- Telemetry persistence
- Heartbeat tracking
- Validation rejection persistence
- Durable outbox event-intent persistence
- MQTT acknowledgement after successful commit

Owns:

- TelemetrySample
- TelemetryRejection
- OutboxMessage
- Heartbeat-driven Monitor and Channel registration behavior

Does not own:

- Minute aggregation
- Hourly aggregation
- Daily aggregation
- Business cost calculations

## Telemetry Aggregation Service

- Consumes telemetry-persisted notifications
- Reads TelemetrySample as the canonical aggregation source
- Generates minute, hourly, and daily disposable projections
- Calculates energy through numerical integration of the available supported power curve
- Calculates time-weighted average power over observed duration
- Tracks projection completeness
- Maintains independent minute, hourly, and daily checkpoints
- Recomputes affected historical windows when late telemetry arrives
- Performs idempotent projection upserts

Owns:

- TelemetryMinute
- TelemetryHourly
- TelemetryDaily
- AggregationCheckpoint

Does not own:

- MQTT telemetry ingestion
- Telemetry contract validation
- Monitor registration
- Energy tariff interpretation
- Cost estimation
- Forecasting or machine learning
## Telemetry Aggregation Service

Included:

- Telemetry Persisted Event Consumption
- Minute Aggregation
- Hourly Aggregation
- Daily Aggregation
- Numerical Energy Integration
- Projection Completeness Metrics
- Late-Telemetry Recalculation
- Aggregation Checkpoints

## Energy Analytics API

Included:

- Room Management
- Monitor Management
- Channel Management
- Channel Assignments
- Energy Tariff Management
- Historical Queries

## Dashboard

Included:

- Real-time monitoring
- Historical analytics
- Configuration management
- Cost reporting

---

# Analytics Features

## Real-Time Monitoring

- RMS Voltage (V)
- RMS Current (A)
- Power (W)

## Historical Analytics

- Daily consumption
- Weekly consumption
- Monthly consumption
- Peak consumption periods

## Cost Estimation

Energy costs are calculated by the Energy Analytics API using aggregated energy consumption together with the applicable EnergyTariff.

The Telemetry Aggregation Service remains independent from business pricing rules.

## Historical Assignment Awareness

Consumption is attributed using the assignment active at the time of measurement.

---

# Future Enhancements

## Phase 2

- Historical trend analysis
- Room comparisons
- Report exports

## Phase 3

- Consumption anomaly detection
- Phantom load detection
- Consumption alerts

## Phase 4

- Consumption pattern clustering
- Usage behavior classification
- Device activity inference
- Predictive consumption forecasting

## Phase 5

- OTA firmware updates
- Multi-monitor deployments
- Remote access
- Advanced machine learning analytics

---

# Success Criteria

1. ESP32 publishes telemetry reliably through MQTT.
2. TelemetrySample records are persisted successfully.
3. Raw telemetry is preserved as the permanent system of record.
4. Minute, hourly and daily projections are generated correctly from TelemetrySample.
5. Projection tables can be safely rebuilt from raw telemetry.
6. AggregationCheckpoint enables resumable aggregation after interruptions.
7. Late-arriving telemetry correctly triggers retroactive projection recomputation.
8. The Energy Analytics API produces business metrics independently from telemetry aggregation.
9. Energy tariffs support accurate cost estimation.
10. Historical assignment tracking remains accurate over time.
11. Dashboard displays real-time and historical analytics.
12. The solution demonstrates a complete IoT telemetry platform suitable for future machine learning experimentation.
