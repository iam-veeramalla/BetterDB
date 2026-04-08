# Demo: Redis to Valkey Migration with BetterDB

This demo walks through a complete Redis-to-Valkey migration using BetterDB's three-phase workflow: **Analysis**, **Execution**, and **Validation**.

## Prerequisites

- Docker and Docker Compose installed
- Ports 6379, 6399, and 3001 available

## Architecture

```
+------------------+          +------------------+
|  Redis 7.4       |  ------> |  Valkey 8.1      |
|  (source)        |  migrate |  (target)        |
|  localhost:6379   |          |  localhost:6399   |
+------------------+          +------------------+
         |
         |  monitors
         v
+------------------+
|  BetterDB        |
|  localhost:3001   |
+------------------+
```

## Step 1: Start the Environment

```bash
docker compose up -d
```

This starts three containers:

| Container | Image | Port | Role |
|-----------|-------|------|------|
| redis-source | redis:7.4 | 6379 | Source instance with data |
| valkey-target | valkey/valkey:8.1 | 6399 | Empty target instance |
| betterdb | betterdb/monitor | 3001 | Migration + monitoring tool |

Verify everything is running:

```bash
docker compose ps
```

## Step 2: Load Sample Data

Run the data loader script to populate Redis with a realistic mix of data types:

```bash
./load-data.sh
```

This creates:

| Key Pattern | Type | Count | Description |
|-------------|------|-------|-------------|
| `user:{id}:name` | string | 5 | User display names |
| `user:{id}:profile` | hash | 5 | User profiles with multiple fields |
| `user:{id}:notifications` | list | 5 | Notification queues (10 items each) |
| `tags:{category}` | set | 3 | Tag collections |
| `leaderboard:daily` | sorted set | 20 | Player scores |
| `leaderboard:weekly` | sorted set | 20 | Player scores |
| `session:{token}` | string (with TTL) | 10 | Active sessions expiring in 1 hour |
| `cache:page:{slug}` | string (with TTL) | 5 | Cached HTML pages expiring in 10 min |
| `config:app` | hash | 1 | Application configuration |
| `events:stream` | stream | 50 | Event log entries |

**Total: ~124 keys** across 6 data types, with a mix of persistent and expiring keys.

Verify the data loaded:

```bash
docker exec redis-source redis-cli DBSIZE
# Expected: (integer) 124

docker exec redis-source redis-cli INFO keyspace
```

## Step 3: Open BetterDB

Open your browser to:

```
http://localhost:3001
```

You will see the BetterDB dashboard showing live metrics from the Redis source instance: memory usage, connected clients, ops/sec, and more.

## Step 4: Add the Valkey Target Connection

BetterDB starts connected to Redis (port 6379). You need to add the Valkey target as a second connection.

1. Click the **connection selector** in the top navigation bar
2. Click the **"+"** button to add a new connection
3. Enter the following details:
   - **Name:** Valkey Target
   - **Host:** valkey-target (the Docker network hostname)
   - **Port:** 6379 (internal container port; Docker maps 6399 externally)
4. Click **Save**

Both connections are now registered in BetterDB.

> **Note:** If you are running BetterDB outside Docker (e.g., via `npx`), use `localhost` as the host and `6399` as the port for the Valkey target.

## Step 5: Run the Migration Analysis

1. Navigate to the **Migration** section in BetterDB
2. Select the **Redis source** (port 6379) as the source
3. Select the **Valkey target** (port 6379 / 6399) as the target
4. Leave the sample size at the default (or increase it)
5. Click **"Analyze"**

### What to Expect

BetterDB scans the source keyspace and produces a compatibility report:

**Compatibility verdict:** Green (no blocking issues for Redis-to-Valkey)

**Data type breakdown:**
- Strings: count + estimated memory
- Hashes: count + estimated memory
- Lists: count + estimated memory
- Sets: count + estimated memory
- Sorted sets: count + estimated memory
- Streams: count + estimated memory

**TTL distribution:**
- Keys with no expiry (config, profiles, leaderboards)
- Keys expiring <1h (sessions)
- Keys expiring <24h (cached pages)

**No data has been written to the target at this point.** The analysis is read-only.

## Step 6: Execute the Migration

1. After reviewing the analysis, click **"Execute"**
2. Select **Command mode** (recommended for cross-protocol Redis-to-Valkey migrations)
3. Click **Start**

### What Happens During Execution

- BetterDB reads each key using the optimal command for its data type
- Compound types (hashes, lists, sets, sorted sets, streams) are written to a temporary staging key, then atomically renamed
- TTLs are preserved using `SET PX` for strings and Lua `RENAME + PEXPIRE` for compound types
- Real-time progress shows: transferred count, skipped count, estimated completion
- A live log viewer shows each operation

### Expected Result

```
Keys transferred: 124
Keys skipped: 0
Errors: 0
```

## Step 7: Validate the Migration

1. Click **"Validate"**
2. BetterDB runs three checks:

| Check | What It Does |
|-------|--------------|
| Key count | `DBSIZE` on both sides, flags >1% discrepancy |
| Sample spot-check | Random keys compared: type + binary-safe value match |
| Baseline comparison | Target's ops/sec, memory, fragmentation vs. source pre-migration |

### Expected Result

**Validation: PASS**

All key counts match. All sampled keys have matching types and values. TTLs preserved.

## Step 8: Manual Verification (Optional)

Verify the data arrived in Valkey:

```bash
# Check key count
docker exec valkey-target valkey-cli DBSIZE

# Check string data
docker exec valkey-target valkey-cli GET user:1:name

# Check hash data
docker exec valkey-target valkey-cli HGETALL user:1:profile

# Check list data
docker exec valkey-target valkey-cli LRANGE user:1:notifications 0 -1

# Check set data
docker exec valkey-target valkey-cli SMEMBERS tags:devops

# Check sorted set data
docker exec valkey-target valkey-cli ZRANGE leaderboard:daily 0 -1 WITHSCORES

# Check stream data
docker exec valkey-target valkey-cli XLEN events:stream

# Check TTL on a session key
docker exec valkey-target valkey-cli TTL session:token-001
```

## Cleanup

```bash
docker compose down -v
```

This stops and removes all containers and volumes.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Port 6379/6399/3001 already in use | Stop existing Redis/Valkey/app on those ports, or modify `docker-compose.yml` |
| BetterDB cannot connect to Redis | Ensure `redis-source` container is healthy: `docker compose ps` |
| Valkey target connection fails | Use `valkey-target` as hostname (Docker networking), not `localhost` |
| Migration analysis shows blocking issues | Review the compatibility report; your setup may differ from this demo |
