#!/usr/bin/env bash

# run args on host
run() {
    # shellcheck disable=SC2029
    ssh target "$*"
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
            # RGB565: green=0x07E0, red=0xF800, yellow=0xFFE0
            case "$color" in
                green)  pixel='\xe0\x07' ;;
                red)    pixel='\x00\xf8' ;;
                yellow) pixel='\xe0\xff' ;;
            esac
            ;;
        24)
            # BGR24
            case "$color" in
                green)  pixel='\x00\xff\x00' ;;
                red)    pixel='\x00\x00\xff' ;;
                yellow) pixel='\x00\xff\xff' ;;
            esac
            ;;
        32)
            # BGRA32
            case "$color" in
                green)  pixel='\x00\xff\x00\xff' ;;
                red)    pixel='\x00\x00\xff\xff' ;;
                yellow) pixel='\x00\xff\xff\xff' ;;
            esac
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
    echo "Usage: $0 {green|red|yellow}"
    exit 1
}

if [[ $# -ne 1 ]] || [[ "$1" != "green" && "$1" != "red" && "$1" != "yellow" ]]; then
    usage
fi

show_color "$1"
