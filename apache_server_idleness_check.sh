 #!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOG_FILE="/var/log/apache2/access.log"
MAX_IDLE_MINUTES=5

# Get current time and last modified time of the access log (in seconds since epoch)
CURRENT_TIME=$(date +%s)
LAST_MODIFIED=$(stat -c %Y "$LOG_FILE")

# Calculate idle time in minutes
IDLE_MINUTES=$(( (CURRENT_TIME - LAST_MODIFIED) / 60 ))

# If idle for too long, stop Apache
if [ "$IDLE_MINUTES" -ge "$MAX_IDLE_MINUTES" ]; then
   echo "$(date +"%H:%M")" >> apache_cron.log

   sudo /usr/bin/systemctl stop apache2
fi

