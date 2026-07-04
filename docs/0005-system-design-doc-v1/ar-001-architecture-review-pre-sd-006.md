# Architecture Review --- Telemetry Pipeline Alignment Before SD-006

## Document Purpose

This document records the final cross-iteration architecture review
performed after SD-002 through SD-005 and before SD-006 --- Design REST
API Contract.

The review exists to prevent SD-006 from exposing API contracts on top
of stale, contradictory, or underspecified telemetry architecture.

The review focuses on decisions that emerged across multiple
system-design chapters rather than inside a single component boundary.

Reviewed design documents:

-   SD-002 --- Define Telemetry Contract V1
-   SD-003 --- Define Heartbeat Contract V1
-   SD-004 --- Design Ingestion Worker Service Contract
-   SD-005 --- Design Telemetry Aggregation Service

Primary review range:

``` text
Firmware Observation Contract
        ↓
MQTT Delivery
        ↓
Telemetry Ingestion
        ↓
Durable Persistence
        ↓
Durable Event Notification
        ↓
Telemetry Aggregation
        ↓
Disposable Analytical Projections
        ↓
Future REST API Contract
```

------------------------------------------------------------------------

# 1. Review Objectives

The review had five objectives:

1.  Identify contradictions introduced as later design decisions refined
    earlier assumptions.
2.  Confirm service ownership boundaries before defining public REST
    resources.
3.  Formalize numerical aggregation semantics.
4.  Define how late telemetry invalidates already-generated projections.
5.  Ensure the database model and project definition reflect the
    accepted architecture.

The review intentionally avoids redesigning MQTT topic architecture
beyond what was already accepted in SD-001 through SD-003.

The backend must remain maintainable enough to accommodate future MQTT
changes without forcing broad architectural redesign.

------------------------------------------------------------------------

# 2. Executive Summary

The review identified five architecture issues requiring explicit
resolution.

  ---------------------------------------------------------------------------------
  Review Item       Issue             Resolution                  Status
  ----------------- ----------------- --------------------------- -----------------
  AR-001            `powerW`          `powerW` is mandatory in    Resolved
                    optionality       Telemetry Contract V1       
                    conflicted with                               
                    aggregation                                   
                    requirements                                  

  AR-002            Numerical         Integrate the available     Resolved
                    integration       supported power curve; do   
                    semantics were    not manufacture missing     
                    underspecified    telemetry                   

  AR-003            Forward           Durable telemetry-persisted Resolved
                    checkpoints could events trigger              
                    not detect stale  affected-window derivation  
                    historical        and recomputation           
                    projections                                   

  AR-004            Aggregation       Use half-open UTC intervals Resolved
                    window boundaries `[StartUtc, EndUtc)`        
                    were ambiguous                                

  AR-005            `AvgPower`        `AvgPowerW` is              Resolved
                    semantics were    time-weighted over          
                    ambiguous under   `ObservedDurationSeconds`   
                    irregular                                     
                    sampling                                      
  ---------------------------------------------------------------------------------

The resulting architecture is internally consistent:

``` text
Firmware
=
Source of Explicit Electrical Observations
```

``` text
Telemetry Ingestion Service
=
Validate + Resolve + Persist + Record Durable Event Intent
```

``` text
Telemetry Aggregation Service
=
Integrate + Project + Track Completeness + Recompute
```

``` text
Energy Analytics API
=
Business Configuration + Business Interpretation + Reporting
```

------------------------------------------------------------------------

# 3. Architecture Baseline Before Review

## 3.1 SD-002 Baseline

SD-002 established:

-   device-owned `timestampUtc`;
-   one physical-port observation per MQTT message;
-   `physicalPort` as firmware-owned channel identity;
-   contract-by-design measurement units;
-   validation failures as rejected operationally traceable messages.

Telemetry Contract V1 shape:

``` json
{
  "timestampUtc": "2026-05-30T18:30:00Z",
  "physicalPort": 1,
  "voltageVrms": 127.3,
  "currentArms": 1.82,
  "powerW": 231.6
}
```

The original unresolved inconsistency was whether `powerW` could remain
optional.

------------------------------------------------------------------------

## 3.2 SD-003 Baseline

SD-003 established heartbeat as the liveness and infrastructure-metadata
contract.

Heartbeat responsibilities include:

-   device discovery;
-   firmware traceability;
-   fixed channel-topology announcement.

