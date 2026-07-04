CREATE TABLE [room] (
  [Id] bigint PRIMARY KEY,
  [Name] nvarchar(100) NOT NULL,
  [CreatedAtUtc] datetime2(3) NOT NULL
)
GO

CREATE TABLE [monitor] (
  [Id] bigint PRIMARY KEY,
  [RoomId] bigint,
  [DeviceIdentifier] nvarchar(20) NOT NULL,
  [Name] nvarchar(100) NOT NULL,
  [FirmwareVersion] varchar(20),
  [LastHeartbeatUtc] datetime2(3),
  [CreatedAtUtc] datetime2(3) NOT NULL
)
GO

CREATE TABLE [channel] (
  [Id] bigint PRIMARY KEY,
  [MonitorId] bigint NOT NULL,
  [PhysicalPort] tinyint NOT NULL,
  [CreatedAtUtc] datetime2(3) NOT NULL
)
GO

CREATE TABLE [channelAssignment] (
  [Id] bigint PRIMARY KEY,
  [ChannelId] bigint NOT NULL,
  [Label] nvarchar(100) NOT NULL,
  [StartDateUtc] datetime2 NOT NULL,
  [EndDateUtc] datetime2
)
GO

CREATE TABLE [energyTariff] (
  [Id] bigint PRIMARY KEY,
  [Name] nvarchar(100) NOT NULL,
  [CostPerKWh] decimal(10,4) NOT NULL,
  [EffectiveFromUtc] datetime2(3) NOT NULL,
  [EffectiveToUtc] datetime2(3)
)
GO

CREATE TABLE [telemetrySample] (
  [Id] bigint PRIMARY KEY,
  [ChannelId] bigint NOT NULL,
  [TimeStampUtc] datetime2(3) NOT NULL,
  [Voltage] decimal(8,3) NOT NULL,
  [Current] decimal(8,3) NOT NULL,
  [Power] decimal(10,3) NOT NULL,
  [CreatedAtUtc] datetime2(3) NOT NULL
)
GO

CREATE TABLE [telemetryRejection] (
  [Id] bigint PRIMARY KEY,
  [DeviceIdentifier] nvarchar(20),
  [Topic] nvarchar(200) NOT NULL,
  [Reason] nvarchar(200) NOT NULL,
  [Payload] nvarchar(max) NOT NULL,
  [CreatedAtUtc] datetime2(3) NOT NULL
)
GO

CREATE TABLE [outboxMessage] (
  [Id] bigint PRIMARY KEY,
  [EventType] varchar(100) NOT NULL,
  [Payload] nvarchar(max) NOT NULL,
  [CreatedAtUtc] datetime2(3) NOT NULL,
  [PublishedAtUtc] datetime2(3)
)
GO

CREATE TABLE [aggregationCheckpoint] (
  [AggregationName] varchar(50) PRIMARY KEY,
  [LastProcessedUtc] datetime2(3) NOT NULL,
  [UpdatedAtUtc] datetime2(3) NOT NULL
)
GO

CREATE TABLE [telemetryMinute] (
  [ChannelId] bigint,
  [MinuteUtc] datetime2(0),
  [SampleCount] int NOT NULL,
  [MinPowerW] decimal(10,3) NOT NULL,
  [MaxPowerW] decimal(10,3) NOT NULL,
  [AvgPowerW] decimal(10,3) NOT NULL,
  [EnergyConsumedWh] decimal(12,4) NOT NULL,
  [ObservedDurationSeconds] decimal(10,3) NOT NULL,
  [ExpectedDurationSeconds] int NOT NULL,
  [CoverageRatio] decimal(9,6) NOT NULL,
  PRIMARY KEY ([ChannelId], [MinuteUtc])
)
GO

CREATE TABLE [telemetryHourly] (
  [ChannelId] bigint,
  [HourUtc] datetime2(0),
  [SampleCount] int NOT NULL,
  [MinPowerW] decimal(10,3) NOT NULL,
  [MaxPowerW] decimal(10,3) NOT NULL,
  [AvgPowerW] decimal(10,3) NOT NULL,
  [EnergyConsumedWh] decimal(12,4) NOT NULL,
  [ObservedDurationSeconds] decimal(10,3) NOT NULL,
  [ExpectedDurationSeconds] int NOT NULL,
  [CoverageRatio] decimal(9,6) NOT NULL,
  PRIMARY KEY ([ChannelId], [HourUtc])
)
GO

