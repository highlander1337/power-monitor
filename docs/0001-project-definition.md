# Energy Analytics Platform (Portfolio Project)

## Project Overview

### Working Title

**Energy Analytics Platform (EAP)**

### Purpose

The Energy Analytics Platform is an Industrial IoT-inspired portfolio project designed to monitor electrical energy consumption at the outlet level within residential or small commercial environments.

The project demonstrates expertise across multiple disciplines:

* Embedded Systems (ESP32 + FreeRTOS)
* IoT Architecture
* MQTT Messaging
* Backend Development (.NET)
* Database Design (SQL Server)
* Telemetry Processing
* Real-Time Monitoring
* Analytics and Reporting

The primary goal is not commercial deployment but rather to showcase end-to-end system design and implementation capabilities.

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

Create a room-based energy monitoring system that:

1. Measures electrical consumption per monitored outlet.
2. Provides real-time visibility into power usage.
3. Maintains historical telemetry records.
4. Estimates energy costs.
5. Enables users to assign meaningful labels to monitored outlets.
6. Supports future expansion into analytics, anomaly detection, and predictive insights.

---

# Core Design Decisions

## Decision 1: Outlet-Centric Architecture

### Chosen Approach

The system measures energy consumption per physical outlet/channel.

### Rationale

Physical channels remain constant while connected devices may change over time.

Monitoring outlets instead of devices simplifies:

* Data modeling
* Historical reporting
* Firmware design
* User management

### Example

Instead of:

```text
Gaming PC = Channel 1
```

The system stores:

```text
Channel 1
Label: Gaming PC
```

The label may change later without affecting telemetry history.

---

## Decision 2: Metadata-Based Device Assignment

Devices are represented as metadata attached to channels.

### Example

Channel 1:

```text
May:
Gaming PC

June:
3D Printer

July:
Air Conditioner
```

The telemetry remains tied to Channel 1.

Historical reports can reconstruct which device was assigned during any given period.

---

## Decision 3: Room-Based Monitoring

### Chosen Architecture

One ESP32 monitors multiple outlets within a room.

### Example

Office Monitor:

```text
Channel 1 → Gaming PC
Channel 2 → Monitor
Channel 3 → Router
Channel 4 → TV
```

### Benefits

* Reduced hardware cost
* More interesting embedded design
* Multi-channel acquisition challenges
* Better portfolio value

---

## Decision 4: Local Infrastructure

### Messaging

MQTT Broker (Local)

Recommended:

* Mosquitto

### Backend

* ASP.NET Core Web API
* .NET Worker Service

### Database

* SQL Server

### Reason

Avoid recurring cloud costs while maintaining a realistic IoT architecture.

---

# System Architecture

```text
┌─────────────────────────┐
│     ESP32 + FreeRTOS    │
│  Multi-Channel Monitor  │
└────────────┬────────────┘
             │ MQTT
             ▼
┌─────────────────────────┐
│     Mosquitto Broker    │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  .NET MQTT Consumer     │
│    Worker Service       │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│      SQL Server         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│     ASP.NET Core API    │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│    Web Dashboard        │
└─────────────────────────┘
```

---

# Embedded System Design

## Platform

ESP32

## Operating System

FreeRTOS

## Responsibilities

* Sensor acquisition
* Power calculations
* Energy accumulation
* MQTT publishing
* Device diagnostics

---

## Initial Task Structure

| Task             | Purpose                    | Frequency    |
| ---------------- | -------------------------- | ------------ |
| Sensor Task      | Read sensor values         | 100 ms       |
| Calculation Task | Compute electrical metrics | 500 ms       |
| MQTT Task        | Publish telemetry          | 1 sec        |
| Health Task      | Diagnostics and heartbeat  | 10 sec       |
| OTA Task         | Future enhancement         | Event Driven |

---

# Telemetry Model

## Channel Telemetry

The ESP32 publishes processed telemetry instead of raw sensor samples.

### Example Payload

```json
{
  "roomId": "office",
  "timestamp": "2026-05-30T18:30:00Z",
  "channels": [
    {
      "channel": 1,
      "power": 220
    },
    {
      "channel": 2,
      "power": 45
    },
    {
      "channel": 3,
      "power": 12
    }
  ]
}
```

---

# MQTT Design

## Topic Structure

```text
energy/{room}/telemetry
```

Example:

```text
energy/office/telemetry
energy/livingroom/telemetry
energy/kitchen/telemetry
```

---

# Data Model

## Room

| Field  |
| ------ |
| RoomId |
| Name   |

---

## Monitor

Represents a physical ESP32.

| Field           |
| --------------- |
| MonitorId       |
| RoomId          |
| FirmwareVersion |
| LastHeartbeat   |

---

## Channel

Represents a physical monitored outlet.

| Field        |
| ------------ |
| ChannelId    |
| MonitorId    |
| PhysicalPort |

---

## Channel Assignment

Stores metadata labels and preserves history.

| Field        |
| ------------ |
| AssignmentId |
| ChannelId    |
| Label        |
| StartDate    |
| EndDate      |

---

## TelemetryRaw

Stores raw telemetry records.

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

Aggregated telemetry.

| Field          |
| -------------- |
| ChannelId      |
| Hour           |
| AveragePower   |
| EnergyConsumed |

---

## TelemetryDaily

Daily analytics.

| Field          |
| -------------- |
| ChannelId      |
| Date           |
| EnergyConsumed |
| EstimatedCost  |

---

# MVP Scope

## Hardware

### Included

* ESP32
* FreeRTOS
* Multi-channel monitoring
* MQTT communication

### Excluded

* OTA updates
* Wireless sensor expansion
* Device recognition

---

## Backend

### Included

* MQTT Consumer Service
* ASP.NET Core API
* SQL Server persistence
* Aggregation jobs

---

## Dashboard

### Included

#### Overview Page

Displays:

* Current total consumption
* Room consumption
* System status

#### Channel View

Displays:

* Outlet consumption
* Channel labels
* Current power usage

#### Historical View

Displays:

* Daily consumption
* Weekly consumption
* Monthly consumption

#### Configuration

Allows:

* Channel naming
* Room configuration

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

User enters:

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
* Export reports

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

# Success Criteria

The project will be considered successful when:

1. ESP32 publishes telemetry reliably through MQTT.
2. Backend persists telemetry into SQL Server.
3. Dashboard displays real-time outlet consumption.
4. Historical analytics are available.
5. Users can assign and manage outlet labels.
6. Energy cost estimation functions correctly.
7. The solution demonstrates a complete end-to-end Industrial IoT architecture suitable for a professional engineering portfolio.

