#!/usr/bin/env bash

# run args on host
run() {
    # shellcheck disable=SC2029
    ssh target "$*" 1>/dev/null 2>&1
}

show_color() {
    local color="$1"

    # Get framebuffer geometry via fbset
    local fb_info
    fb_info=$(run fbset -fb /dev/fb0)

    local width height bpp
    width=$(echo "$fb_info" | awk '/geometry/ {print $2}')
    height=$(echo "$fb_info" | awk '/geometry/ {print $3}')
    bpp=$(echo "$fb_info" | awk '/geometry/ {print $6}')

    if [[ -z "$width" || -z "$height" || -z "$bpp" ]]; then
        echo "Error: could not read framebuffer geometry" >&2
        return 1
    fi

    local pixel
    case "$bpp" in
        16)
            # RGB565: green=0x07E0, red=0xF800
            if [[ "$color" == "green" ]]; then
                pixel='\xe0\x07'
            else
                pixel='\x00\xf8'
            fi
            ;;
        24)
            # BGR24
            if [[ "$color" == "green" ]]; then
                pixel='\x00\xff\x00'
            else
                pixel='\x00\x00\xff'
            fi
            ;;
        32)
            # BGRA32
            if [[ "$color" == "green" ]]; then
                pixel='\x00\xff\x00\xff'
            else
                pixel='\x00\x00\xff\xff'
            fi
            ;;
        *)
            echo "Error: unsupported bpp $bpp" >&2
            return 1
            ;;
    esac

    local pixel_count=$(( width * height ))

    echo "Filling /dev/fb0 (${width}x${height} @ ${bpp}bpp) with $color"
    run "python3 -c \"
import sys
pixel = b'${pixel}'
sys.stdout.buffer.write(pixel * ${pixel_count})
\" > /dev/fb0"
}

usage() {
    echo "Usage: $0 {green|red}"
    exit 1
}

if [[ $# -ne 1 ]] || [[ "$1" != "green" && "$1" != "red" ]]; then
    usage
fi

show_color "$1"
