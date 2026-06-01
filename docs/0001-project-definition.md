# Industrial IoT Energy Analytics Platform

## Project Overview

### Working Title

**Industrial IoT Energy Analytics Platform (IEAP)**

### Purpose

The Industrial IoT Energy Analytics Platform is a portfolio project designed to demonstrate end-to-end engineering capabilities across embedded systems, IoT architecture, backend development, data modeling, and analytics.

The platform monitors electrical energy consumption at the outlet level, processes telemetry in real time, stores historical data, and provides actionable insights through a web dashboard.

The project is intentionally designed to showcase expertise in:

* Embedded Systems Engineering
* IoT Architecture
* Event-Driven Systems
* Backend Development
* Database Modeling
* Real-Time Telemetry Processing
* Analytics and Reporting
* System Design

---

# Problem Statement

Users often lack visibility into:

* Real-time power consumption
* Historical energy usage
* Energy cost attribution
* High-consumption devices
* Standby ("phantom") energy losses

The platform provides detailed insights into energy consumption by monitoring individual outlets and aggregating data at the room level.

---

# Product Vision

Create a room-based energy monitoring platform that:

1. Measures electrical consumption per monitored outlet.
2. Provides real-time visibility into power usage.
3. Maintains historical telemetry records.
4. Estimates energy costs.
5. Enables users to assign meaningful labels to monitored outlets.
6. Preserves assignment history over time.
7. Supports future expansion into analytics, anomaly detection, and predictive insights.

---

# Core Design Principles

---

## Principle 1: Outlet-Centric Monitoring

The system measures electrical consumption per monitored outlet (channel).

Channels are the source of truth.

Users may assign labels to channels to represent connected devices.

### Example

```text
Channel 1
Label: Gaming PC
```

The telemetry remains associated with the physical channel regardless of which device is connected.

---

## Principle 2: Historical Metadata Preservation

Device assignments are stored as metadata.

Assignments are time-bound and preserve historical context.

### Example

```text
May:
Channel 1 → Gaming PC

June:
Channel 1 → 3D Printer
```

Historical reports accurately reflect the assignment that existed when telemetry was collected.

---

## Principle 3: Room-Based Monitoring

One ESP32 device monitors multiple electrical channels within a room.

### Example

```text
Office Monitor

Channel 1 → Gaming PC
Channel 2 → Monitor
Channel 3 → Router
Channel 4 → TV
```

### Benefits

* Lower hardware cost
* More interesting embedded design
* Multi-channel telemetry processing
* Better portfolio value

---

## Principle 4: Workload-Based Architecture

The platform separates responsibilities according to workload characteristics rather than technical layers.

Telemetry ingestion and business configuration have fundamentally different operational requirements.

### Telemetry Workload

Characteristics:

* High-frequency
* Event-driven
* Machine-generated
* Write-heavy
* Continuous

Examples:

* Voltage readings
* Current measurements
* Power calculations
* Heartbeat messages

### Business Workload

Characteristics:

* Low-frequency
* User-driven
* CRUD-oriented
* Read-heavy

Examples:

* Create room
* Configure channel
* Assign labels
* Define tariffs
* View analytics

---

# Architecture Decision

## Hybrid Telemetry and Business Architecture

Telemetry ingestion and business configuration follow different communication patterns.

### Telemetry Flow

```text
ESP32
    ↓ MQTT
Mosquitto Broker
    ↓
Telemetry Ingestion Service
    ↓
SQL Server
```

### Business Configuration Flow

```text
Dashboard
    ↓ REST
Energy Analytics API
    ↓
SQL Server
```

### Architectural Rationale

Telemetry ingestion and business configuration have different characteristics.

MQTT and a dedicated ingestion service are used for high-frequency telemetry workloads, while REST APIs handle low-frequency configuration and analytics workloads.

Both services share a common data model and persist to SQL Server.

---

# System Architecture