Accepted ownership:

``` text
Device owns heartbeat timestamp.
```

Mandatory heartbeat fields:

``` text
timestampUtc
firmwareVersion
```

`numberOfChannels` is used only where required by
configuration/registration behavior.

Capability discovery was rejected because firmware version provides the
current traceability mechanism.

Topology is treated as part of monitor infrastructure identity for the
current product generation.

The current architecture does not support runtime topology expansion
after registration.

------------------------------------------------------------------------

## 3.3 SD-004 Baseline

SD-004 established the Telemetry Ingestion Service boundary.

Responsibilities:

``` text
Receive MQTT Messages
Validate Contracts
Register Devices
Resolve Channels
Persist Telemetry
Persist Validation Rejections
Acknowledge Broker After Commit
```

Accepted transaction ordering:

``` text
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

Accepted delivery compatibility:

``` text
At Least Once
```

Accepted telemetry idempotency key:

``` text
UNIQUE (
    ChannelId,
    TimestampUtc
)
```

Duplicate telemetry is not a validation failure.

------------------------------------------------------------------------

## 3.4 SD-005 Baseline

SD-005 established a separate Telemetry Aggregation Service.

Accepted principles:

-   `TelemetrySample` is always the canonical aggregation source;
-   minute, hourly, and daily projections are disposable;
-   checkpoints exist independently per aggregation granularity;
-   checkpoints are optimization state;
-   projections can be deleted and regenerated from `TelemetrySample`;
-   late telemetry must cause affected projections to be recomputed;
-   aggregation produces telemetry-derived metrics only.

The review exposed several semantics that needed stronger formalization
before SD-006.

------------------------------------------------------------------------

# 4. AR-001 --- Mandatory Power Observation

## Problem

The earlier telemetry design considered `powerW` optional because
initial firmware planning centered on voltage and current transducers.

SD-005 later established energy calculation through integration of the
power curve.

This created a contradiction:

``` text
powerW optional
        ↓
Aggregation requires power curve
        ↓
Backend must derive missing power
```

That derivation would violate the established ownership principle that
backend ingestion preserves device observations rather than inventing
electrical meaning.

------------------------------------------------------------------------

## Q1 --- Should `powerW` remain optional?

### Option A --- Keep `powerW` optional

Advantages:

-   Firmware may publish only voltage and current.

Disadvantages:

-   Aggregation lacks an explicit power curve.
-   Backend derivation becomes necessary.
-   Electrical semantics become ambiguous.
-   Measured and derived values may be conflated.

Decision:

❌ Rejected

------------------------------------------------------------------------

### Option B --- Derive power in the backend

Example:

``` text
Power ≈ VoltageVrms × CurrentArms
```

Advantages:

-   Allows aggregation without explicit power.

Disadvantages:

-   Makes backend services responsible for electrical interpretation.
-   May conflate active, reactive, and apparent power concepts.
-   Violates the source-of-truth boundary.
-   Creates ambiguity about whether persisted power was observed or
    derived.

Decision:

❌ Rejected

------------------------------------------------------------------------

### Option C --- Require firmware-supplied `powerW`

Advantages:

-   Provides deterministic aggregation input.
-   Preserves firmware as source of electrical observations.
-   Avoids backend manufacture of missing measurements.
-   Supports explicit future evolution.

Disadvantages:

-   Firmware must always provide V1 power.

Decision:

✅ Accepted

------------------------------------------------------------------------

## AR-001 Final Decision

Telemetry Contract V1 requires:

``` text
powerW
```

`TelemetrySample.Power` is:

``` text
NOT NULL
```

The backend must not derive missing power from voltage and current.

Future telemetry contracts may introduce explicit quantities such as:

``` text
activePowerW
reactivePowerVar
apparentPowerVa
powerFactor
phaseAngleDeg
```

Such evolution must be explicit.

------------------------------------------------------------------------

## AR-001 Consequences

  -----------------------------------------------------------------------
  Artifact                            Required Change
  ----------------------------------- -----------------------------------
  SD-002                              Make `powerW` mandatory and define
                                      rejection behavior

  SD-004                              Reject invalid telemetry lacking
                                      required power

  SD-005                              Integrate persisted
                                      firmware-supplied power

  Database                            `TelemetrySample.Power NOT NULL`

  Project Definition                  Update telemetry contract and
                                      ownership language
  -----------------------------------------------------------------------

Status:

✅ Resolved and propagated

------------------------------------------------------------------------

# 5. AR-002 --- Numerical Integration Semantics

## Problem

SD-005 selected:

``` text
EnergyConsumedWh
=
Area Under the Power Curve
```

However, the phrase was insufficient without defining behavior for:

-   irregular sample intervals;
-   missing telemetry;
-   observations near window boundaries;
-   incomplete windows.

The architecture needed to prevent accidental estimation from becoming
hidden system behavior.

------------------------------------------------------------------------

## Q2 --- Should an observation remain valid indefinitely until the next sample?

### Option A --- Unlimited previous-value hold

Conceptually:

``` text
Last Power Observation
        ↓
