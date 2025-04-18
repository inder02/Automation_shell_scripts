#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

install_required_package(){

# === REQUIRED COMMANDS ===
REQUIRED_CMDS=("iostat" "bc" "ss" "top" "free" "ps" "docker")

# === Detect OS ===
if [ -f /etc/os-release ]; then
    OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
else
    echo "❌ Cannot detect OS type. /etc/os-release not found."
    exit 1
fi

echo "🖥️ Detected OS: $OS_ID"
echo "🔍 Checking required commands..."

# === Function to check if command exists ===
missing_cmds=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "⛔ Missing: $cmd"
        missing_cmds+=("$cmd")
    else
        echo "✅ Found: $cmd"
    fi
done

if [ ${#missing_cmds[@]} -eq 0 ]; then
    echo "🎉 All required commands are already installed."
    exit 0
fi

echo
echo "🚧 Installing missing packages..."

# === Install based on OS ===
case "$OS_ID" in
    ubuntu|debian)
        sudo apt update
        sudo apt install -y sysstat bc iproute2 docker.io
        ;;
    centos|rhel|amzn|ol)
        sudo yum install -y sysstat bc iproute docker
        ;;
    alpine)
        sudo apk update
        sudo apk add sysstat bc iproute2 docker
        ;;
    *)
        echo "❌ Unsupported OS: $OS_ID. Please install manually: ${missing_cmds[*]}"
        exit 1
        ;;
esac

echo "✅ Installation complete."

}

#installing dependency
install_required_package


# === CONFIGURATION ===
SAMPLE_INTERVAL_MINUTES=5              # Run this script every 10 mins via cron/systemd
IDLE_THRESHOLD_MINUTES=10               # System must be idle for the past 60 minutes
HISTORY_FILE="$HOME/idle_state.log"  # Stores idle activity history
MAX_ENTRIES=$((IDLE_THRESHOLD_MINUTES / SAMPLE_INTERVAL_MINUTES))
CPU_IDLE_THRESHOLD=85
RAM_USAGE_THRESHOLD=20
DISK_ACTIVITY_THRESHOLD=300
NET_CONNECTION_THRESHOLD=1
LOG_FILE="$HOME/idle_shutdown.log"
metric_file="$HOME/METRIC_LOG.log"
# === Logging Function ===
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# === Collect Metrics ===

# Count non-root logged-in users
active_users=$(who | awk '$1 != "root"' | wc -l)

# CPU Idle %
cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/[^0-9.]//g' | cut -d'.' -f1)

# RAM usage %
mem_total=$(free -m | awk '/Mem:/ {print $2}')
mem_used=$(free -m | awk '/Mem:/ {print $3}')
ram_usage=$(( (100 * mem_used) / mem_total ))

# Disk I/O activity (sum of read+write IOPS)
disk_io=$(iostat -d 1 2 | awk '/^Device/ {getline; getline} {sum += $3 + $4} END {print sum}'  | cut -d'.' -f1)

# Network connections
net_connections=$(ss -tun state established | wc -l)

# User processes (excluding root/system)
active_processes=$(ps -eo user,tty | awk '$1 != "root" && $2 != "?"' | wc -l)

# Docker containers running
containers_running=$(docker ps -q | wc -l)

echo "$active_users","$containers_running","$active_processes", "$cpu_idle","$ram_usage", "$disk_io", "$net_connections" >> "$metric_file"
# === Determine if current sample is idle ===
is_idle=true
echo "$is_idle" >> "$metric_file"
[[ "$active_users" -gt 0 ]] && is_idle=false
echo "$is_idle"	>> "$metric_file"

[[ "$containers_running" -gt 0 ]] && is_idle=false
echo "$is_idle"	>> "$metric_file"

[[ "$active_processes" -gt 2 ]] && is_idle=false
echo "$is_idle"	>> "$metric_file"

[[ "$cpu_idle" -lt "$CPU_IDLE_THRESHOLD" ]] && is_idle=false

echo "$is_idle"	>> "$metric_file"

[[ "$ram_usage" -gt "$RAM_USAGE_THRESHOLD" ]] && is_idle=false
echo "$is_idle"	>> "$metric_file"

[[ "$disk_io" -gt "$DISK_ACTIVITY_THRESHOLD" ]] && is_idle=false
echo "$is_idle"	>> "$metric_file"

[[ "$net_connections" -gt "$NET_CONNECTION_THRESHOLD" ]] && is_idle=false
echo "$is_idle"	>> "$metric_file"

timestamp=$(date +%s)
status=$([[ "$is_idle" == true ]] && echo "idle" || echo "active")

# === Save to history ===
echo "$timestamp $status" >> "$HISTORY_FILE"

# Trim history to the last $MAX_ENTRIES lines
tail -n "$MAX_ENTRIES" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"

# === Evaluate Idle History ===
idle_count=$(grep "idle" "$HISTORY_FILE" | wc -l)

if [ "$idle_count" -eq "$MAX_ENTRIES" ]; then
    log "✅ System has been idle for $IDLE_THRESHOLD_MINUTES minutes. Initiating shutdown."
   sudo /sbin/shutdown -h now
else
    log "ℹ️ System not idle for full duration. Idle samples: $idle_count/$MAX_ENTRIES."
fi

