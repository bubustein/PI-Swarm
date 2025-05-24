default_subnet() {
    ip route | awk '/src/ {print $1}' | head -n1
}

default_gateway() {
    ip route | awk '/default/ {print $3}' | head -n1
}

default_dns() {
    awk '/nameserver/ {print $2; exit}' /etc/resolv.conf
}