Remains Valid Until Next Observation
```

Advantages:

-   Produces continuous curves.

Disadvantages:

-   A connectivity gap may become fabricated energy consumption.
-   Missing telemetry becomes invisible.
-   Long outages may be interpreted as valid continuous observation.

Decision:

❌ Rejected

------------------------------------------------------------------------

### Option B --- Fixed maximum carry-forward threshold

Advantages:

-   Limits unlimited extrapolation.

Disadvantages:

-   Introduces an arbitrary threshold.
-   Couples aggregation semantics to an undeclared sampling policy.
-   Still manufactures unsupported telemetry after the last observation.

Decision:

❌ Rejected for current architecture

------------------------------------------------------------------------

### Option C --- Use available observations only

The service integrates curve segments supported by available telemetry.

Advantages:

-   Does not manufacture missing observations.
-   Preserves uncertainty.
-   Supports explicit completeness metrics.
-   Remains compatible with irregular sampling.

Disadvantages:

-   Windows may be incomplete.
-   Consumers must understand coverage.

Decision:

✅ Accepted

------------------------------------------------------------------------

## AR-002 Final Decision

``` text
Available telemetry defines the supported power curve.

Missing telemetry is not manufactured.
```

Energy is calculated from supported temporal curve segments.

The architecture does not automatically:

-   extend a previous-window observation into the next window;
-   hold the last value indefinitely;
-   fill missing intervals with zero;
-   fill missing intervals with an average;
-   derive missing power from voltage and current.

------------------------------------------------------------------------

## Projection Completeness

Because `SampleCount` cannot describe temporal coverage, the projections
include:

``` text
ObservedDurationSeconds
ExpectedDurationSeconds
CoverageRatio
```

Definitions:

``` text
ObservedDurationSeconds
=
Duration supported by integrated curve segments
```

``` text
ExpectedDurationSeconds
=
Nominal duration of the projection window
```

``` text
CoverageRatio
=
ObservedDurationSeconds / ExpectedDurationSeconds
```

Expected durations:

  Projection     Expected Duration
  ------------ -------------------
  Minute                60 seconds
  Hourly              3600 seconds
  Daily UTC          86400 seconds

------------------------------------------------------------------------

## Zero Supported Duration

Accepted behavior:

``` text
ObservedDurationSeconds = 0
        ↓
No Projection Row Created
```

This preserves the meaning of a projection row:

> A projection row represents a window with at least some supported
> power-curve duration.

Consequences:

-   `AvgPowerW` remains non-nullable.
-   Empty windows are not represented as fabricated zero-valued
    analytics.
-   Absence of a projection row is distinct from a valid zero-power
    observation.

------------------------------------------------------------------------

## AR-002 Consequences

  -----------------------------------------------------------------------
  Artifact                            Required Change
  ----------------------------------- -----------------------------------
  SD-005                              Formalize supported-curve
                                      integration

  Database                            Add completeness fields

  Project Definition                  Document missing-telemetry behavior

  SD-006                              API schemas must expose
                                      completeness where projections are
                                      returned
  -----------------------------------------------------------------------

Status:

✅ Resolved and propagated

------------------------------------------------------------------------

# 6. AR-003 --- Late Telemetry Detection

## Problem

SD-005 established checkpoints for forward aggregation progress.

Example:

``` text
Minute Checkpoint
=
12:30:00
```

Later, delayed telemetry may arrive with:

``` text
TimestampUtc
=
12:15:30
```

The affected historical projection may already exist.

A forward-only checkpoint cannot discover that the historical window
became stale.

------------------------------------------------------------------------

## Q3 --- How should late telemetry invalidate projections?

### Option A --- Scan by ingestion timestamp

Advantages:

-   Uses persisted telemetry.

Disadvantages:

-   Requires another watermark.
-   Couples detection latency to polling.
-   May repeatedly rediscover historical changes.

Decision:

❌ Rejected

------------------------------------------------------------------------

### Option B --- Ingestion writes dirty aggregation windows

Advantages:

-   Explicit invalidation state.

Disadvantages:

-   Makes ingestion understand minute, hourly, and daily projection
    semantics.
-   Couples ingestion to aggregation design.
-   Weakens separation of concerns.

Decision:

❌ Rejected

------------------------------------------------------------------------

### Option C --- Durable telemetry-persisted event

Conceptually:

``` text
TelemetrySample Persisted
        ↓
