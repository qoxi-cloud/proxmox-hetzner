# shellcheck shell=bash
# Network interface and IP detection

# Detect default network interface. Sets CURRENT_INTERFACE.
_detect_default_interface() {
  if cmd_exists ip && cmd_exists jq; then
    CURRENT_INTERFACE=$(ip -j route 2>/dev/null | jq -r '.[] | select(.dst == "default") | .dev' | head -n1)
  elif cmd_exists ip; then
    CURRENT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
  elif cmd_exists route; then
    CURRENT_INTERFACE=$(route -n | awk '/^0\.0\.0\.0/ {print $8}' | head -n1)
  fi

  if [[ -z $CURRENT_INTERFACE ]]; then
    if cmd_exists ip && cmd_exists jq; then
      CURRENT_INTERFACE=$(ip -j link show 2>/dev/null | jq -r '.[] | select(.ifname != "lo" and .operstate == "UP") | .ifname' | head -n1)
    elif cmd_exists ip; then
      CURRENT_INTERFACE=$(ip link show | awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2; exit}')
    elif cmd_exists ifconfig; then
      CURRENT_INTERFACE=$(ifconfig -a | awk '/^[a-z]/ && !/^lo/ {print $1; exit}' | tr -d ':')
    fi
  fi

  if [[ -z $CURRENT_INTERFACE ]]; then
    CURRENT_INTERFACE="eth0"
    log "WARNING: Could not detect network interface, defaulting to eth0"
  fi
}

# Get predictable interface name from udev. Sets PREDICTABLE_NAME, DEFAULT_INTERFACE.
_detect_predictable_name() {
  PREDICTABLE_NAME=""

  if [[ -e "/sys/class/net/${CURRENT_INTERFACE}" ]]; then
    local udev_info
    udev_info=$(udevadm info "/sys/class/net/${CURRENT_INTERFACE}" 2>/dev/null)

    PREDICTABLE_NAME=$(printf '%s\n' "$udev_info" | grep "ID_NET_NAME_PATH=" | cut -d'=' -f2)

    if [[ -z $PREDICTABLE_NAME ]]; then
      PREDICTABLE_NAME=$(printf '%s\n' "$udev_info" | grep "ID_NET_NAME_ONBOARD=" | cut -d'=' -f2)
    fi

    if [[ -z $PREDICTABLE_NAME ]]; then
      PREDICTABLE_NAME=$(ip -d link show "$CURRENT_INTERFACE" 2>/dev/null | grep "altname" | awk '{print $2}' | head -1)
    fi
  fi

  if [[ -n $PREDICTABLE_NAME ]]; then
    DEFAULT_INTERFACE="$PREDICTABLE_NAME"
  else
    DEFAULT_INTERFACE="$CURRENT_INTERFACE"
  fi
}

# Get available interfaces. Sets AVAILABLE_INTERFACES, INTERFACE_NAME, etc.
_detect_available_interfaces() {
  AVAILABLE_ALTNAMES=$(ip -d link show | grep -v "lo:" | grep -E '(^[0-9]+:|altname)' | awk '/^[0-9]+:/ {interface=$2; gsub(/:/, "", interface); printf "%s", interface} /altname/ {printf ", %s", $2} END {print ""}' | sed 's/, $//')

  if cmd_exists ip && cmd_exists jq; then
    AVAILABLE_INTERFACES=$(ip -j link show 2>/dev/null | jq -r '.[] | select(.ifname != "lo") | .ifname' | sort)
  elif cmd_exists ip; then
    AVAILABLE_INTERFACES=$(ip link show | awk -F': ' '/^[0-9]+:/ && !/lo:/ {print $2}' | sort)
  else
    AVAILABLE_INTERFACES="$CURRENT_INTERFACE"
  fi

  INTERFACE_COUNT=$(printf '%s\n' "$AVAILABLE_INTERFACES" | wc -l)

  if [[ -z $INTERFACE_NAME ]]; then
    INTERFACE_NAME="$DEFAULT_INTERFACE"
  fi
}

# IP address detection

