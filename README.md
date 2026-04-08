# Redis to Valkey Migration with BetterDB

A practical guide and runnable demo for migrating from Redis to Valkey using [BetterDB](https://www.betterdb.com/).

## Table of Contents

- [Why Migrate from Redis?](#why-migrate-from-redis)
- [What Changed in Redis](#what-changed-in-redis)
- [Why Valkey](#why-valkey)
- [The Migration Problem](#the-migration-problem)
- [BetterDB: The Solution](#betterdb-the-solution)
- [Demo: Redis to Valkey Migration](#demo-redis-to-valkey-migration)
- [BetterDB Beyond Migration](#betterdb-beyond-migration)
- [Resources](#resources)

---

## Why Migrate from Redis?

Three things happened between 2024 and 2025 that fundamentally changed what Redis is:

1. **License change** - Redis switched from BSD 3-Clause to a dual RSAL/SSPL license
2. **File format break** - Redis 7.4 introduced RDB version 12, incompatible with forks
3. **Command set divergence** - Redis 8.0 folded 8 proprietary modules (150+ commands) into core

The Redis you knew as an open-source, community-driven project no longer exists in the same form.

### The License Change (March 2024)

Redis Labs changed the license from BSD 3-Clause to a dual license under the Redis Source Available License (RSAL) and the Server Side Public License (SSPL). Cloud providers can no longer offer managed Redis without a commercial agreement with Redis Inc.

If you are a developer running Redis on your own servers, you can still use it. But the open-source license that made Redis what it was is gone. Contributors who built Redis for over a decade now contribute to a product that cannot be freely distributed.

### The RDB Format Break (August 2024)

Redis 7.4 bumped the RDB persistence format from version 11 to version 12. This broke data-level compatibility with every Redis-compatible alternative:

```
Can't handle RDB format version 12
```

If you are on Redis 7.4+ and try to migrate by copying your dump file to Valkey, Dragonfly, or any other fork, it fails. This is not a warning. It is a hard stop.

### The Command Set Divergence (May 2025)

Redis 8.0 integrated eight previously proprietary modules directly into core:

| Module | Description |
|--------|-------------|
| RedisJSON | Native JSON document support |
| RediSearch | Full-text search and secondary indexing |
| RedisTimeSeries | Time-series data structure |
| RedisBloom | Bloom filter, Cuckoo filter, Count-min sketch, Top-K |
| RedisGraph | Graph database (Cypher queries) |
| RedisAI | Tensor operations and model serving |
| RedisGears | Serverless engine for data processing |
| RedisCell | Rate limiting |

This added over 150 commands that do not exist in Valkey or any fork. Redis and Valkey are now genuinely different products.

### The Cost Factor

Running managed Redis on Amazon ElastiCache is expensive. Production-grade, multi-AZ, clustered setups easily run hundreds to thousands of dollars per month. You are paying a premium for something that used to be free and open source, with license uncertainty on top.

---

## Why Valkey

[Valkey](https://valkey.io/) is the open-source fork of Redis, maintained by the Linux Foundation.

### Backing

- AWS
- Google Cloud
- Oracle
- Ericsson
- Snap

### License

BSD 3-Clause. The same license Redis had before the change. No dual licensing, no source-available restrictions, no commercial limitations.

### Compatibility

Wire-protocol compatible with Redis. Existing Redis client libraries (Jedis, Lettuce, ioredis, redis-py, etc.) work with Valkey with zero code changes.

### What Valkey Adds Beyond Redis

Valkey is not a frozen copy of Redis from 2024. Active development has introduced:

| Feature | Version | Description |
|---------|---------|-------------|
| I/O Threading | 8.0+ | Significantly better multi-core utilization |
| Per-Slot Statistics | 8.0+ | Granular cluster workload metrics via `CLUSTER SLOT-STATS` |
| COMMANDLOG | 8.1+ | Full command history, not just the slowest queries |
| Hash Field Expiry (HFE) | 8.1+ | TTLs on individual hash fields, not just keys |

### Cloud Adoption

- **AWS ElastiCache** now defaults to Valkey
- **Google Cloud Memorystore** supports Valkey
- **Aiven**, **Upstash**, and others offer managed Valkey

---

## The Migration Problem

If you have a running Redis instance with production data, moving to Valkey is harder than it should be:

### RIOT Is Deprecated

RIOT (Redis Input/Output Tools) was the go-to open-source migration utility. It was **archived in October 2025**. Its replacement is:
- Closed-source
- Enterprise-only
- Built exclusively for Redis Cloud
- No Valkey support

### RDB File Copy Does Not Work

Redis 7.4+ uses RDB version 12, which Valkey cannot read. You cannot simply copy your `dump.rdb` file.

### Writing Custom Scripts Does Not Scale

A SCAN + GET + SET script works for a few thousand string keys. It falls apart when you need to handle:
- Hashes with hundreds of fields
- Lists with millions of entries
- Sorted sets, streams
- TTL preservation (key-level and field-level)
- Cluster topologies and slot-aware writes
- Binary data that breaks on UTF-8 coercion

What looks like a weekend project becomes weeks of engineering.

---

## BetterDB: The Solution

[BetterDB](https://www.betterdb.com/) is a monitoring and observability platform for Valkey and Redis that ships migration as a first-class feature. It handles migration in three phases.

### Phase 1: Analysis

Before moving any data, BetterDB scans the source and produces a compatibility report. No data is written.

**What it checks:**

| Check | Description |
|-------|-------------|
| Key sampling | SCAN + TYPE on a configurable sample (1,000 to 50,000 keys). Cluster mode samples each master independently. |
| Memory estimation | `MEMORY USAGE` per sampled key, extrapolated to the full keyspace |
| TTL distribution | Groups keys into buckets: no expiry, <1h, <24h, <7d, >7d |
| Hash Field Expiry | Detects per-field TTLs on Valkey 8.1+ via `HEXPIRETIME` |
| Compatibility | 10 rules producing blocking/warning/info severity verdicts |
| Command distribution | Top commands from `COMMANDLOG` or `SLOWLOG` |

**Compatibility checks:**

| Check | Severity | Condition |
|-------|----------|-----------|
| `cluster_topology` | blocking | Cluster source to standalone target |
| `cluster_topology` | warning | Standalone source to cluster target |
| `type_direction` | blocking | Valkey source to Redis target (Valkey-specific features may be lost) |
| `hfe` | blocking | Hash Field Expiry on source, target does not support it |
| `modules` | blocking | Source uses modules not on target |
| `multi_db` | blocking | Multiple databases going to cluster (clusters only support db0) |
| `maxmemory_policy` | warning | Eviction policy differs |
| `acl` | warning | Custom ACL users missing on target |
| `persistence` | info | Persistence config differs |

### Phase 2: Execution

Two modes available:

**Command-based mode** (cross-version, cross-protocol):

| Data Type | Read | Write | Atomicity |
|-----------|------|-------|-----------|
| string | `GET` (binary) | `SET PX` | Atomic single SET with PX flag |
| hash | `HSCAN` (binary fields) | `HSET` to temp key, then `RENAME` | Lua RENAME + PEXPIRE |
| list | `LRANGE` in 1,000-element chunks | `RPUSH` to temp key, then `RENAME` | Lua RENAME + PEXPIRE |
| set | `SMEMBERS` or `SSCAN` (>10K) | `SADD` to temp key, then `RENAME` | Lua RENAME + PEXPIRE |
| sorted set | `ZRANGE` or `ZSCAN` (>10K) | `ZADD` to temp key, then `RENAME` | Lua RENAME + PEXPIRE |
| stream | `XRANGE` in 1,000-entry chunks | `XADD` to temp key, then `RENAME` | Lua RENAME + PEXPIRE |

Command-based mode sidesteps the RDB v12 problem entirely by operating at the command level, not the file level.

**RedisShake mode** (same-protocol, speed-optimized):

Uses the RedisShake binary for DUMP/RESTORE-based transfer. Best for large datasets and same-protocol migrations.

Both modes provide:
- Real-time progress (transferred count, skipped, ETA)
- Live log viewer
- Safe cancellation at any point
- Credential redaction in all logs

### Phase 3: Validation

Post-migration verification:

1. **Key count comparison** - `DBSIZE` on both sides, flags discrepancy over 1%
2. **Sample spot-check** - Random keys with binary-safe value comparison (type + content match)
3. **Baseline comparison** - Target's ops/sec, memory, fragmentation, CPU compared against source's pre-migration snapshots

Result: pass/fail verdict with a breakdown of any mismatches.

### Topology Support

| Source | Target | Status | Notes |
|--------|--------|--------|-------|
| Standalone | Standalone | Supported | Direct key transfer |
| Standalone | Cluster | Supported | Keys resharded across target slots |
| Cluster | Cluster | Supported | Per-master scanning, slot-aware writes |
| Cluster | Standalone | Blocked | Cannot safely collapse slots to single node |

### Migration Direction

BetterDB works in **any direction**:
- Redis to Valkey
- Valkey to Redis
- Cloud to self-hosted (ElastiCache, MemoryDB, Redis Cloud, Memorystore)
- Self-hosted to cloud
- Cloud to cloud, across providers

---

## Demo: Redis to Valkey Migration

See [demo/README.md](demo/README.md) for the full step-by-step walkthrough with a runnable setup.

**Quick start:**

```bash
# 1. Start Redis, Valkey, and BetterDB
cd demo
docker compose up -d

# 2. Load sample data into Redis
./load-data.sh

# 3. Open BetterDB dashboard
open http://localhost:3001

# 4. Follow the migration steps in demo/README.md
```

---

## BetterDB Beyond Migration

BetterDB is a full monitoring and observability platform. Key capabilities:

| Feature | Description |
|---------|-------------|
| **Historical Analytics** | Query what happened at 3 AM, not just what is happening now. Survives log rotations. |
| **Anomaly Detection** | Automatic detection of unusual patterns across memory, CPU, connections |
| **Slowlog & COMMANDLOG** | Pattern analysis across persisted slow queries and full command history |
| **Client Attribution** | Which clients consume resources, unusual buffer sizes, connection spikes |
| **Cluster Visualization** | Interactive topology graphs, slot heatmaps, migration tracking |
| **Hot Key Tracking** | Top 50 keys by access frequency with rank movement over time |
| **Latency Monitoring** | Per-event latency history across P50/P95/P99 |
| **ACL Audit Trail** | Track who accessed what for compliance and debugging |
| **Prometheus + Webhooks** | 100+ Prometheus metrics, Slack/email/webhook notifications |
| **AI Assistant** | Ask questions about your instance in plain English |
| **MCP Server** | Connect to Claude Code, Cursor, or any MCP-compatible client |
| **Semantic Caching** | `@betterdb/semantic-cache` for Valkey-native LLM response caching |
| **VS Code Extension** | Browse keys, edit values, run commands without leaving the editor |
| **Throughput Forecasting** | Growth rate trend and ceiling-based ops/sec forecasting |

### MCP Server Setup

```json
{
  "mcpServers": {
    "betterdb": {
      "command": "npx",
      "args": ["-y", "@betterdb/mcp"]
    }
  }
}
```

### Self-Host Options

```bash
# Docker
docker run -d \
  --name betterdb \
  -p 3001:3001 \
  -e DB_HOST=your-valkey-host \
  -e BETTERDB_LICENSE_KEY=your-license-key \
  betterdb/monitor

# npx (instant, no Docker needed)
npx @betterdb/monitor
```

Open source core on GitHub. Free during early access with all Pro and Enterprise features unlocked.

---

## Resources

| Resource | Link |
|----------|------|
| BetterDB Website | https://www.betterdb.com |
| BetterDB Documentation | https://docs.betterdb.com |
| BetterDB GitHub | https://github.com/BetterDB-inc/monitor |
| BetterDB VS Code Extension | https://marketplace.visualstudio.com/items?itemName=betterdb.betterdb-for-valkey |
| BetterDB MCP Server | https://mcp.so/server/betterdb-mcp/BetterDB-inc |
| BetterDB npm (semantic cache) | https://www.npmjs.com/package/@betterdb/semantic-cache |
| Valkey | https://valkey.io |
| Valkey GitHub | https://github.com/valkey-io/valkey |
| Redis License Change Announcement | https://redis.io/blog/redis-adopts-dual-source-available-licensing |

---

## License

This repository (guide + demo files) is licensed under the MIT License. See [LICENSE](LICENSE) for details.

BetterDB itself has its own licensing. See [betterdb.com](https://www.betterdb.com) for details.