Durable Event Intent
        ↓
Event Published
        ↓
Telemetry Aggregation Service
        ↓
Affected Windows Derived
        ↓
Projection Recomputed
```

Advantages:

-   Preserves service ownership.
-   Ingestion announces observation availability.
-   Aggregation derives analytical consequences.
-   Supports historical invalidation.

Disadvantages:

-   Requires reliable event publication.
-   Requires idempotent consumers.

Decision:

✅ Accepted

------------------------------------------------------------------------

## Reliable Publication Problem

A naive dual write is unsafe:

``` text
Commit TelemetrySample
        ↓
Publish Event
```

Failure scenario:

``` text
TelemetrySample committed
        ↓
Process crashes
        ↓
Event never published
```

Decision:

❌ Naive dual write rejected

------------------------------------------------------------------------

## Accepted Outbox Strategy

``` text
Begin Transaction
        ↓
Insert TelemetrySample
        ↓
Insert OutboxMessage
        ↓
Commit
        ↓
Acknowledge MQTT Broker
```

Separate publisher:

``` text
Read Pending OutboxMessage
        ↓
Publish Event
        ↓
Mark PublishedAtUtc
```

Decision:

✅ Accepted

------------------------------------------------------------------------

## Updated Ingestion Transaction Boundary

``` text
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

Atomic invariant:

``` text
TelemetrySample persisted
+
Event publication intent persisted
```

or:

``` text
Neither persisted
```

------------------------------------------------------------------------

## Duplicate Telemetry

Accepted idempotency key:

``` text
UNIQUE (
    ChannelId,
    TimestampUtc
)
```

Duplicate telemetry remains:

``` text
Not a Validation Failure
```

If no new `TelemetrySample` is inserted:

``` text
No New TelemetryPersisted Event Intent Required
```

------------------------------------------------------------------------

## Event Delivery

The internal event boundary must tolerate:

``` text
At Least Once Delivery
```

Therefore the Telemetry Aggregation Service must be idempotent.

Projection writes use deterministic composite keys and upsert semantics.

------------------------------------------------------------------------

## Affected Window Derivation

Given:

``` text
TimestampUtc = 2026-05-30T12:15:30Z
```

the Aggregation Service derives:

``` text
Minute:
[2026-05-30T12:15:00Z,
 2026-05-30T12:16:00Z)
```

``` text
Hourly:
[2026-05-30T12:00:00Z,
 2026-05-30T13:00:00Z)
```

``` text
Daily:
[2026-05-30T00:00:00Z,
 2026-05-31T00:00:00Z)
```

If an affected projection already exists:

``` text
Reload TelemetrySample for Window
        ↓
Rebuild Supported Power Curve
        ↓
Recalculate Metrics
        ↓
Upsert Projection
```

------------------------------------------------------------------------

## AR-003 Consequences

  -----------------------------------------------------------------------
  Artifact                            Required Change
  ----------------------------------- -----------------------------------
  SD-004                              Add durable event intent and Outbox
                                      Pattern

  SD-005                              Consume persisted-observation
                                      notifications

  Database                            Add `OutboxMessage`

  Project Definition                  Add event-driven aggregation
                                      boundary

  SD-006                              Public API remains independent from
                                      internal event transport
  -----------------------------------------------------------------------

Status:

✅ Resolved and propagated

------------------------------------------------------------------------

# 7. AR-004 --- Formal Aggregation Window Semantics

## Problem

Aggregation boundaries were described informally.

Without exact interval semantics, timestamps at boundaries could:

-   belong to two windows;
-   belong to no window;
-   produce inconsistent recomputation.

------------------------------------------------------------------------

