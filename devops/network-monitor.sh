#!/bin/bash
# Script Name: network-monitor.sh
# Description: Real-time network monitoring and troubleshooting tool
# Author: huangxl-github / Adapted from network diagnostics best practices
# Usage: ./network-monitor.sh [command]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Command: network-info - Display comprehensive network information
show_network_info() {
    print_info "System Network Configuration"
    echo ""
    
    # IP addresses and interfaces
    echo -e "${CYAN}=== IP Addresses & Interfaces ==${NC}"
    if command -v ip &> /dev/null; then
        ip addr show | grep -E "^[0-9]+:|inet " || true
    else
        ifconfig 2>/dev/null | grep -E "^[a-z]|inet " || true
    fi
    
    echo ""
    echo -e "${CYAN}=== Active Connections ==${NC}"
    ss -tuln 2>/dev/null | head -20 || netstat -tuln 2>/dev/null | head -20
    
    # Check DNS resolution
    echo ""
    echo -e "${CYAN}=== DNS Configuration ==${NC}"
    if [ -f "/etc/resolv.conf" ]; then
        cat /etc/resolv.conf | grep nameserver | sed 's/nameserver/  📍/g'
    fi
    
    print_info "Testing DNS resolution..."
    dig google.com +short &>/dev/null || nslookup google.com &>/dev/null | grep "Address:" | sed 's/Address:[[:space:]]*//' || echo "  ✗ DNS test failed"
    
    # Check default gateway
    echo ""
    echo -e "${CYAN}=== Default Gateway ==${NC}"
    if command -v ip &> /dev/null; then
        ip route show default | head -1 | sed 's/default via/  📍/'
    else
        route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print "  Gateway: "$2}' || true
    fi
}

# Command: ping-test - Ping multiple hosts and show statistics
ping_test() {
    TARGETS=("${1:-8.8.8.8}" "${2:-google.com}" "${3:-github.com}")
    
    print_info "Testing network connectivity..."
    echo ""
    
    for target in "${TARGETS[@]}"; do
        echo -e "${CYAN}Pinging: $target${NC}"
        
        if command -v ping &> /dev/null; then
            PING_OUTPUT=$(timeout 5 ping -c 3 "$target" 2>/dev/null || true)
            
            if [ -n "$PING_OUTPUT" ]; then
                MIN_RTT=$(echo "$PING_OUTPUT" | grep -oE "min/avg/max/dev[[:space:]]+[0-9.]+" | awk '{print $NF}' | cut -d'/' -f1 || echo "N/A")
                MAX_PACKET_LOSS=$(echo "$PING_OUTPUT" | grep -oE "[0-9]+% packet loss" | head -1 || echo "N/A")
                
                printf "  %s\n" "Latency (min): $MIN_RTT"
                printf "  %s\n" "Packet Loss: $MAX_PACKET_LOSS"
            fi
        else
            print_warning "ping command not available on this system"
        fi
        
        echo ""
    done
    
    # Additional connectivity test
    print_info "Testing HTTP connectivity..."
    
    for host in "google.com" "github.com" "microsoft.com"; do
        RESPONSE_TIME=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 5 "https://$host" 2>/dev/null || echo "N/A")
        
        STATUS="✓"
        [ "$RESPONSE_TIME" = "N/A" ] && STATUS="✗"
        
        printf "  %s %-15s: %s s\n" "$STATUS" "$host" "$RESPONSE_TIME"
    done
}

