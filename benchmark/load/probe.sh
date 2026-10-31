#!/usr/bin/env bash
# Tries, on the machine it runs on, what the deploy shapes rely on. Each of these
# came from documentation, so this is where they meet a real runner
# (.shipkit/specs/deploy-shape-benchmark/design.md).
#
#   benchmark/load/probe.sh [FILE]    also append the table to FILE
#
# Exits 1 if a PASS/FAIL check fails. INFO rows only report. Every check runs
# whatever the others do, because the point is to see all of them at once.

set -u

RUBY_IMAGE=ruby:3.4-slim
ALPINE_IMAGE=alpine:3.20
K6_IMAGE=grafana/k6:1.8.2
NETWORK=red-probe
DATABASE=red-probe-db
DELAY_MS=1
BURN_SECONDS=10

summary=${1:-}
failed=0

# shellcheck disable=SC2329 # the trap below runs it
cleanup() {
  docker rm -f "$DATABASE" >/dev/null 2>&1
  docker network rm "$NETWORK" >/dev/null 2>&1
}
trap cleanup EXIT

say() {
  printf '%s\n' "$1"
  if [ -n "$summary" ]; then printf '%s\n' "$1" >>"$summary"; fi
}

# One table row, whatever a command's output looked like.
row() {
  say "| $1 | $2 | $(printf '%s' "$3" | tr '\n' ' ') |"
  if [ "$2" = "FAIL" ]; then failed=1; fi
}

# Up front, or Docker's progress lines land in the first check's captured output
# and fail it on every fresh runner.
pull_images() {
  local image
  for image in "$RUBY_IMAGE" "$ALPINE_IMAGE" "$K6_IMAGE"; do
    if ! docker pull --quiet "$image" >/dev/null 2>&1; then
      row "Pull $image" FAIL "docker pull failed"
    fi
  done
}

# Is the value within the range? awk, because these are decimals.
between() {
  awk -v value="$1" -v low="$2" -v high="$3" 'BEGIN { exit !(value >= low && value <= high) }'
}

# The host's stolen and total CPU ticks, or nothing where there's no /proc/stat.
ticks() {
  if [ -r /proc/stat ]; then
    awk '/^cpu / { print $9, $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9 }' /proc/stat
  fi
}

# The share of CPU time stolen between two readings of ticks().
steal_share() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "not available"
    return
  fi
  printf '%s %s\n' "$1" "$2" | awk '{
    total = $4 - $2
    printf "%.2f%%", (total > 0 ? 100 * ($3 - $1) / total : 0)
  }'
}

# Average round trip in ms from a fresh container to the database container.
round_trip() {
  docker run --rm --network "$NETWORK" "$ALPINE_IMAGE" ping -q -c 20 -i 0.2 "$DATABASE" 2>/dev/null |
    awk -F/ '/round-trip/ { print $4 }'
}

check_cpuset() {
  local seen
  seen=$(docker run --rm --cpuset-cpus=0,1 "$RUBY_IMAGE" ruby -retc -e 'print Etc.nprocessors' 2>&1)
  if [ "$seen" = "2" ]; then
    row "cpuset: Ruby sees 2 CPUs" PASS "Etc.nprocessors = $seen"
  else
    row "cpuset: Ruby sees 2 CPUs" FAIL "got: ${seen:0:200}"
  fi
}

check_memory() {
  local seen
  seen=$(docker run --rm --memory=4g --memory-swap=4g "$RUBY_IMAGE" \
    sh -c 'cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max' 2>&1 | tr '\n' ' ')
  if [ "$seen" = "4294967296 0 " ]; then
    row "Memory: 4 GB, no swap" PASS "memory.max and memory.swap.max: $seen"
  else
    row "Memory: 4 GB, no swap" FAIL "got: ${seen:0:200}"
  fi
}