## Q4 --- How are windows represented?

Accepted representation:

``` text
[StartUtc, EndUtc)
```

Meaning:

``` text
StartUtc = included
EndUtc   = excluded
```

Decision:

✅ Accepted

------------------------------------------------------------------------

## Minute

``` text
[12:01:00, 12:02:00)
```

Examples:

``` text
12:01:00.000 → included
12:01:59.999 → included
12:02:00.000 → excluded
```

------------------------------------------------------------------------

## Hourly

``` text
[12:00:00, 13:00:00)
```

Examples:

``` text
12:00:00.000 → included
12:59:59.999 → included
13:00:00.000 → excluded
```

------------------------------------------------------------------------

## Daily

``` text
[2026-05-30T00:00:00Z,
 2026-05-31T00:00:00Z)
```

The daily projection is explicitly UTC-based.

------------------------------------------------------------------------

## Boundary Ownership

Adjacent windows:

``` text
W1 = [12:01:00, 12:02:00)

W2 = [12:02:00, 12:03:00)
```

Timestamp:

``` text
12:02:00
```

belongs only to:

``` text
W2
```

Therefore:

``` text
No Overlap
No Boundary Gap
Deterministic Timestamp Ownership
```

------------------------------------------------------------------------

## Integration Boundary

Integration does not cross projection boundaries.

Accepted principle:

``` text
Each projection integrates only supported curve segments
attributed to its own half-open UTC window.
```

Observations from previous windows are not automatically carried forward
to manufacture coverage.

------------------------------------------------------------------------

## AR-004 Consequences

  -----------------------------------------------------------------------
  Artifact                            Required Change
  ----------------------------------- -----------------------------------
  SD-005                              Formalize all window definitions

  Database                            Window keys represent deterministic
                                      UTC starts/dates

  Project Definition                  Document half-open UTC intervals

  SD-006                              Query range semantics should align
                                      with deterministic UTC boundaries
  -----------------------------------------------------------------------

Status:

✅ Resolved and propagated

------------------------------------------------------------------------

# 8. AR-005 --- Time-Weighted Average Power

## Problem

After completeness metrics were introduced, `AvgPower` became ambiguous.

For irregular observations:

``` text
12:01:05 → 100 W
12:01:06 → 200 W
12:01:45 → 100 W
```

Arithmetic mean:

``` text
(100 + 200 + 100) / 3
=
133.33 W
```

This ignores how long each power level contributes to the supported
curve.

Since energy already uses temporal integration, arithmetic average power
would be mathematically inconsistent.

------------------------------------------------------------------------

## Q5 --- How should average power be calculated?

### Option A --- Arithmetic sample mean

``` text
AvgPowerW
=
Sum(Power Samples) / SampleCount
```

Advantages:

-   Simple.

Disadvantages:

-   Ignores irregular spacing.
-   Gives equal weight to observations with unequal temporal
    contribution.
-   Can disagree with integrated energy.

Decision:

❌ Rejected

------------------------------------------------------------------------

### Option B --- Time-weighted average over observed duration

``` text
AvgPowerW
=
EnergyConsumedWh × 3600
/
ObservedDurationSeconds
```

Advantages:

-   Uses the same supported curve as energy.
-   Respects irregular observation intervals.
-   Creates a mathematical invariant.
-   Keeps average power coherent with completeness.

Disadvantages:

-   Undefined when observed duration is zero.

Decision:

✅ Accepted

------------------------------------------------------------------------

## AR-005 Final Decision

`AvgPowerW` is the time-weighted average power over:

``` text
ObservedDurationSeconds
```

It is derived from the same integrated supported power curve used for:

``` text
EnergyConsumedWh
```

Invariant for projections where:

``` text
ObservedDurationSeconds > 0
```

is:

``` text
AvgPowerW
=
EnergyConsumedWh × 3600
/
ObservedDurationSeconds
```

within accepted numeric precision and rounding tolerance.

------------------------------------------------------------------------

## Metric Naming Alignment

Previous names:

``` text
MinPower
MaxPower
AvgPower
```

Accepted names:

``` text
MinPowerW
MaxPowerW
AvgPowerW
```

This aligns with contract-by-design unit semantics.

------------------------------------------------------------------------

## Symmetric Projection Metric Family

Minute, hourly, and daily projections use:

