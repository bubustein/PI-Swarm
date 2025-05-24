discover_pis() {
    # Dependency check function
    check_dep() {
        command -v "$1" >/dev/null 2>&1 || {
            echo "Error: '$1' is not installed."
            case "$1" in
                nmap)
                    echo "Install it with: sudo apt update && sudo apt install nmap -y"
                    ;;
                arp)
                    echo "Install it with: sudo apt install net-tools -y"
                    ;;
                ip)
                    echo "Install it with: sudo apt install iproute2 -y"
                    ;;
                awk)
                    echo "Install it with: sudo apt install gawk -y"
                    ;;
                ssh)
                    echo "Install it with: sudo apt install openssh-client -y"
                    ;;
                host)
                    echo "Install it with: sudo apt install bind9-host -y"
                    ;;
                *)
                    echo "Please install '$1' using your package manager."
                    ;;
            esac
            exit 1
        }
    }

    # Check dependencies
    check_dep nmap
    check_dep arp
    check_dep ip
    check_dep awk
    check_dep ssh
    check_dep host

    # Find interface & subnet
    IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
    [ -z "$IFACE" ] && { echo "Could not detect active interface."; exit 1; }

    IP_CIDR=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | head -n 1)
    [ -z "$IP_CIDR" ] && { echo "Could not get IPv4 address."; exit 1; }

    SUBNET="$IP_CIDR"

    # Use a unique temp file for nmap output
    NMAP_OUT=$(mktemp /tmp/nmap_pi_scan.XXXXXX)
    rm -f /tmp/nmap_pi_scan.txt 2>/dev/null

    echo "Scanning network: $SUBNET..."
    nmap -sn "$SUBNET" -oG "$NMAP_OUT" >/dev/null

    # Pi MACs
    RPI_MACS="b8:27:eb|dc:a6:32|e4:5f:01|dc:44:6d|00:e0:4c|28:cd:c1|d8:3a:dd|ec:fa:bc|b8:31:b5|e0:4f:43"

    # Info holders
    declare -A MAC_TO_IPS
    declare -A IP_TO_MAC
    declare -A IP_TO_HOST
    declare -A MAC_TO_HOST

    # Collect info
    while read -r line; do
        if [[ "$line" =~ Host:\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            ip="${BASH_REMATCH[1]}"
            MAC=$(arp -n "$ip" | awk '/ether/ {print $3}' | tr 'A-Z' 'a-z')
            if [[ -n "$MAC" && $MAC =~ ^($RPI_MACS) ]]; then
                HOST=$(host "$ip" | awk '/domain name pointer/ {print $5}' | sed 's/\.$//')
                [ -z "$HOST" ] && HOST="(no-dns-name)"
                MAC_TO_IPS["$MAC"]+="$ip "
                IP_TO_MAC["$ip"]="$MAC"
                IP_TO_HOST["$ip"]="$HOST"
                MAC_TO_HOST["$MAC"]="$HOST"
            fi
        fi
        # Defensive: print debug if MAC is empty
        # [ -z "$MAC" ] && echo "[DEBUG] No MAC for $ip"
    done < "$NMAP_OUT"

    # Defensive: print debug if no Pis found
    if [[ ${#MAC_TO_IPS[@]} -eq 0 ]]; then
        echo "No Raspberry Pi devices found."
        echo
        read -rp "Enter comma-separated Pi IPs to manage (e.g. 192.168.3.201,192.168.3.202): " manual_ips
        IFS=',' read -ra PI_IPS <<< "$manual_ips"
        PI_HOSTNAMES=()
        for ip in "${PI_IPS[@]}"; do
            read -rp "Enter hostname for $ip (or press Enter for default): " h
            PI_HOSTNAMES+=("${h:-$ip}")
        done
        if [[ ${#PI_IPS[@]} -eq 0 ]]; then
            echo "No Pis entered. Exiting."
            rm -f "$NMAP_OUT"
            return 1
        fi
    else
        # Print table header
        printf "\n%-17s | %-30s | %-45s | %-17s | %-25s\n" "MAC Address" "Hostname" "IP Addresses" "Open SSH?" "Other Open Ports"
        printf -- "-------------------+--------------------------------+-----------------------------------------------+-------------------+-------------------------\n"
        FOUND=0
        for mac in "${!MAC_TO_IPS[@]}"; do
            host="${MAC_TO_HOST[$mac]}"
            ips="${MAC_TO_IPS[$mac]}"
            ip_list=""
            ssh_status=""
            open_ports=""
            for ip in $ips; do
                ip_list+="$ip "
                SSH_OPEN=$(nmap -Pn -p 22 "$ip" | grep "22/tcp open")
                if [[ ! -z "$SSH_OPEN" ]]; then
                    ssh_status+="Yes (ssh pi@$ip) "
                else
                    ssh_status+="No "
                fi
                PORTS=$(nmap -Pn -p 80,443,5900,8000-8100 "$ip" | awk '/^[0-9]+\/tcp/ && $2=="open" {printf "%s ", $1}')
                [ -z "$PORTS" ] && PORTS="-"
                open_ports+="$PORTS "
            done
            ip_list="${ip_list%" "}"
            ssh_status="${ssh_status%" "}"
            open_ports="${open_ports%" "}"
            printf "%-17s | %-30s | %-45s | %-17s | %-25s\n" "$mac" "$host" "$ip_list" "$ssh_status" "$open_ports"
            FOUND=1
        done
        echo
        sleep 1
        # Always prompt for selection if Pis are found
        PI_IPS=()
        PI_HOSTNAMES=()
        MAC_LIST=()
        IDX=1
        for mac in "${!MAC_TO_IPS[@]}"; do
            host="${MAC_TO_HOST[$mac]}"
            ips="${MAC_TO_IPS[$mac]}"
            for ip in $ips; do
                printf "%d) %-17s | %-30s | %-15s\n" "$IDX" "$mac" "$host" "$ip"
                MAC_LIST+=("$mac")
                PI_IPS+=("$ip")
                PI_HOSTNAMES+=("$host")
                ((IDX++))
            done
        done
        echo
        sleep 1
        read -rp "Select Pis to manage (comma-separated indices, e.g. 1,3): " selection
        IFS=',' read -ra indices <<< "$selection"
        SELECTED_IPS=()
        SELECTED_HOSTNAMES=()
        for idx in "${indices[@]}"; do
            idx=$((idx-1))
            if [[ $idx -ge 0 && $idx -lt ${#PI_IPS[@]} ]]; then
                SELECTED_IPS+=("${PI_IPS[$idx]}")
                SELECTED_HOSTNAMES+=("${PI_HOSTNAMES[$idx]}")
            fi
        done
        if [[ ${#SELECTED_IPS[@]} -eq 0 ]]; then
            echo "No Pis selected. Exiting."
            rm -f "$NMAP_OUT"
            return 1
        fi
        PI_IPS=("${SELECTED_IPS[@]}")
        PI_HOSTNAMES=("${SELECTED_HOSTNAMES[@]}")
    fi

    echo
    rm -f "$NMAP_OUT"
    export PI_IPS
    export PI_HOSTNAMES
}