```text
                    ┌─────────────────────┐
                    │  Web Dashboard      │
                    └──────────┬──────────┘
                               │ REST
                               ▼
                    ┌─────────────────────┐
                    │ Energy Analytics    │
                    │ API                 │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ SQL Server          │
                    └──────────▲──────────┘
                               │
                               │ EF Core
                               │
                    ┌──────────┴──────────┐
                    │ Telemetry Ingestion │
                    │ Service             │
                    └──────────▲──────────┘
                               │ MQTT
                               ▼
                    ┌─────────────────────┐
                    │ Mosquitto Broker    │
                    └──────────▲──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ ESP32 + FreeRTOS    │
                    │ Room Monitor        │
                    └─────────────────────┘
```

---

# Solution Structure

```text
EnergyAnalytics.sln

├── Energy.Domain
│
├── Energy.Infrastructure
│
├── Energy.TelemetryIngestion
│
├── Energy.API
│
└── Energy.Dashboard
```

---

# Shared Infrastructure Layer

The platform uses a shared infrastructure layer.

---

## Energy.Domain

Contains:

* Entities
* Value Objects
* Domain Models
* Shared Contracts

### Examples

* Room
* Channel
* ChannelAssignment
* TelemetryRaw
* TelemetryHourly
* DeviceHeartbeat

---

## Energy.Infrastructure

Contains:

* DbContext
* EF Core Configurations
* Repositories
* Database Migrations

Shared by:

* Energy.TelemetryIngestion
* Energy.API

---

# Component Responsibilities

---

## ESP32 Room Monitor

### Responsibilities

* Sensor acquisition
* Power calculations
* Energy accumulation
* MQTT publishing
* Device health reporting

### Technology

* ESP32
* FreeRTOS

---

## Mosquitto Broker

### Responsibilities

* MQTT message transport
* Topic routing
* Reliable telemetry delivery

### Technology

* Mosquitto MQTT Broker

---

## Telemetry Ingestion Service

### Technology

* .NET Worker Service

### Responsibilities

* MQTT subscriptions
* Payload validation
* Telemetry persistence
* Heartbeat tracking
* Telemetry aggregation
* Future anomaly detection

### Owns

* TelemetryRaw
* TelemetryMinute
* TelemetryHourly
* TelemetryDaily
* DeviceHeartbeat

---

## Energy Analytics API

### Technology

* ASP.NET Core Web API

### Responsibilities

* Room management
* Channel management
* Channel assignment management
* Energy tariff configuration
* Dashboard APIs
* Analytics APIs
* Reporting APIs

### Owns

* Rooms
* Channels
* ChannelAssignments
* EnergyTariffs
* UserPreferences

---

## SQL Server

### Responsibilities

* Persistent storage
* Historical telemetry
* Aggregated telemetry
* Business configuration data

---

## Dashboard

### Responsibilities

* Real-time monitoring
* Historical visualization
* Configuration management
* Analytics presentation

---

# Communication Patterns

---

## MQTT

Used for:

* Telemetry ingestion
* Device heartbeats
* Future command topics

### Example Topics

```text
energy/office/telemetry
energy/livingroom/telemetry
energy/kitchen/telemetry
```

### Rationale

MQTT is optimized for lightweight, event-driven communication between embedded devices and backend services.

The Energy Analytics API does not subscribe to MQTT topics.

The Telemetry Ingestion Service is the sole telemetry consumer.

---

## REST

Used for:

* Room management
* Channel management
* Assignment management
* Analytics retrieval
* Dashboard operations

### Rationale

REST is optimized for user-driven CRUD and reporting operations.

---

# Embedded System Design

## Platform

ESP32

## Operating System

FreeRTOS

---

## Initial Task Structure

| Task             | Purpose                   | Frequency    |
| ---------------- | ------------------------- | ------------ |
| Sensor Task      | Read sensors              | 100 ms       |
| Calculation Task | Compute power metrics     | 500 ms       |
| MQTT Publisher   | Publish telemetry         | 1 sec        |
| Health Task      | Diagnostics and heartbeat | 10 sec       |
| OTA Task         | Future enhancement        | Event Driven |

---

# Telemetry Model

The ESP32 publishes processed telemetry instead of raw sensor samples.

### Example Payload