``` text
SampleCount
MinPowerW
MaxPowerW
AvgPowerW
EnergyConsumedWh
ObservedDurationSeconds
ExpectedDurationSeconds
CoverageRatio
```

Only the window duration differs.

------------------------------------------------------------------------

## AR-005 Consequences

  -----------------------------------------------------------------------
  Artifact                            Required Change
  ----------------------------------- -----------------------------------
  SD-005                              Define time-weighted average
                                      semantics

  Database                            Rename power metrics with explicit
                                      watt units

  Project Definition                  Document mathematical relationship

  SD-006                              Projection response schemas should
                                      preserve explicit units and
                                      completeness
  -----------------------------------------------------------------------

Status:

✅ Resolved and propagated

------------------------------------------------------------------------

# 9. Final Service Ownership Review

## Firmware

Owns:

``` text
Observation Timestamp
Physical Port Identity
RMS Voltage Observation
RMS Current Observation
Power Observation
Firmware Version
Channel Topology Announcement
```

Does not own:

``` text
Database Identity
Room Assignment
Tariff Interpretation
Historical Projection State
```

------------------------------------------------------------------------

## MQTT Broker

Owns transport-level delivery behavior according to configured session
and QoS policies.

The backend architecture assumes at-least-once-compatible processing.

The broker is not the analytical source of truth.

------------------------------------------------------------------------

## Telemetry Ingestion Service

Owns:

``` text
MQTT Subscription
Contract Validation
Heartbeat Processing
Automatic Registration
Monitor Resolution
Channel Resolution
Telemetry Persistence
Validation Rejection Persistence
Durable Outbox Intent
Commit-Before-Acknowledge Ordering
```

Does not own:

``` text
Minute Aggregation
Hourly Aggregation
Daily Aggregation
Projection Invalidation Semantics
Tariff Interpretation
Cost Estimation
Forecasting
```

------------------------------------------------------------------------

## Telemetry Aggregation Service

Owns:

``` text
Minute Projection
Hourly Projection
Daily Projection
Numerical Integration
Time-Weighted AvgPowerW
Projection Completeness
Forward Checkpoints
Late-Telemetry Recalculation
Idempotent Projection Upserts
```

Reads:

``` text
TelemetrySample
```

Consumes:

``` text
Telemetry Persisted Events
```

Does not own:

``` text
MQTT Ingestion
Telemetry Contract Validation
Device Registration
Tariff Interpretation
Cost Estimation
Machine Learning
```

------------------------------------------------------------------------

## Energy Analytics API

Owns:

``` text
Room Management
Monitor Management
Channel Management
Channel Assignment Management
Energy Tariff Management
Business Queries
Reporting APIs
Cost Interpretation
```

The API may read telemetry-derived projections but does not own their
generation.

------------------------------------------------------------------------

# 10. Final Data Ownership Review

  ---------------------------------------------------------------------------------
  Data                      Classification            Source of Truth / Owner
  ------------------------- ------------------------- -----------------------------
  `Room`                    Business metadata         Energy Analytics API

  `Monitor`                 Infrastructure/business   Registration + API management
                            metadata                  boundary

  `Channel`                 Infrastructure identity   Heartbeat-driven registration

  `ChannelAssignment`       Business history          Energy Analytics API

  `EnergyTariff`            Business configuration    Energy Analytics API

  `TelemetrySample`         System of record          Telemetry Ingestion Service

  `TelemetryRejection`      Operational data          Telemetry Ingestion Service

  `OutboxMessage`           Operational integration   Ingestion/event-publication
                            state                     boundary

  `TelemetryMinute`         Disposable projection     Telemetry Aggregation Service

  `TelemetryHourly`         Disposable projection     Telemetry Aggregation Service

  `TelemetryDaily`          Disposable projection     Telemetry Aggregation Service

  `AggregationCheckpoint`   Optimization state        Telemetry Aggregation Service
  ---------------------------------------------------------------------------------

------------------------------------------------------------------------

# 11. Final Projection Semantics

## Canonical Source

``` text
TelemetrySample
```

All projections are conceptually derived directly from the system of
record:

``` text
TelemetrySample → TelemetryMinute
TelemetrySample → TelemetryHourly
TelemetrySample → TelemetryDaily
```

------------------------------------------------------------------------

## Disposable Projection Principle

``` text
Delete Projection
        ↓
Reset Relevant Checkpoint
        ↓
Replay TelemetrySample
        ↓
Regenerate Projection
```

