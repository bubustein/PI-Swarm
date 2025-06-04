#!/bin/bash

# Pi Discovery Script with Network Scanning
# Shows detected Raspberry Pi devices before prompting for IP input

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
        return 1
    }
}

# Enhanced Pi discovery function
discover_and_scan_pis() {
    log INFO "🔍 Starting Pi discovery and network scan..."
    
    # Check dependencies (non-fatal for graceful degradation)
    local deps_available=true
    for dep in nmap arp ip awk ssh host; do
        if ! check_dep "$dep"; then
            log WARN "Dependency '$dep' not available - falling back to manual IP input"
            deps_available=false
            break
        fi
    done
    
    if [[ "$deps_available" == "false" ]]; then
        log INFO "Network scanning unavailable - please enter Pi IP addresses manually"
        prompt_for_pi_ips
        return $?
    fi
    
    # Find interface & subnet
    local IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
    if [[ -z "$IFACE" ]]; then
        log WARN "Could not detect active network interface - falling back to manual input"
        prompt_for_pi_ips
        return $?
    fi
    
    local IP_CIDR=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | head -n 1)
    if [[ -z "$IP_CIDR" ]]; then
        log WARN "Could not get IPv4 address - falling back to manual input"
        prompt_for_pi_ips
        return $?
    fi
    
    local SUBNET="$IP_CIDR"
    
    echo ""
    echo "🔍 Scanning network: $SUBNET for Raspberry Pi devices..."
    echo "   This may take 15-30 seconds..."
    
    # Create temporary file
    local scan_file="/tmp/nmap_pi_scan_$(date +%s).txt"
    
    # Run network scan
    if ! nmap -sn "$SUBNET" -oG "$scan_file" >/dev/null 2>&1; then
        log WARN "Network scan failed - falling back to manual input"
        rm -f "$scan_file"
        prompt_for_pi_ips
        return $?
    fi
    
    # Pi MAC address prefixes (known Raspberry Pi Foundation MAC ranges)
    local RPI_MACS="b8:27:eb|dc:a6:32|e4:5f:01|dc:44:6d|00:e0:4c|28:cd:c1|d8:3a:dd|ec:fa:bc|b8:31:b5|e0:4f:43"
    
    # Info holders
    declare -A MAC_TO_IPS
    declare -A IP_TO_MAC
    declare -A IP_TO_HOST
    declare -A MAC_TO_HOST
    
    # Collect device information
    while read -r line; do
        if [[ "$line" =~ Host:\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            local ip="${BASH_REMATCH[1]}"
            local MAC=$(arp -n "$ip" 2>/dev/null | awk '/ether/ {print $3}' | tr 'A-Z' 'a-z')
            if [[ $MAC =~ ^($RPI_MACS) ]]; then
                local HOST=$(host "$ip" 2>/dev/null | awk '/domain name pointer/ {print $5}' | sed 's/\.$//')
                [[ -z "$HOST" ]] && HOST="(no-dns-name)"
                MAC_TO_IPS["$MAC"]+="$ip "
                IP_TO_MAC["$ip"]="$MAC"
                IP_TO_HOST["$ip"]="$HOST"
                MAC_TO_HOST["$MAC"]="$HOST"
            fi
        fi
    done < "$scan_file"
    
    # Display results
    echo ""
    echo "🔍 Pi Discovery Results:"
    echo "========================"
    
    if [[ ${#MAC_TO_IPS[@]} -eq 0 ]]; then
        echo "❌ No Raspberry Pi devices found on network $SUBNET"
        echo ""
        log INFO "No Pi devices detected - proceeding with manual IP input"
        prompt_for_pi_ips
    else
        echo "✅ Found ${#MAC_TO_IPS[@]} Raspberry Pi device(s):"
        echo ""
        
        # Print table header
        printf "%-17s | %-25s | %-15s | %-12s | %-20s\n" "MAC Address" "Hostname" "IP Address" "SSH Status" "Other Ports"
        printf -- "-------------------+---------------------------+-----------------+--------------+--------------------\n"
        
        # Collect discovered IPs for auto-suggestion
        local discovered_ips=()
        
        # For each device
        for mac in "${!MAC_TO_IPS[@]}"; do
            local host="${MAC_TO_HOST[$mac]}"
            local ips="${MAC_TO_IPS[$mac]}"
            
            for ip in $ips; do
                # Check SSH status
                local ssh_status="Checking..."
                if timeout 3 bash -c "</dev/tcp/$ip/22" 2>/dev/null; then
                    ssh_status="✅ Open"
                else
                    ssh_status="❌ Closed"
                fi
                
                # Quick port check for common services
                local other_ports=""
                for port in 80 443 5900 8080; do
                    if timeout 1 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
                        other_ports+="$port "
                    fi
                done
                [[ -z "$other_ports" ]] && other_ports="-"
                
                # Print the table row
                printf "%-17s | %-25s | %-15s | %-12s | %-20s\n" "$mac" "$host" "$ip" "$ssh_status" "$other_ports"
                
                # Add to discovered IPs for suggestion
                discovered_ips+=("$ip")
            done
        done
        
        echo ""
        
        # Offer auto-selection or manual input
        if [[ ${#discovered_ips[@]} -gt 0 ]]; then
            echo "🎯 Auto-detected Pi IP addresses: ${discovered_ips[*]}"
            echo ""
            echo "Choose an option:"
            echo "1. Use all detected Pi IPs (${discovered_ips[*]})"
            echo "2. Select specific IPs from detected list"
            echo "3. Enter IP addresses manually"
            echo ""
            
            while true; do
                if [ ! -t 0 ]; then
                    choice=1
                    echo "[INFO] Non-interactive mode: defaulting to option 1 (all detected Pi IPs)"
                else
                    read -p "Enter your choice (1-3): " choice
                fi
                case $choice in
                    1)
                        PI_IPS="${discovered_ips[*]}"
                        log INFO "Using all detected Pi IPs: $PI_IPS"
                        break
                        ;;
                    2)
                        echo ""
                        echo "Available Pi IPs:"
                        for i in "${!discovered_ips[@]}"; do
                            echo "$((i+1)). ${discovered_ips[i]}"
                        done
                        echo ""
                        if [ ! -t 0 ]; then
                            selections="1"
                            echo "[INFO] Non-interactive mode: defaulting to first Pi IP only"
                        else
                            read -p "Enter numbers separated by spaces (e.g., 1 3): " selections
                        fi
                        selected_ips=()
                        for num in $selections; do
                            if [[ $num =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#discovered_ips[@]} ]]; then
                                selected_ips+=("${discovered_ips[$((num-1))]}")
                            fi
                        done
                        if [[ ${#selected_ips[@]} -gt 0 ]]; then
                            PI_IPS="${selected_ips[*]}"
                            log INFO "Using selected Pi IPs: $PI_IPS"
                            break
                        else
                            echo "❌ Invalid selection. Please try again."
                        fi
                        ;;
                    3)
                        prompt_for_pi_ips
                        break
                        ;;
                    *)
                        echo "❌ Invalid choice. Please enter 1, 2, or 3."
                        ;;
                esac
            done
        else
            prompt_for_pi_ips
        fi
    fi
    
    # Cleanup
    rm -f "$scan_file"
    
    # Validate final IP selection
    if [[ -z "$PI_IPS" ]]; then
        log ERROR "No Pi IP addresses provided"
        return 1
    fi
    
    # Test connectivity to selected IPs
    echo ""
    echo "🔍 Testing connectivity to selected Pi devices..."
    local reachable_count=0
    local total_count=0
    
    log INFO "DEBUG: Starting connectivity tests for PI_IPS: '$PI_IPS'"
    
    for ip in $PI_IPS; do
        total_count=$((total_count + 1))
        echo -n "  Testing $ip... "
        log INFO "DEBUG: Testing connectivity to $ip"
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo "✅ Reachable"
            reachable_count=$((reachable_count + 1))
            log INFO "DEBUG: $ip is reachable"
        else
            echo "❌ Unreachable"
            log INFO "DEBUG: $ip is unreachable"
        fi
    done
    
    log INFO "DEBUG: Connectivity test complete. Reachable: $reachable_count, Total: $total_count"
    
    echo ""
    if [[ $reachable_count -eq $total_count ]]; then
        log INFO "✅ All Pi devices ($reachable_count/$total_count) are reachable"
    elif [[ $reachable_count -gt 0 ]]; then
        log WARN "⚠️ Only $reachable_count/$total_count Pi devices are reachable"
        if [ ! -t 0 ]; then
            # Non-interactive mode: continue with available devices
            log INFO "Non-interactive mode: continuing with $reachable_count available Pi devices"
        else
            # Interactive mode: ask user
            echo "Would you like to continue with reachable devices only? (y/n)"
            read -r continue_choice
            if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                log INFO "Deployment cancelled by user"
                return 1
            fi
        fi
    else
        log ERROR "❌ No Pi devices are reachable. Please check network connectivity."
        return 1
    fi
    
    export PI_IPS
    return 0
}

# Fallback function for manual IP input
prompt_for_pi_ips() {
    echo ""
    echo "📝 Manual Pi IP Configuration"
    echo "============================="
    echo ""
    echo "Please enter the IP addresses of your Raspberry Pi devices."
    echo "Examples:"
    echo "  Single Pi:     192.168.1.100"
    echo "  Multiple Pis:  192.168.1.100 192.168.1.101 192.168.1.102"
    echo "  Range format:  192.168.1.{100..102}"
    echo ""
    
    while true; do
        read -p "Enter Pi IP addresses (space-separated): " input_ips
        
        if [[ -z "$input_ips" ]]; then
            echo "❌ Please enter at least one IP address."
            continue
        fi
        
        # Expand brace notation if used
        if [[ "$input_ips" =~ \{.*\} ]]; then
            input_ips=$(eval echo "$input_ips")
        fi
        
        # Validate IP format
        valid_ips=""
        invalid_count=0
        
        for ip in $input_ips; do
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # Basic IP format validation
                IFS='.' read -ra octets <<< "$ip"
                valid_ip=true
                for octet in "${octets[@]}"; do
                    if [[ $octet -gt 255 ]]; then
                        valid_ip=false
                        break
                    fi
                done
                
                if [[ "$valid_ip" == "true" ]]; then
                    valid_ips+="$ip "
                else
                    echo "❌ Invalid IP address: $ip"
                    invalid_count=$((invalid_count + 1))
                fi
            else
                echo "❌ Invalid IP format: $ip"
                invalid_count=$((invalid_count + 1))
            fi
        done
        
        if [[ $invalid_count -eq 0 && -n "$valid_ips" ]]; then
            PI_IPS="${valid_ips% }"  # Remove trailing space
            echo "✅ Using Pi IP addresses: $PI_IPS"
            break
        else
            echo "Please correct the invalid IP addresses and try again."
        fi
    done
    
    export PI_IPS
}