# Command: port-scan - Check which ports are open/available
port_scan() {
    PORT="${1:-8080}"
    TARGET="${2:-localhost}"
    
    print_info "Scanning port(s) on $TARGET"
    echo ""
    
    if [ "${PORT//,/ }" != "$PORT" ]; then
        # Multiple ports (range or comma-separated)
        for p in ${PORT//,/ }; do
            check_port "$TARGET" "$p"
        done
    elif [[ "$PORT" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        # Port range
        START=${BASH_REMATCH[1]}
        END=${BASH_REMATCH[2]}
        
        for ((p=START; p<=END; p++)); do
            check_port "$TARGET" "$p"
        done
    else
        check_port "$TARGET" "$PORT"
    fi
}

check_port() {
    TARGET=$1
    PORT=$2
    
    if command -v nc &> /dev/null; then
        timeout 1 bash -c "echo >/dev/tcp/$TARGET/$PORT" 2>/dev/null && {
            echo -e "  ${GREEN}✓${NC} $TARGET:$PORT is OPEN"
            return 0
        }
    elif lsof -i :$PORT &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $TARGET:$PORT is in use\n$(lsof -i :$PORT | head -5)"
        return 0
    else
        echo -e "  ${RED}✗${NC} $TARGET:$PORT is CLOSED"
        return 1
    fi
}

# Command: bandwidth-test - Test network bandwidth (download/upload)
bandwidth_test() {
    SERVER="${1:-}"
    
    print_info "Network Speed Test"
    echo ""
    
    # Download test using curl/iperf3 if available
    if command -v iperf3 &> /dev/null; then
        print_info "Using iPerf3 for accurate measurement..."
        
        DOWNLOAD_SPEED=$(iperf3 -c "$SERVER" 2>/dev/null | grep "receiver" | tail -1 | awk '{print $4, $5}' || echo "N/A")
        echo "Download: $DOWNLOAD_SPEED"
    else
        # Fallback to simple HTTP test
        TEMP_FILE=$(mktemp)
        
        print_info "Testing download speed..."
        
        START_TIME=$(date +%s%N)
        curl -o "$TEMP_FILE" --connect-timeout 5 --speed-limit 1000 https://speed.hetzner.de/10Mio.bin 2>/dev/null || {
            print_warning "Download test failed. Using alternative..."
            rm -f "$TEMP_FILE"
            
            START_TIME=$(date +%s%N)
            curl -o "$TEMP_FILE" --connect-timeout 5 "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png"
            END_TIME=$(date +%s%N)
            
            if [ -f "$TEMP_FILE" ]; then
                FILE_SIZE_BYTES=$(stat -c%s "$TEMP_FILE")  # Mac: stat -f%z
                SLEEPING=$(( (END_TIME - START_TIME) / 1000000 ))
                
                if [ "$SLEEPING" -gt 0 ]; then
                    KBPS=$((FILE_SIZE_BYTES * 8 / ${SLEEPING} / 1024))
                    
                    printf "Download: %d Kbps\n" "$KBPS"
                fi
                
                rm -f "$TEMP_FILE"
            else
                echo "Speed test not available"
            fi
        }
    fi
    
    print_info "Note: This is a simple estimate. Use Speedtest.net or Ookla for accurate results."
}

# Command: whois-lookup - Get domain WHOIS information
whois_lookup() {
    if [ "$#" -lt 1 ]; then
        print_error "Usage: $0 whois <domain>"
        return 1
    fi
    
    DOMAIN="$1"
    
    print_info "WHOIS information for: $DOMAIN"
    echo ""
    
    if command -v whois &> /dev/null; then
        whois "$DOMAIN" | grep -E "Domain Name|Organization|Expir|Created" || true
    else
        # Fallback to curl on WHOIS service
        curl -s "https://api.ipwho.is/$DOMAIN" 2>/dev/null || {
            print_warning "WHOIS lookup not available. Install 'whois' package."
        }
    fi
}

# Command: port-availability - Find available ports for application deployment
find_available_port() {
    START_PORT="${1:-3000}"
    END_PORT="${2:-$((START_PORT + 50))}"
    
    print_info "Finding available ports between $START_PORT and $END_PORT"
    echo ""
    
    AVAILABLE_PORTS=()
    INUSE_PORTS=()
    
    for ((port=START_PORT; port<=END_PORT; port++)); do
        check_port "localhost" "$port" >/dev/null 2>&1 && {
            INUSE_PORTS+=("$port")
        } || {
            AVAILABLE_PORTS+=("$port")
        }
    done
    
    echo -e "${CYAN}Available ports (${#AVAILABLE_PORTS[@]}):${NC}"
    printf "  %s\n" "${AVAILABLE_PORTS[@]}"
    
    echo ""
    echo -e "${CYAN}Ports in use (${#INUSE_PORTS[@]}):${NC}"
    if [ ${#INUSE_PORTS[@]} -gt 0 ]; then
        printf "  %s\n" "${INUSE_PORTS[@]}"
    else
        echo "  (none found)"
    fi
    
    if [ ${#AVAILABLE_PORTS[@]} -gt 0 ]; then
        echo ""
        print_success "First available port: ${AVAILABLE_PORTS[0]}"
    fi
}

# Show usage
show_usage() {
    echo ""
    echo "${BLUE}=== Network Monitoring Utility ==${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Available Commands:"
    echo -e "  ${CYAN}info${NC}                    Show network configuration"
    echo -e "  ${CYAN}ping [host1] [host2]... ${NC}   Test connectivity to hosts"
    echo -e "  ${CYAN}port <num|range> [target]${NC}  Check port availability"
    echo -e "  ${CYAN}available [start][end]${NC}   Find available ports (default: 3000-3050)"
    echo -e "  ${CYAN}speed [server]${NC}        Test network bandwidth"
    echo -e "  ${CYAN}whois <domain> ${NC}         Get domain WHOIS info"
    echo ""
    echo "Examples:"
    echo "  $0 info                          # Show all network info"
    echo "  $0 ping google.com github.com   # Ping multiple hosts"
    echo "  $0 port 8080-9000 localhost      # Scan ports 8080-9000"
    echo "  $0 available                     # Find first free port from 3000"
    echo "  $0 speed                         # Test download speed"
    echo "  $0 whois google.com              # WHOIS lookup"
    echo ""
}

# Main command dispatcher
case "${1:-help}" in
    info)
        show_network_info
        ;;
    ping)
        shift
        ping_test "$@"
        ;;
    port|scan)
        shift
        port_scan "$@"
        ;;
    available|free)
        shift
        find_available_port "$@"
        ;;
    speed|bandwidth)
        shift
        bandwidth_test "$@"
        ;;
    whois)
        shift
        whois_lookup "$@"
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