Projection loss is not telemetry loss.

Checkpoint loss is not telemetry loss.

------------------------------------------------------------------------

## Completeness Principle

A projection does not claim full-window observation unless its coverage
supports that claim.

``` text
CoverageRatio
=
ObservedDurationSeconds / ExpectedDurationSeconds
```

Consumers must be able to distinguish:

``` text
Complete Observation
Partial Observation
No Projection
```

------------------------------------------------------------------------

# 12. Failure and Recovery Review

## Ingestion crashes before commit

``` text
TelemetrySample not committed
OutboxMessage not committed
MQTT message not acknowledged
```

Expected result:

``` text
Message remains eligible for redelivery
```

------------------------------------------------------------------------

## Ingestion crashes after commit but before MQTT acknowledgement

``` text
TelemetrySample committed
OutboxMessage committed
MQTT message may be redelivered
```

Expected result:

``` text
Unique(ChannelId, TimestampUtc)
prevents duplicate observation creation
```

------------------------------------------------------------------------

## Process crashes after commit but before event publication

``` text
TelemetrySample committed
OutboxMessage pending
```

Expected result:

``` text
Outbox publisher resumes later
```

------------------------------------------------------------------------

## Event delivered more than once

Expected result:

``` text
Aggregation consumer remains idempotent
```

------------------------------------------------------------------------

## Aggregation service restarts

Expected result:

``` text
Read granularity checkpoint
        ↓
Continue forward processing
```

Historical invalidation remains independently event-driven.

------------------------------------------------------------------------

## Projection data is lost

Expected recovery:

``` text
Delete/Reset Projection State
        ↓
Reset Checkpoint
        ↓
Replay TelemetrySample
```

------------------------------------------------------------------------

# 13. Database Alignment Review

The accepted database changes are:

## `telemetrySample`

``` text
Power NOT NULL
```

Idempotency:

``` text
UNIQUE(ChannelId, TimeStampUtc)
```

------------------------------------------------------------------------

## `outboxMessage`

Required operational integration state:

``` text
Id
EventType
Payload
CreatedAtUtc
PublishedAtUtc
```

------------------------------------------------------------------------

## Projection Tables

All three projection tables use the same metric family:

``` text
SampleCount
MinPowerW
MaxPowerW
AvgPowerW
EnergyConsumedWh
ObservedDurationSeconds
ExpectedDurationSeconds
CoverageRatio
```

Composite keys:

``` text
TelemetryMinute
(ChannelId, MinuteUtc)
```

``` text
TelemetryHourly
(ChannelId, HourUtc)
```

``` text
TelemetryDaily
(ChannelId, DateUtc)
```

------------------------------------------------------------------------

## Removed Aggregation Responsibility

The daily projection does not contain:

``` text
EstimatedCost
```

Reason:

``` text
Cost Estimation
=
Business Interpretation
```

Tariff-based cost calculation belongs to the business/API boundary.

------------------------------------------------------------------------

# 14. Traceability Matrix

  --------------------------------------------------------------------------------------------------------
  Decision                SD-002     SD-003         SD-004     SD-005                Database      Project
                                                                                                Definition
  ------------------- ---------- ---------- -------------- ---------- ----------------------- ------------
  Mandatory `powerW`     Updated        N/A        Aligned    Aligned                 Updated      Updated

  Device-owned           Defined   Mirrored       Consumed       Used                 Aligned      Updated
  timestamp                                                                                   

  Fixed topology             N/A    Defined   Registration        N/A                 Aligned      Aligned
  identity                                         aligned                                    

  Validation             Defined   Mirrored        Defined        N/A                 Updated      Updated
  rejection                                                                                   
  persistence                                                                                 

  At-least-once              N/A        N/A        Defined   Consumer                 Updated      Updated
  idempotency                                                 aligned                         

  Outbox event intent        N/A        N/A        Updated   Consumed                 Updated      Updated

  `TelemetrySample`          N/A        N/A      Preserved    Defined                 Aligned      Updated
  canonical source                                                                            

  Supported-curve            N/A        N/A            N/A    Updated                 Updated      Updated
  integration                                                                                 

  Completeness               N/A        N/A            N/A    Updated                 Updated      Updated
  metrics                                                                                     

  Half-open UTC              N/A        N/A            N/A    Updated                 Aligned      Updated
  windows                                                                                     

  Late telemetry             N/A        N/A Event produced    Updated                 Aligned      Updated
  recomputation                                                                               

  Time-weighted              N/A        N/A            N/A    Updated                 Updated      Updated
  `AvgPowerW`                                                                                 

  No zero-duration           N/A        N/A            N/A    Defined   Constraint-compatible      Updated
  projection row                                                                              

  Cost excluded from         N/A        N/A            N/A    Defined                 Updated      Updated
  aggregation                                                                                 
  --------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

