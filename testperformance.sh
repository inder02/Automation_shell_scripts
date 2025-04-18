#!/bin/bash

# Output file
OUTPUT_FILE="laptop_category.txt"
LOG_FILE="performance_log.txt"

# Clean old log
> "$LOG_FILE"

echo "Running performance tests..." | tee -a "$LOG_FILE"

# ------------------ CPU Performance Test ------------------
echo "Running CPU benchmark on all threads..." | tee -a "$LOG_FILE"
CPU_THREADS=$(nproc)
CPU_EVENTS_PER_SEC=$(sysbench cpu --cpu-max-prime=20000 --threads=$CPU_THREADS run | grep "events per second:" | awk '{print int($NF)}')
echo "CPU Threads     : $CPU_THREADS" | tee -a "$LOG_FILE"
echo "CPU Events/sec  : $CPU_EVENTS_PER_SEC" | tee -a "$LOG_FILE"

# ------------------ RAM Performance Test ------------------
echo "Running RAM benchmark (using full system memory)..." | tee -a "$LOG_FILE"
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/ { print $2 }')
MEM_SPEED_MBPS=$(sysbench memory \
  --threads=$CPU_THREADS \
  --memory-block-size=1M \
  --memory-total-size=${TOTAL_MEM_MB}M run | \
  grep "transferred" | awk '{print int($1)}')
echo "Total Memory     : ${TOTAL_MEM_MB} MB" | tee -a "$LOG_FILE"
echo "RAM Speed        : $MEM_SPEED_MBPS MB/s" | tee -a "$LOG_FILE"

# ------------------ Disk Write Speed Test ------------------
echo "Running Disk write speed test with fio..." | tee -a "$LOG_FILE"

# Run fio test
FIO_OUTPUT=$(fio --name=disk-test --filename=tempfile --size=512M --bs=1M --rw=write --direct=1 --numjobs=1 --time_based --runtime=10s --group_reporting)

# Parse the first MB/s from WRITE line
DISK_WRITE_MBPS=$(echo "$FIO_OUTPUT" | grep -i "WRITE:" | grep -o '[0-9.]\+MB/s' | head -n1 | sed 's/MB\/s//' | awk '{print int($1)}')

# Clean up
rm -f tempfile
echo "Disk Write Speed (fio): ${DISK_WRITE_MBPS} MB/s" | tee -a "$LOG_FILE"

# ------------------ Score Calculation ------------------
CPU_WEIGHT=2
MEM_WEIGHT=1
DISK_WEIGHT=2

TOTAL_SCORE=$((CPU_EVENTS_PER_SEC * CPU_WEIGHT + MEM_SPEED_MBPS * MEM_WEIGHT + DISK_WRITE_MBPS * DISK_WEIGHT))
echo "Total Score: $TOTAL_SCORE"
# ------------------ Categorization (Revised Thresholds) ------------------
if [ "$TOTAL_SCORE" -ge 100000 ]; then
    CATEGORY="P1"
elif [ "$TOTAL_SCORE" -ge 50000 ]; then
    CATEGORY="P2"
else
    CATEGORY="P3"
fi

# ------------------ Output Result ------------------
echo "-----------------------------" | tee -a "$LOG_FILE"
echo "TOTAL PERFORMANCE SCORE: $TOTAL_SCORE" | tee -a "$LOG_FILE"
echo "LAPTOP CATEGORY        : $CATEGORY" | tee -a "$LOG_FILE"

# Save category
echo "$CATEGORY" > "$OUTPUT_FILE"
