#!/usr/bin/env bash
set -euo pipefail

REDIS_CLI="docker exec redis-source redis-cli"

echo "=== Loading sample data into Redis source ==="

# ------------------------------------------------------------------
# Strings: user names
# ------------------------------------------------------------------
echo "[1/10] Creating user name strings..."
for i in $(seq 1 5); do
  $REDIS_CLI SET "user:${i}:name" "User ${i}" > /dev/null
done

# ------------------------------------------------------------------
# Hashes: user profiles
# ------------------------------------------------------------------
echo "[2/10] Creating user profile hashes..."
cities=("Hyderabad" "Bangalore" "Mumbai" "Delhi" "Chennai")
roles=("DevOps Engineer" "SRE" "Backend Developer" "Platform Engineer" "Cloud Architect")
for i in $(seq 1 5); do
  idx=$((i - 1))
  $REDIS_CLI HSET "user:${i}:profile" \
    age "$((25 + i))" \
    city "${cities[$idx]}" \
    role "${roles[$idx]}" \
    active "true" \
    joined "2024-0${i}-15" > /dev/null
done

# ------------------------------------------------------------------
# Lists: notification queues
# ------------------------------------------------------------------
echo "[3/10] Creating notification lists..."
notifications=("Welcome to the platform" "Your order has shipped" "Password changed successfully" "New login detected" "Profile updated" "Payment received" "Subscription renewed" "Security alert" "Weekly digest ready" "Feature announcement")
for i in $(seq 1 5); do
  for msg in "${notifications[@]}"; do
    $REDIS_CLI RPUSH "user:${i}:notifications" "${msg}" > /dev/null
  done
done

# ------------------------------------------------------------------
# Sets: tag collections
# ------------------------------------------------------------------
echo "[4/10] Creating tag sets..."
$REDIS_CLI SADD tags:devops "kubernetes" "docker" "terraform" "ansible" "valkey" "prometheus" "grafana" "helm" > /dev/null
$REDIS_CLI SADD tags:languages "python" "go" "rust" "typescript" "java" "bash" > /dev/null
$REDIS_CLI SADD tags:cloud "aws" "gcp" "azure" "digitalocean" "hetzner" > /dev/null

# ------------------------------------------------------------------
# Sorted sets: leaderboards
# ------------------------------------------------------------------
echo "[5/10] Creating leaderboard sorted sets..."
for i in $(seq 1 20); do
  score=$((RANDOM % 1000))
  $REDIS_CLI ZADD leaderboard:daily "$score" "player:${i}" > /dev/null
done
for i in $(seq 1 20); do
  score=$((RANDOM % 5000))
  $REDIS_CLI ZADD leaderboard:weekly "$score" "player:${i}" > /dev/null
done

# ------------------------------------------------------------------
# Strings with TTL: sessions (expire in 1 hour)
# ------------------------------------------------------------------
echo "[6/10] Creating session strings with TTL..."
for i in $(seq 1 10); do
  token=$(printf "token-%03d" "$i")
  $REDIS_CLI SET "session:${token}" "{\"user_id\":${i},\"active\":true}" EX 3600 > /dev/null
done

# ------------------------------------------------------------------
# Strings with TTL: cached pages (expire in 10 minutes)
# ------------------------------------------------------------------
echo "[7/10] Creating cached page strings with TTL..."
pages=("home" "about" "pricing" "docs" "blog")
for page in "${pages[@]}"; do
  $REDIS_CLI SET "cache:page:${page}" "<html><body>Cached content for ${page}</body></html>" EX 600 > /dev/null
done

# ------------------------------------------------------------------
# Hash: application config
# ------------------------------------------------------------------
echo "[8/10] Creating application config hash..."
$REDIS_CLI HSET config:app \
  version "2.4.1" \
  environment "production" \
  max_connections "1000" \
  cache_ttl "300" \
  feature_dark_mode "enabled" \
  feature_beta "disabled" \
  maintenance "false" > /dev/null

# ------------------------------------------------------------------
# Stream: event log
# ------------------------------------------------------------------
echo "[9/10] Creating event stream..."
events=("user.login" "user.logout" "page.view" "api.request" "error.500")
for i in $(seq 1 50); do
  idx=$((RANDOM % ${#events[@]}))
  $REDIS_CLI XADD events:stream '*' \
    type "${events[$idx]}" \
    user_id "$((RANDOM % 5 + 1))" \
    timestamp "$(date +%s)" > /dev/null
done

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo "[10/10] Verifying..."
KEY_COUNT=$($REDIS_CLI DBSIZE | awk '{print $2}')
echo ""
echo "=== Done ==="
echo "Total keys loaded: ${KEY_COUNT}"
echo ""
echo "Key types summary:"
echo "  Strings (user names):     5"
echo "  Hashes (user profiles):   5"
echo "  Lists (notifications):    5"
echo "  Sets (tags):              3"
echo "  Sorted sets (boards):     2"
echo "  Strings w/ TTL (sessions):10"
echo "  Strings w/ TTL (cache):   5"
echo "  Hash (app config):        1"
echo "  Stream (events):          1"
echo "  ---"
echo "  Expected total:           37 keys (124 if counting was different - check DBSIZE above)"
echo ""
echo "Open BetterDB at http://localhost:3001 to start the migration."
