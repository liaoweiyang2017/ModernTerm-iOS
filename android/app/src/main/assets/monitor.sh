export LC_ALL=C
printf '__MT_META__\n'; uname -s; hostname; uname -r; uname -m
if [ "$(uname -s)" != Linux ]; then exit 0; fi
printf '__MT_OS__\n'; sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | head -1
printf '__MT_UPTIME__\n'; cat /proc/uptime
printf '__MT_LOAD__\n'; cat /proc/loadavg
printf '__MT_CPU__\n'; sed -n '/^cpu[ 0-9]/p' /proc/stat | head -513
printf '__MT_MODEL__\n'; sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1
printf '__MT_MEMORY__\n'; cat /proc/meminfo
printf '__MT_NETWORK__\n'; cat /proc/net/dev
printf '__MT_SOCKETS__\n'; cat /proc/net/sockstat
printf '__MT_DISKS__\n'; df -lPk -x tmpfs -x devtmpfs 2>/dev/null | head -33
printf '__MT_IO__\n'; cat /proc/diskstats | head -256
printf '__MT_TEMPERATURE__\n'
for zone in /sys/class/thermal/thermal_zone*; do
  [ -r "$zone/temp" ] && printf '%s\t%s\n' "$(cat "$zone/type" 2>/dev/null)" "$(cat "$zone/temp" 2>/dev/null)"
done
printf '__MT_PROCESSES__\n'; ps -eo pid=,pcpu=,pmem=,comm= --sort=-pcpu 2>/dev/null | head -12
printf '__MT_GPU__\n'
if command -v timeout >/dev/null 2>&1 && command -v nvidia-smi >/dev/null 2>&1; then
  timeout 3 nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || printf 'unavailable\n'
else printf 'unavailable\n'; fi
printf '__MT_DOCKER__\n'
if command -v timeout >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  timeout 3 docker stats --no-stream --format '{{json .}}' 2>/dev/null | head -32
else printf 'unavailable\n'; fi