CREATE TABLE [telemetryDaily] (
  [ChannelId] bigint,
  [DateUtc] date,
  [SampleCount] int NOT NULL,
  [MinPowerW] decimal(10,3) NOT NULL,
  [MaxPowerW] decimal(10,3) NOT NULL,
  [AvgPowerW] decimal(10,3) NOT NULL,
  [EnergyConsumedWh] decimal(12,4) NOT NULL,
  [ObservedDurationSeconds] decimal(10,3) NOT NULL,
  [ExpectedDurationSeconds] int NOT NULL,
  [CoverageRatio] decimal(9,6) NOT NULL,
  PRIMARY KEY ([ChannelId], [DateUtc])
)
GO

CREATE UNIQUE INDEX [monitor_index_0] ON [monitor] ("DeviceIdentifier")
GO

CREATE UNIQUE INDEX [channel_index_1] ON [channel] ("MonitorId", "PhysicalPort")
GO

CREATE UNIQUE INDEX [telemetrySample_index_2] ON [telemetrySample] ("ChannelId", "TimeStampUtc")
GO

CREATE INDEX [outboxMessage_index_3] ON [outboxMessage] ("PublishedAtUtc", "CreatedAtUtc")
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Last firmware version reported by heartbeat.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'monitor',
@level2type = N'Column', @level2name = 'FirmwareVersion';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'RMS Electric Voltage reported by firmware.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetrySample',
@level2type = N'Column', @level2name = 'Voltage';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'RMS Electric Current reported by firmware.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetrySample',
@level2type = N'Column', @level2name = 'Current';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Mandatory firmware-supplied power observation in watts.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetrySample',
@level2type = N'Column', @level2name = 'Power';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Telemetry ingestion timestamp.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetrySample',
@level2type = N'Column', @level2name = 'CreatedAtUtc';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Minimum observed power in watts within the aggregation window.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryMinute',
@level2type = N'Column', @level2name = 'MinPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Maximum observed power in watts within the aggregation window.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryMinute',
@level2type = N'Column', @level2name = 'MaxPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Time-weighted average power in watts over ObservedDurationSeconds.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryMinute',
@level2type = N'Column', @level2name = 'AvgPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Expected value for minute projections: 60 seconds.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryMinute',
@level2type = N'Column', @level2name = 'ExpectedDurationSeconds';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Minimum observed power in watts within the aggregation window.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryHourly',
@level2type = N'Column', @level2name = 'MinPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Maximum observed power in watts within the aggregation window.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryHourly',
@level2type = N'Column', @level2name = 'MaxPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Time-weighted average power in watts over ObservedDurationSeconds.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryHourly',
@level2type = N'Column', @level2name = 'AvgPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Expected value for hourly projections: 3600 seconds.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryHourly',
@level2type = N'Column', @level2name = 'ExpectedDurationSeconds';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Minimum observed power in watts within the aggregation window.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryDaily',
@level2type = N'Column', @level2name = 'MinPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Maximum observed power in watts within the aggregation window.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryDaily',
@level2type = N'Column', @level2name = 'MaxPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Time-weighted average power in watts over ObservedDurationSeconds.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryDaily',
@level2type = N'Column', @level2name = 'AvgPowerW';
GO

EXEC sp_addextendedproperty
@name = N'Column_Description',
@value = 'Expected value for UTC daily projections: 86400 seconds.',
@level0type = N'Schema', @level0name = 'dbo',
@level1type = N'Table',  @level1name = 'telemetryDaily',
@level2type = N'Column', @level2name = 'ExpectedDurationSeconds';
GO

ALTER TABLE [monitor] ADD FOREIGN KEY ([RoomId]) REFERENCES [room] ([Id])
GO

ALTER TABLE [channel] ADD FOREIGN KEY ([MonitorId]) REFERENCES [monitor] ([Id])
GO

ALTER TABLE [channelAssignment] ADD FOREIGN KEY ([ChannelId]) REFERENCES [channel] ([Id])
GO

ALTER TABLE [telemetrySample] ADD FOREIGN KEY ([ChannelId]) REFERENCES [channel] ([Id])
GO

ALTER TABLE [telemetryMinute] ADD FOREIGN KEY ([ChannelId]) REFERENCES [channel] ([Id])
GO

ALTER TABLE [telemetryHourly] ADD FOREIGN KEY ([ChannelId]) REFERENCES [channel] ([Id])
GO

ALTER TABLE [telemetryDaily] ADD FOREIGN KEY ([ChannelId]) REFERENCES [channel] ([Id])
GO