# 15. Decisions Intentionally Deferred

The review does not require every future concern to be solved before
SD-006.

The following remain intentionally deferred unless SD-006 exposes a
direct dependency:

  -----------------------------------------------------------------------
  Deferred Topic                      Reason
  ----------------------------------- -----------------------------------
  Internal event transport technology Outbox contract is defined;
                                      transport selection is
                                      implementation-level

  Explicit telemetry schema version   Rejected for V1; firmware version
  field                               provides current traceability

  Active/reactive/apparent power      Future telemetry contract evolution
  taxonomy                            

  Runtime topology expansion          Not required for current
                                      home-automation hardware generation

  ML anomaly detection                Future analytics capability

  Forecasting                         Future analytics capability

  Maximum timestamp skew policy       Not yet accepted as a contract rule

  Electrical range validation         Not yet accepted as contract rules
  thresholds                          

  Outbox retry metadata details       Implementation refinement

  Projection rounding tolerance       Must be defined in
                                      implementation/test specification
                                      if required
  -----------------------------------------------------------------------

These deferred items must not be silently invented inside SD-006.

------------------------------------------------------------------------

# 16. Readiness Review for SD-006

SD-006 can now begin from stable upstream semantics.

## Stable Resource Foundations

The REST API may safely reason about:

``` text
Rooms
Monitors
Channels
Channel Assignments
Energy Tariffs
Telemetry Samples
Minute Projections
Hourly Projections
Daily Projections
```

subject to endpoint-scope decisions in SD-006.

------------------------------------------------------------------------

## Stable Projection Semantics

Any API response exposing analytical projections can rely on:

``` text
SampleCount
MinPowerW
MaxPowerW
AvgPowerW
EnergyConsumedWh
ObservedDurationSeconds
ExpectedDurationSeconds
CoverageRatio
```

with explicit semantics.

------------------------------------------------------------------------

## Stable Time Semantics

API query design can align with:

``` text
UTC
Half-Open Intervals
Deterministic Window Ownership
```

------------------------------------------------------------------------

## Stable Quality Semantics

API consumers can distinguish partial analytical coverage through:

``` text
ObservedDurationSeconds
ExpectedDurationSeconds
CoverageRatio
```

------------------------------------------------------------------------

## Stable Ownership Boundary

SD-006 must not expose internal implementation state as public business
resources without explicit justification.

Examples of internal state that should not automatically become public
REST resources:

``` text
OutboxMessage
AggregationCheckpoint
```

`TelemetryRejection` may require an operational/admin API in the future,
but that is a separate API-scope decision.

------------------------------------------------------------------------

# 17. Final Review Decision

The architecture review concludes:

``` text
SD-002
through
SD-005
```

are sufficiently aligned to proceed to:

``` text
SD-006 — Design REST API Contract
```

provided SD-006 preserves the following invariants:

1.  `powerW` is mandatory in Telemetry Contract V1.
2.  `TelemetrySample` remains the permanent telemetry source of truth.
3.  Analytical projections remain disposable.
4.  Aggregation windows remain half-open UTC intervals.
5.  Missing telemetry is not manufactured.
6.  `AvgPowerW` remains time-weighted over observed duration.
7.  Projection completeness remains explicit.
8.  Late telemetry causes deterministic historical recomputation.
9.  Internal event transport remains separate from public REST design.
10. Cost estimation remains a business/API concern rather than telemetry
    aggregation output.

------------------------------------------------------------------------

# Final Architectural Principle

``` text
Firmware reports explicit observations.

Ingestion preserves valid observations and durable notification intent.

Aggregation derives mathematically coherent, completeness-aware,
disposable projections from TelemetrySample.

The API interprets and exposes business capabilities without leaking
internal processing mechanics.

With these boundaries aligned, SD-006 can define the public REST contract
without redesigning the telemetry pipeline underneath it.
```