# 0.4 of a CPU for BURN_SECONDS is 0.4 * BURN_SECONDS of CPU time, however many
# threads ask for more. The steal reading shows whether a quota looks like steal.
check_quota() {
  local before after stats throttled used
  before=$(ticks)
  stats=$(docker run --rm --cpuset-cpus=0,1 --cpus=0.4 -e "BURN=$BURN_SECONDS" "$RUBY_IMAGE" sh -c '
    for i in 1 2; do timeout "$BURN" sh -c "while :; do :; done" & done
    wait
    cat /sys/fs/cgroup/cpu.stat' 2>&1)
  after=$(ticks)
  throttled=$(awk '/^nr_throttled/ { print $2 }' <<<"$stats")
  used=$(awk -v burn="$BURN_SECONDS" '/^usage_usec/ { printf "%.2f", $2 / 1000000 / burn }' <<<"$stats")

  if [ "${throttled:-0}" -gt 0 ] && between "${used:-0}" 0.32 0.48; then
    row "Quota: 0.4 CPU of time" PASS "used ${used} CPU, throttled ${throttled} times"
  else
    row "Quota: 0.4 CPU of time" FAIL "used ${used:-?} CPU, throttled ${throttled:-?} times"
  fi
  row "Host CPU time stolen while throttled" INFO "$(steal_share "$before" "$after")"
}

check_network_delay() {
  local base delayed added
  # A runner's kernel may not have it loaded. Where this can't load it, tc below
  # says so.
  sudo -n modprobe sch_netem 2>/dev/null

  if ! docker network create "$NETWORK" >/dev/null 2>&1 ||
    ! docker run -d --name "$DATABASE" --network "$NETWORK" --cap-add NET_ADMIN "$ALPINE_IMAGE" sleep 300 >/dev/null 2>&1 ||
    ! docker exec "$DATABASE" apk add --no-cache --quiet iproute2 >/dev/null 2>&1; then
    row "netem: ${DELAY_MS} ms delay" FAIL "couldn't start the containers"
    return
  fi

  base=$(round_trip)
  local errors
  if ! errors=$(docker exec "$DATABASE" tc qdisc add dev eth0 root netem delay "${DELAY_MS}ms" 2>&1); then
    row "netem: ${DELAY_MS} ms delay" FAIL "tc: ${errors:0:200}"
    return
  fi
  delayed=$(round_trip)
  added=$(awk -v a="${delayed:-0}" -v b="${base:-0}" 'BEGIN { printf "%.2f", a - b }')

  # Within 20%, the line the design draws before falling back to Toxiproxy.
  if between "$added" 0.8 1.2; then
    row "netem: ${DELAY_MS} ms delay" PASS "round trip ${base} ms, then ${delayed} ms: added ${added} ms"
  else
    row "netem: ${DELAY_MS} ms delay" FAIL "round trip ${base:-?} ms, then ${delayed:-?} ms: added ${added} ms"
  fi
}

check_load_generator() {
  local seen
  if seen=$(docker run --rm "$K6_IMAGE" version 2>&1); then
    row "k6 runs on this architecture" PASS "${seen:0:80}"
  else
    row "k6 runs on this architecture" FAIL "${seen:0:200}"
  fi
}

check_compose() {
  local seen
  if seen=$(docker compose version 2>&1); then
    row "Docker Compose" PASS "$seen"
  else
    row "Docker Compose" FAIL "${seen:0:200}"
  fi
}

# Nothing here is a shape's limit: this is what the runner gave us, with every
# CPU busy for a while, to see if steal ever shows on its own.
report_machine() {
  local model before after
  model=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo 2>/dev/null)
  row "CPU" INFO "${model:-no model name in /proc/cpuinfo}"
  row "Architecture" INFO "$(uname -m), kernel $(uname -r)"
  row "CPUs" INFO "$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
  row "Threads per core" INFO "$(lscpu 2>/dev/null | awk -F': *' '/^Thread\(s\) per core/ { print $2 }')"
  row "CPU 0 shares a core with" INFO \
    "$(cat /sys/devices/system/cpu/cpu0/topology/thread_siblings_list 2>/dev/null || echo unknown)"

  before=$(ticks)
  for _ in $(seq 1 "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"); do
    timeout "$BURN_SECONDS" bash -c 'while :; do :; done' &
  done
  wait
  after=$(ticks)
  row "Host CPU time stolen with every CPU busy" INFO "$(steal_share "$before" "$after")"
}

say "## Deploy benchmark: runner probe"
say ""
say "| Check | Result | Detail |"
say "|---|---|---|"
pull_images
report_machine
check_cpuset
check_memory
check_quota
check_network_delay
check_load_generator
check_compose

exit "$failed"
