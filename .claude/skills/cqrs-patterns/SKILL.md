---
description: CQRS architecture conventions and patterns for rails_error_dashboard
user-invocable: false
---

# CQRS Architecture Patterns

This gem uses strict Command/Query/Service separation. All new features MUST follow these patterns.

## Directory Structure

```
lib/rails_error_dashboard/
├── commands/       # Write operations (create, update, delete)
├── queries/        # Read operations (fetch, filter, aggregate)
├── services/       # Pure algorithms (parse, calculate, detect)
```

## Commands — Write Operations

**Location**: `lib/rails_error_dashboard/commands/`
**Purpose**: Create, update, or delete records. Never return data for display.

### Pattern

```ruby
module RailsErrorDashboard
  module Commands
    class DoSomething
      def self.call(...)
        new(...).call
      end

      def initialize(params)
        @param = params
      end

      def call
        # Write to database
        # Dispatch notifications via ActiveSupport::Notifications
        # Return the record (but callers shouldn't use it for display)
      rescue => e
        Rails.logger.error("[RailsErrorDashboard] DoSomething failed: #{e.message}")
        nil
      end
    end
  end
end
```

### Existing Commands
- `LogError` — main error capture write path
- `FindOrIncrementError` — deduplication + increment occurrence count
- `FindOrCreateApplication` — multi-app support
- `ResolveError`, `UpdateErrorStatus`, `SnoozeError`, `UnsnoozeError` — workflow state
- `AssignError`, `UnassignError` — assignment management
- `UpdateErrorPriority` — priority changes
- `AddErrorComment` — discussion thread
- `BatchResolveErrors`, `BatchDeleteErrors` — bulk operations
- `IncrementCascadeDetection`, `CalculateCascadeProbability` — cascade tracking

## Queries — Read Operations

**Location**: `lib/rails_error_dashboard/queries/`
**Purpose**: Fetch and filter data for display. Never mutate state.

### Pattern

```ruby
module RailsErrorDashboard
  module Queries
    class FetchSomething
      def self.call(...)
        new(...).call
      end

      def initialize(params)
        @param = params
      end

      def call
        # Build ActiveRecord query
        # Apply filters
        # Return data (relation, hash, or array)
      end
    end
  end
end
```

### Existing Queries
- `ErrorsList` — main error listing with 15+ filters, pagination, sorting
- `DashboardStats` — overview metrics (counts, rates, MTTR)
- `AnalyticsStats` — time-series data for charts
- `BaselineStats` — anomaly detection baselines
- `SimilarErrors` — similarity matching
- `RecurringIssues` — repeat offender detection
- `MttrStats` — mean time to resolution
- `ErrorCascades` — parent-child cascade chains
- `ErrorCorrelation` — co-occurring error pairs
- `PlatformComparison` — browser/OS breakdown
- `FilterOptions` — available filter values for dropdowns
- `CriticalAlerts` — threshold-based alerts
- `DeprecationWarnings` — Rails deprecation aggregates
- `NPlusOneSummary` — N+1 query pattern aggregates
- `CacheHealthSummary` — cache miss/hit aggregates

## Services — Pure Algorithms

**Location**: `lib/rails_error_dashboard/services/`
**Purpose**: Computation, parsing, transformation. No direct DB access — receive data as params, return computed results.

### Pattern

```ruby
module RailsErrorDashboard
  module Services
    class CalculateSomething
      def self.call(...)
        new(...).call
      end

      def initialize(data)
        @data = data
      end

      def call
        # Pure computation on @data
        # Return result
      end
    end
  end
end
```

### Existing Services (a sample; 76 files including `storm_protection/`, so list the directory for all of them)
- **Parsing**: `BacktraceParser`, `BacktraceProcessor`
- **Detection**: `CascadeDetector`, `PatternDetector`, `PlatformDetector`
- **Calculation**: `SimilarityCalculator`, `PearsonCorrelation`, `BaselineCalculator`, `BaselineAlertThrottler`
- **Normalization**: `ErrorNormalizer` (smart deduplication — UUIDs, timestamps, IDs, tokens)
- **Source**: `SourceCodeReader`, `GitBlameReader`, `GithubLinkGenerator`
- **Notifications**: `ErrorBroadcaster`, `ErrorNotificationDispatcher`
- **Payload builders**: `SlackPayloadBuilder`, `DiscordPayloadBuilder`, `TelegramPayloadBuilder`, `PagerdutyPayloadBuilder`, `WebhookPayloadBuilder`, `BaselineAlertPayloadBuilder`
- **Issue trackers**: `IssueTrackerClient` and its `GitHubIssueClient`, `GitLabIssueClient`, `CodebergIssueClient`, `LinearIssueClient`; `IssueBodyFormatter`
- **Breadcrumbs**: `BreadcrumbCollector` (ring buffer, thread-local)
- **Health**: `SystemHealthSnapshot` (GC.stat, connection pool, threads)
- **Data**: `SensitiveDataFilter`, `ExceptionFilter`, `CauseChainExtractor`
- **Storm protection**: `StormProtection::Gate`, `CircuitBreaker`, `CountBuffer`, `FingerprintBuckets`

## Naming Conventions

| Layer | Verb Style | Examples |
|-------|-----------|----------|
| Commands | Action verb | `LogError`, `ResolveError`, `BatchDelete` |
| Queries | Noun/adjective | `ErrorsList`, `DashboardStats`, `SimilarErrors` |
| Services | Algorithm name | `ErrorNormalizer`, `SimilarityCalculator`, `BacktraceParser` |

## Spec File Locations

```
spec/
├── commands/rails_error_dashboard/    # Command specs
├── queries/rails_error_dashboard/     # Query specs
├── services/rails_error_dashboard/    # Service specs
├── models/                            # Model specs
├── jobs/                              # Job specs
├── integration/                       # Cross-layer integration tests
├── system/                            # Capybara browser tests
```

## Common Violations to Avoid

- Controller doing `ErrorLog.create(...)` instead of `Commands::LogError.call(...)`
- Query that updates a counter (use a Command for the write)
- Service that does `ErrorLog.where(...)` (pass data in, don't query inside)
- Command returning complex data for view rendering (just write, let a Query read)
- Business logic in models beyond simple validations/scopes