# Detect IPv4 address and gateway. Sets MAIN_IPV4, MAIN_IPV4_CIDR, MAIN_IPV4_GW.
_detect_ipv4() {
  local max_attempts="${SSH_RETRY_ATTEMPTS:-3}"
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))

    if cmd_exists ip && cmd_exists jq; then
      MAIN_IPV4_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null | jq -r '.[0].addr_info[] | select(.family == "inet" and .scope == "global") | "\(.local)/\(.prefixlen)"' | head -n1)
      MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
      MAIN_IPV4_GW=$(ip -j route 2>/dev/null | jq -r '.[] | select(.dst == "default") | .gateway' | head -n1)
      [[ -n $MAIN_IPV4 ]] && [[ -n $MAIN_IPV4_GW ]] && return 0
    elif cmd_exists ip; then
      MAIN_IPV4_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null | grep global | grep "inet " | awk '{print $2}' | head -n1)
      MAIN_IPV4="${MAIN_IPV4_CIDR%/*}"
      MAIN_IPV4_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n1)
      [[ -n $MAIN_IPV4 ]] && [[ -n $MAIN_IPV4_GW ]] && return 0
    elif cmd_exists ifconfig; then
      MAIN_IPV4=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/inet / {print $2}' | sed 's/addr://')
      local netmask
      netmask=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/inet / {print $4}' | sed 's/Mask://')
      if [[ -n $MAIN_IPV4 ]] && [[ -n $netmask ]]; then
        case "$netmask" in
          255.255.255.0) MAIN_IPV4_CIDR="${MAIN_IPV4}/24" ;;
          255.255.255.128) MAIN_IPV4_CIDR="${MAIN_IPV4}/25" ;;
          255.255.255.192) MAIN_IPV4_CIDR="${MAIN_IPV4}/26" ;;
          255.255.255.224) MAIN_IPV4_CIDR="${MAIN_IPV4}/27" ;;
          255.255.255.240) MAIN_IPV4_CIDR="${MAIN_IPV4}/28" ;;
          255.255.255.248) MAIN_IPV4_CIDR="${MAIN_IPV4}/29" ;;
          255.255.255.252) MAIN_IPV4_CIDR="${MAIN_IPV4}/30" ;;
          255.255.0.0) MAIN_IPV4_CIDR="${MAIN_IPV4}/16" ;;
          *) MAIN_IPV4_CIDR="${MAIN_IPV4}/24" ;;
        esac
      fi
      if cmd_exists route; then
        MAIN_IPV4_GW=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/ {print $2}' | head -n1)
      fi
      [[ -n $MAIN_IPV4 ]] && [[ -n $MAIN_IPV4_GW ]] && return 0
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      log "Network info attempt $attempt failed, retrying in ${RETRY_DELAY_SECONDS:-2} seconds..."
      sleep "${RETRY_DELAY_SECONDS:-2}"
    fi
  done
}

# Detect MAC and IPv6 info. Sets MAC_ADDRESS, IPV6_*, MAIN_IPV6.
_detect_ipv6_and_mac() {
  if cmd_exists ip && cmd_exists jq; then
    MAC_ADDRESS=$(ip -j link show "$CURRENT_INTERFACE" 2>/dev/null | jq -r '.[0].address // empty')
    IPV6_CIDR=$(ip -j address show "$CURRENT_INTERFACE" 2>/dev/null | jq -r '.[0].addr_info[] | select(.family == "inet6" and .scope == "global") | "\(.local)/\(.prefixlen)"' | head -n1)
  elif cmd_exists ip; then
    MAC_ADDRESS=$(ip link show "$CURRENT_INTERFACE" 2>/dev/null | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ip address show "$CURRENT_INTERFACE" 2>/dev/null | grep global | grep "inet6 " | awk '{print $2}' | head -n1)
  elif cmd_exists ifconfig; then
    MAC_ADDRESS=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/ether/ {print $2}')
    IPV6_CIDR=$(ifconfig "$CURRENT_INTERFACE" 2>/dev/null | awk '/inet6/ && /global/ {print $2}')
  fi
  MAIN_IPV6="${IPV6_CIDR%/*}"

  if [[ -n $IPV6_CIDR ]]; then
    local ipv6_prefix="${MAIN_IPV6%%:*:*:*:*}"
    if [[ $ipv6_prefix == "$MAIN_IPV6" ]] || [[ -z $ipv6_prefix ]]; then
      ipv6_prefix=$(printf '%s' "$MAIN_IPV6" | cut -d':' -f1-4)
    fi
    FIRST_IPV6_CIDR="${ipv6_prefix}:1::1/80"
  else
    FIRST_IPV6_CIDR=""
  fi

  if [[ -n $MAIN_IPV6 ]]; then
    if cmd_exists ip; then
      IPV6_GATEWAY=$(ip -6 route 2>/dev/null | grep default | awk '{print $3}' | head -n1)
    fi
  fi
}
