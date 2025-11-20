#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

convert_socks_to_http() {
    local input_file=$1
    local proxy_user=$2
    local proxy_pass=$3
    
    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        echo -e "${RED}Usage: $0 <input.ovpn> [proxy_user] [proxy_pass]${NC}"
        echo -e "${YELLOW}Example: $0 config.ovpn test11 test11${NC}"
        return 1
    fi
    
    # Default proxy settings
    local proxy_host="87.106.64.47"
    local proxy_port="3128"
    proxy_user=${proxy_user:-"test11"}
    proxy_pass=${proxy_pass:-"test11"}
    
    # Output filename
    local output_file="${input_file%.ovpn}-httpproxy.ovpn"
    
    echo -e "${CYAN}Converting config...${NC}"
    echo "  Input:  $input_file"
    echo "  Output: $output_file"
    echo ""
    
    # Copy original
    cp "$input_file" "$output_file"
    
    # Remove SOCKS5 options
    sed -i '/socks-proxy/d' "$output_file"
    sed -i '/socks-proxy-retry/d' "$output_file"
    sed -i '/socks-proxy-username/d' "$output_file"
    sed -i '/socks-proxy-password/d' "$output_file"
    
    # Add HTTP proxy with authentication
    local auth_base64=$(echo -n "$proxy_user:$proxy_pass" | base64 -w 0)
    
    # Add after 'remote' line
    sed -i "/^remote /a http-proxy $proxy_host $proxy_port\nhttp-proxy-option CUSTOM-HEADER \"Proxy-Authorization\" \"Basic $auth_base64\"" "$output_file"
    
    echo -e "${GREEN}✓ Conversion complete!${NC}"
    echo ""
    echo -e "${YELLOW}Changes made:${NC}"
    echo "  ✗ Removed: All socks-proxy options"
    echo "  ✓ Added: http-proxy $proxy_host:$proxy_port"
    echo "  ✓ Added: Proxy authentication"
    echo ""
    echo -e "${CYAN}New config saved to:${NC}"
    echo "  $output_file"
    echo ""
    echo -e "${YELLOW}Upload this to your device and test!${NC}"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    convert_socks_to_http "$@"
fi