```json
{
  "schemaVersion": 1,
  "monitorId": "office-01",
  "roomId": "office",
  "timestamp": "2026-05-30T18:30:00Z",
  "channels": [
    {
      "channelId": 1,
      "power": 220
    },
    {
      "channelId": 2,
      "power": 45
    },
    {
      "channelId": 3,
      "power": 12
    }
  ]
}
```

---

# Data Model

---

## Room

| Field  |
| ------ |
| RoomId |
| Name   |

---

## Monitor

| Field           |
| --------------- |
| MonitorId       |
| RoomId          |
| FirmwareVersion |
| LastHeartbeat   |

---

## Channel

| Field        |
| ------------ |
| ChannelId    |
| MonitorId    |
| PhysicalPort |

---

## ChannelAssignment

| Field        |
| ------------ |
| AssignmentId |
| ChannelId    |
| Label        |
| StartDate    |
| EndDate      |

---

## TelemetryRaw

| Field       |
| ----------- |
| TelemetryId |
| ChannelId   |
| Timestamp   |
| Voltage     |
| Current     |
| Power       |

---

## TelemetryHourly

| Field          |
| -------------- |
| ChannelId      |
| Hour           |
| AveragePower   |
| EnergyConsumed |

---

## TelemetryDaily

| Field          |
| -------------- |
| ChannelId      |
| Date           |
| EnergyConsumed |
| EstimatedCost  |

---

# MVP Scope

---

## Hardware

### Included

* ESP32
* FreeRTOS
* Multi-channel monitoring
* MQTT communication

### Excluded

* OTA updates
* Device recognition
* Multi-monitor deployments

---

## Telemetry Ingestion Service

### Included

* MQTT Consumer
* Payload Validation
* Telemetry Persistence
* Heartbeat Monitoring
* Aggregation Jobs

---

## Energy Analytics API

### Included

* Room Management
* Channel Management
* Channel Assignments
* Energy Tariff Management
* Historical Queries

---

## Dashboard

### Included

#### Overview

* Current total consumption
* Room consumption
* System health

#### Channel View

* Current outlet consumption
* Assigned labels
* Real-time telemetry

#### Historical View

* Daily consumption
* Weekly consumption
* Monthly consumption

#### Configuration

* Room setup
* Channel naming
* Energy tariff configuration

---

# Analytics Features (MVP)

## Real-Time Monitoring

Display:

* Current Power (W)
* Voltage (V)
* Current (A)

---

## Energy Consumption

Display:

* Daily kWh
* Weekly kWh
* Monthly kWh

---

## Cost Estimation

User defines:

```text
Energy Price = R$/kWh
```

System calculates:

* Daily cost
* Monthly projection
* Historical cost

---

## Top Consumers

Rank channels by:

* Total energy consumption
* Monthly consumption
* Cost contribution

---

# Future Enhancements

## Phase 2

* Historical trend analysis
* Room comparisons
* Report exports

## Phase 3

* Anomaly detection
* Phantom load detection
* Consumption alerts

## Phase 4

* Device recognition
* Machine learning classification
* Predictive consumption forecasting

## Phase 5

* OTA firmware updates
* Multi-room deployments
* Remote access

---

# Architectural Positioning

This project intentionally demonstrates both IoT and backend engineering concepts.

| Domain           | Technologies                                |
| ---------------- | ------------------------------------------- |
| Embedded Systems | ESP32, FreeRTOS                             |
| IoT              | MQTT, Mosquitto                             |
| Backend          | ASP.NET Core, Worker Services               |
| Data             | SQL Server, EF Core                         |
| Architecture     | Event-Driven Systems, Shared Infrastructure |
| Analytics        | Aggregation, Cost Modeling                  |

---

# Success Criteria

The project will be considered successful when:

1. ESP32 publishes telemetry reliably through MQTT.
2. The Telemetry Ingestion Service consumes and persists telemetry successfully.
3. SQL Server stores both telemetry and business configuration data.
4. The Energy Analytics API provides analytics and configuration endpoints.
5. The dashboard displays real-time and historical consumption data.
6. Users can assign and manage outlet labels.
7. Energy cost estimation functions correctly.
8. The solution demonstrates a complete Industrial IoT architecture suitable for a professional engineering portfolio.
