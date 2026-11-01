#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---preview}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sgbu"
CONFIG_FILE="$CONFIG_DIR/xmb.conf"

if [ -r "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            SGBU_XMB_COLOR)
                [ -n "${SGBU_XMB_COLOR+x}" ] || SGBU_XMB_COLOR="$value"
                ;;
            SGBU_XMB_ICONS)
                [ -n "${SGBU_XMB_ICONS+x}" ] || SGBU_XMB_ICONS="$value"
                ;;
        esac
    done < "$CONFIG_FILE"
fi

if [ "$MODE" = "--preview" ]; then
    ITEM_IDS=(retroarch steam desktop bluetooth terminal diagnostics setting-color setting-icons reboot shutdown exit)
    ITEM_LABELS=(
        "GAME|RetroArch"
        "GAME|Steam (GamepadUI)"
        "SETTINGS|Desktop Session"
        "NETWORK|Bluetooth Manager"
        "SETTINGS|Terminal"
        "SETTINGS|Run Diagnostics"
        "SETTINGS|Background Color"
        "SETTINGS|Icon Set"
        "USERS|Restart System"
        "USERS|Turn Off System"
        "USERS|Exit UI Preview"
    )
elif [ "$MODE" = "--menu" ]; then
    shift
    if [ "$#" -eq 0 ] || [ "$(( $# % 2 ))" -ne 0 ]; then
        echo "Usage: $0 --menu item-id item-label [item-id item-label ...]" >&2
        exit 2
    fi
    while [ "$#" -gt 0 ]; do
        ITEM_IDS+=("$1")
        ITEM_LABELS+=("$2")
        shift 2
    done
else
    echo "Usage: $0 [--preview | --menu item-id item-label ...]" >&2
    exit 2
fi

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo "XMB UI needs an interactive terminal." >&2
    exit 1
fi

CATEGORY_NAMES=(USERS SETTINGS PHOTO MUSIC VIDEO GAME NETWORK FRIENDS)
CATEGORY_ICONS_UNICODE=("☺" "⚙" "▧" "♫" "▣" "◆" "◎" "☻")
CATEGORY_ICONS_ASCII=("U" "S" "P" "M" "V" "G" "N" "F")
ICON_STYLE="${SGBU_XMB_ICONS:-unicode}"
COLOR_STYLE="${SGBU_XMB_COLOR:-auto}"
COLOR_OPTIONS=(auto blue purple green red cyan)
ICON_OPTIONS=(unicode ascii)
CATEGORY_INDEX=0
SELECTED_ITEM=-1
TERM_SIZE=$(stty size < /dev/tty)
read -r TERM_ROWS TERM_COLS <<< "$TERM_SIZE"
TERM_ROWS="${TERM_ROWS:-24}"
TERM_COLS="${TERM_COLS:-80}"
(( TERM_ROWS < 22 )) && TERM_ROWS=22
(( TERM_COLS < 60 )) && TERM_COLS=60

set_background_color() {
    local month="${1:-01}"
    local color="${2:-$COLOR_STYLE}"
    local month_number
    case "$color" in
        auto)
            case "$month" in
                01) BG_R=14; BG_G=35; BG_B=92 ;;
                02) BG_R=30; BG_G=34; BG_B=105 ;;
                03) BG_R=18; BG_G=64; BG_B=105 ;;
                04) BG_R=15; BG_G=78; BG_B=100 ;;
                05) BG_R=13; BG_G=88; BG_B=83 ;;
                06) BG_R=18; BG_G=78; BG_B=64 ;;
                07) BG_R=20; BG_G=67; BG_B=68 ;;
                08) BG_R=30; BG_G=59; BG_B=83 ;;
                09) BG_R=55; BG_G=52; BG_B=92 ;;
                10) BG_R=72; BG_G=45; BG_B=91 ;;
                11) BG_R=54; BG_G=39; BG_B=91 ;;
                12) BG_R=34; BG_G=39; BG_B=108 ;;
                *) BG_R=14; BG_G=35; BG_B=92 ;;
            esac
            ;;
        blue) BG_R=14; BG_G=35; BG_B=92 ;;
        purple) BG_R=52; BG_G=30; BG_B=91 ;;
        green) BG_R=14; BG_G=67; BG_B=61 ;;
        red) BG_R=91; BG_G=31; BG_B=43 ;;
        cyan) BG_R=10; BG_G=65; BG_B=83 ;;
        *)
            printf 'Unknown SGBU_XMB_COLOR "%s"; using automatic monthly colors.\n' "$color" >&2
            color=auto
            COLOR_STYLE=auto
            set_background_color "$month"
            return
            ;;
    esac

    BG_GREEN_STEP=2
    BG_BLUE_STEP=3
    case "$color" in
        auto)
            month_number=$((10#$month))
            BG_GREEN_STEP=$(( (month_number % 3) + 1 ))
            BG_BLUE_STEP=$(( (month_number % 4) + 1 ))
            ;;
    esac
}

if [ "$COLOR_STYLE" != "auto" ] && [ "$COLOR_STYLE" != "blue" ] &&
    [ "$COLOR_STYLE" != "purple" ] && [ "$COLOR_STYLE" != "green" ] &&
    [ "$COLOR_STYLE" != "red" ] && [ "$COLOR_STYLE" != "cyan" ]; then
    printf 'Unknown SGBU_XMB_COLOR "%s"; using automatic monthly colors.\n' "$COLOR_STYLE" >&2
    COLOR_STYLE=auto
fi

if [ "$ICON_STYLE" != "unicode" ] && [ "$ICON_STYLE" != "ascii" ]; then
    printf 'Unknown SGBU_XMB_ICONS "%s"; using unicode icons.\n' "$ICON_STYLE" >&2
    ICON_STYLE=unicode
fi

apply_icon_style() {
    if [ "$ICON_STYLE" = "ascii" ]; then
        CATEGORY_ICONS=("${CATEGORY_ICONS_ASCII[@]}")
    else
        CATEGORY_ICONS=("${CATEGORY_ICONS_UNICODE[@]}")
    fi
}

save_settings() {
    local temporary_file
    if ! mkdir -p "$CONFIG_DIR"; then
        printf 'Unable to create XMB settings directory: %s\n' "$CONFIG_DIR" >&2
        return 1
    fi
    if ! temporary_file=$(mktemp "$CONFIG_DIR/xmb.conf.XXXXXX"); then
        printf 'Unable to create temporary XMB settings file in %s\n' "$CONFIG_DIR" >&2
        return 1
    fi
    if ! {
        printf 'SGBU_XMB_COLOR=%s\n' "$COLOR_STYLE"
        printf 'SGBU_XMB_ICONS=%s\n' "$ICON_STYLE"
    } > "$temporary_file" || ! mv -f -- "$temporary_file" "$CONFIG_FILE"; then
        rm -f -- "$temporary_file"
        printf 'Unable to save XMB settings to %s\n' "$CONFIG_FILE" >&2
        return 1
    fi
}

update_settings_labels() {
    local i color_label
    case "$COLOR_STYLE" in
        auto) color_label="Auto (monthly)" ;;
        *) color_label="${COLOR_STYLE^}" ;;
    esac

    for i in "${!ITEM_IDS[@]}"; do
        case "${ITEM_IDS[$i]}" in
            setting-color) ITEM_LABELS[$i]="SETTINGS|Background Color: $color_label" ;;
            setting-icons) ITEM_LABELS[$i]="SETTINGS|Icon Set: ${ICON_STYLE^}" ;;
        esac
    done
}

apply_icon_style

CURRENT_MONTH=$(date +%m)
set_background_color "$CURRENT_MONTH" "$COLOR_STYLE"
update_settings_labels

get_os_name() {
    local name=""
    if [ -r /etc/os-release ]; then
        name=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -n 1 | tr -d '"')
    fi
    if [ -z "$name" ]; then
        name=$(uname -srm 2>/dev/null || printf 'Unknown OS')
    fi
    printf '%s' "$name"
}

get_memory_info() {
    local memory
    memory=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2; exit}')
    if [ -z "$memory" ] && [ -r /proc/meminfo ]; then
        memory=$(awk '
            /^MemTotal:/ { total = $2 }
            /^MemAvailable:/ { available = $2 }
            END {
                if (total && available) {
                    used_gb = (total - available) / 1000000
                    total_gb = total / 1000000
                    printf "%.1f/%.1f GB", used_gb, total_gb
                }
            }
        ' /proc/meminfo)
    fi
    printf '%s' "${memory:-Unknown}"
}

get_cpu_info() {
    local cpu
    cpu=$(awk -F ': *' '/^(model name|Hardware|Processor)[[:space:]]*:/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
    if [ -z "$cpu" ] && command -v lscpu >/dev/null 2>&1; then
        cpu=$(lscpu 2>/dev/null | awk -F ': *' '/^Model name:/ {print $2; exit}')
    fi
    printf '%s' "${cpu:-Unknown}"
}

get_gpu_info() {
    local gpu="" device driver pci_id vendor
    if command -v nvidia-smi >/dev/null 2>&1; then
        gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1)
    fi
    if command -v lspci >/dev/null 2>&1; then
        [ -n "$gpu" ] || gpu=$(lspci 2>/dev/null | awk -F ': ' '/VGA compatible controller|3D controller|Display controller/ {print $2; exit}')
    fi

    if [ -z "$gpu" ]; then
        for device in /sys/class/drm/card[0-9]/device; do
            [ -r "$device/uevent" ] || continue
            driver=$(basename "$(readlink -f "$device/driver" 2>/dev/null)" 2>/dev/null || true)
            pci_id=$(sed -n 's/^PCI_ID=//p' "$device/uevent" | head -n 1)
            vendor="${pci_id%%:*}"
            case "$vendor" in
                1002) vendor="AMD" ;;
                10DE) vendor="NVIDIA" ;;
                8086) vendor="Intel" ;;
                1AF4) vendor="Virtio" ;;
                "") vendor="" ;;
                *) vendor="PCI $vendor" ;;
            esac
            gpu="${vendor:-GPU}"
            [ -n "$driver" ] && gpu="$gpu ($driver)"
            [ -n "$pci_id" ] && gpu="$gpu [$pci_id]"
            break
        done
    fi
    printf '%s' "${gpu:-Unknown}"
}

OS_NAME=$(get_os_name)
MEMORY_INFO=$(get_memory_info)
CPU_INFO=$(get_cpu_info)
GPU_INFO=$(get_gpu_info)
CPU_THREADS=$(nproc --all 2>/dev/null || nproc 2>/dev/null || printf 'Unknown')
if command -v lscpu >/dev/null 2>&1; then
    CPU_CORES=$(lscpu -p=CORE,SOCKET 2>/dev/null | awk -F, '
        !/^#/ && NF > 1 { cores[$1 "," $2] = 1 }
        END { for (core in cores) count++; print count + 0 }
    ')
else
    CPU_CORES="$CPU_THREADS"
fi
CPU_CORES="${CPU_CORES:-$CPU_THREADS}"
GPU_DRIVER=""
GPU_DRIVER_VERSION=""
GPU_VRAM="Unknown"
GPU_VRAM_PERCENT="N/A"
GPU_USAGE="N/A"
GPU_TEMP="N/A"
GPU2_INFO=""
GPU2_DRIVER="Unknown"
GPU2_DRIVER_VERSION="Unknown"
GPU2_VRAM="Unknown"
GPU2_USAGE="N/A"
GPU2_TEMP="N/A"
GPU_COUNT=0
CARD_GPU_USAGE="N/A"
declare -A GPU_IDLE_RESIDENCY=() GPU_IDLE_TIMESTAMP=()
CPU_USAGE="N/A"
CPU_TEMP="N/A"
RAM_USAGE="Unknown"
RAM_PERCENT="N/A"
LAST_CPU_TOTAL=0
LAST_CPU_IDLE=0
LAST_METRICS_UPDATE=0
METRICS_UPDATED=0
CLOCK_VALUE=""
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GYRO_SENSOR="${SGBU_GYRO_SENSOR:-$SCRIPT_DIR/gyro-sensor.py}"
GYRO_STATUS="automatic drift (no gyro)"
GYRO_FD=""
GYRO_PID=""
NEEDS_RENDER=1
PARTICLES_DRAWN=0
PARTICLE_COUNT=12
declare -a PARTICLE_X=() PARTICLE_Y=() PARTICLE_VX=() PARTICLE_VY=()

get_temperature() {
    local device label input value candidate="" max_value=0
    for device in /sys/class/hwmon/hwmon*; do
        [ -d "$device" ] || continue
        for input in "$device"/temp*_input; do
            [ -r "$input" ] || continue
            label="${input%_input}_label"
            [ -r "$label" ] && label=$(<"$label") || label=""
            case "${label,,}" in
                *cpu*|*package*|*tctl*|*tdie*|*core*) ;;
                *) continue ;;
            esac
            value=$(<"$input")
            if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ] && [ "$value" -lt 150000 ]; then
                printf '%s' "$((value / 1000))"
                return
            fi
        done
    done

    for input in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$input" ] || continue
        value=$(<"$input")
        if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt "$max_value" ] && [ "$value" -lt 150000 ]; then
            max_value="$value"
        fi
    done
    if [ "$max_value" -gt 0 ]; then
        candidate="$((max_value / 1000))"
    fi
    printf '%s' "${candidate:-N/A}"
}

get_card_temperature() {
    local device="$1" vendor="$2" gpu_path hwmon hwmon_path input label value fallback=""
    gpu_path=$(readlink -f "$device" 2>/dev/null || true)
    if [ -z "$gpu_path" ]; then
        printf 'N/A'
        return
    fi
    for hwmon in "$device"/hwmon/hwmon* /sys/class/hwmon/hwmon*; do
        [ -d "$hwmon" ] || continue
        hwmon_path=$(readlink -f "$hwmon/device" 2>/dev/null || true)
        case "$hwmon_path" in
            "$gpu_path"|"$gpu_path"/*) ;;
            *) continue ;;
        esac
        for input in "$hwmon"/temp*_input; do
            [ -r "$input" ] || continue
            value=$(<"$input")
            [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ] && [ "$value" -lt 150000 ] || continue
            label="${input%_input}_label"
            [ -r "$label" ] && label=$(<"$label") || label=""
            case "$vendor:${label,,}" in
                AMD:*edge*|AMD:*junction*|Intel:*GPU*|Intel:*Package*)
                    printf '%s' "$((value / 1000))"
                    return
                    ;;
            esac
            fallback="$value"
        done
    done
    if [ -n "$fallback" ]; then
        printf '%s' "$((fallback / 1000))"
    else
        printf 'N/A'
    fi
}

get_card_gpu_usage() {
    local device="$1" vendor="$2" card_path input usage rc6_file idle_ms now_ms previous_idle previous_time elapsed_ms idle_delta
    card_path="${device%/device}"
    CARD_GPU_USAGE="N/A"
    case "$vendor" in
        Intel)
            for input in "$card_path/gt_busy_percent" "$device/gt_busy_percent"; do
                [ -r "$input" ] || continue
                usage=$(<"$input")
                if [[ "$usage" =~ ^[0-9]+$ ]]; then
                    CARD_GPU_USAGE="$usage"
                    return
                fi
            done
            rc6_file="$card_path/gt/gt0/rc6_residency_ms"
            [ -r "$rc6_file" ] || rc6_file="$device/gt/gt0/rc6_residency_ms"
            if [ -r "$rc6_file" ]; then
                idle_ms=$(<"$rc6_file")
                now_ms=$(awk '{ printf "%d", $1 * 1000 }' /proc/uptime)
                if [[ "$idle_ms" =~ ^[0-9]+$ ]] && [[ "$now_ms" =~ ^[0-9]+$ ]]; then
                    local card_index="${card_path##*card}"
                    previous_idle="${GPU_IDLE_RESIDENCY[$card_index]:-}"
                    previous_time="${GPU_IDLE_TIMESTAMP[$card_index]:-}"
                    GPU_IDLE_RESIDENCY[$card_index]="$idle_ms"
                    GPU_IDLE_TIMESTAMP[$card_index]="$now_ms"
                    if [[ "$previous_idle" =~ ^[0-9]+$ ]] &&
                        [[ "$previous_time" =~ ^[0-9]+$ ]] &&
                        [ "$idle_ms" -ge "$previous_idle" ] &&
                        [ "$now_ms" -gt "$previous_time" ]; then
                        elapsed_ms=$((now_ms - previous_time))
                        idle_delta=$((idle_ms - previous_idle))
                        CARD_GPU_USAGE=$((100 - idle_delta * 100 / elapsed_ms))
                        [ "$CARD_GPU_USAGE" -ge 0 ] || CARD_GPU_USAGE=0
                        [ "$CARD_GPU_USAGE" -le 100 ] || CARD_GPU_USAGE=100
                    fi
                fi
            fi
            ;;
        AMD|NVIDIA)
            for input in "$device/gpu_busy_percent" "$card_path/gpu_busy_percent"; do
                [ -r "$input" ] || continue
                usage=$(<"$input")
                if [[ "$usage" =~ ^[0-9]+$ ]]; then
                    CARD_GPU_USAGE="$usage"
                    return
                fi
            done
            ;;
    esac
}

get_gpu_driver() {
    local device driver
    for device in /sys/class/drm/card[0-9]/device; do
        [ -e "$device/driver" ] || continue
        driver=$(basename "$(readlink -f "$device/driver" 2>/dev/null)" 2>/dev/null || true)
        if [ -n "$driver" ]; then
            printf '%s' "$driver"
            return
        fi
    done
    printf 'Unknown'
}

get_gpu_driver_version() {
    local driver="${1:-$GPU_DRIVER}" nvidia_index="${2:-}" version
    if [ "$driver" != "Unknown" ] && command -v modinfo >/dev/null 2>&1; then
        version=$(modinfo -F version "$driver" 2>/dev/null | head -n 1)
        if [ -n "$version" ]; then
            printf '%s' "$version"
            return
        fi
    fi
    if [ "$driver" = nvidia ] && command -v nvidia-smi >/dev/null 2>&1; then
        if [ -n "$nvidia_index" ]; then
            version=$(nvidia-smi --id="$nvidia_index" --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1)
        else
            version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1)
        fi
        if [ -n "$version" ]; then
            printf '%s' "$version"
            return
        fi
    fi
    case "$driver" in
        nouveau|i915|xe|amdgpu)
            uname -r
            return
            ;;
    esac
    printf 'Unknown'
}

get_gpu_vram() {
    local device bytes nvidia_memory used total percent="N/A"
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1)
        if [ -n "$nvidia_memory" ]; then
            used="${nvidia_memory%%,*}"
            total="${nvidia_memory#*,}"
            total="${total//[!0-9]/}"
            used="${used//[!0-9]/}"
            if [ "$total" -gt 0 ]; then
                percent=$((used * 100 / total))
            fi
            printf '%s/%s MiB|%s' "$used" "$total" "$percent"
            return
        fi
    fi
    for device in /sys/class/drm/card[0-9]/device/mem_info_vram_total; do
        [ -r "$device" ] || continue
        bytes=$(<"$device")
        if [[ "$bytes" =~ ^[0-9]+$ ]]; then
            local used_file="${device%/*}/mem_info_vram_used"
            if [ -r "$used_file" ]; then
                used=$(<"$used_file")
                if [[ "$used" =~ ^[0-9]+$ ]] && [ "$bytes" -gt 0 ]; then
                    percent=$((used * 100 / bytes))
                    printf '%s/%s GB|%s' \
                        "$(awk -v bytes="$used" 'BEGIN { printf "%.1f", bytes / 1000000000 }')" \
                        "$(awk -v bytes="$bytes" 'BEGIN { printf "%.1f", bytes / 1000000000 }')" \
                        "$percent"
                    return
                fi
            fi
            awk -v bytes="$bytes" 'BEGIN { printf "%.1f GB|N/A", bytes / 1000000000 }'
            return
        fi
    done
    printf 'Unknown|N/A'
}

update_cpu_usage() {
    local total idle delta_total delta_idle
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle=$((idle + iowait))
    if [ "$LAST_CPU_TOTAL" -gt 0 ] && [ "$total" -gt "$LAST_CPU_TOTAL" ]; then
        delta_total=$((total - LAST_CPU_TOTAL))
        delta_idle=$((idle - LAST_CPU_IDLE))
        CPU_USAGE=$(( (delta_total - delta_idle) * 100 / delta_total ))
    fi
    LAST_CPU_TOTAL="$total"
    LAST_CPU_IDLE="$idle"
}

update_gpu_usage() {
    local device vendor_id vendor driver model nvidia_index=0 nvidia_stats nvidia_id
    local usage="" vram_info temperature="N/A" driver_version
    GPU_COUNT=0
    GPU2_INFO=""
    GPU2_DRIVER="Unknown"
    GPU2_DRIVER_VERSION="Unknown"
    GPU2_VRAM="Unknown"
    GPU_USAGE="N/A"
    GPU_TEMP="N/A"
    GPU2_USAGE="N/A"
    GPU2_TEMP="N/A"

    for device in /sys/class/drm/card[0-9]/device; do
        [ -d "$device" ] || continue
        vendor_id=""
        if [ -r "$device/vendor" ]; then
            vendor_id=$(<"$device/vendor")
        fi
        case "${vendor_id,,}" in
            0x1002) vendor=AMD ;;
            0x8086) vendor=Intel ;;
            0x10de) vendor=NVIDIA ;;
            *) continue ;;
        esac

        driver=$(basename "$(readlink -f "$device/driver" 2>/dev/null)" 2>/dev/null || true)
        model=""
        if command -v lspci >/dev/null 2>&1; then
            model=$(lspci -s "$(basename "$(readlink -f "$device")")" 2>/dev/null | awk -F ': ' '{print $NF}')
        fi
        model="${model:-$vendor GPU}"
        usage=""
        vram_info=""
        temperature="N/A"
        nvidia_id=""

        if [ "$vendor" = NVIDIA ] && command -v nvidia-smi >/dev/null 2>&1; then
            nvidia_id="$nvidia_index"
            nvidia_index=$((nvidia_index + 1))
            nvidia_stats=$(nvidia-smi --id="$nvidia_id" \
                --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total \
                --format=csv,noheader,nounits 2>/dev/null | head -n 1)
            if [ -n "$nvidia_stats" ]; then
                IFS=',' read -r temperature usage vram_used vram_total <<< "$nvidia_stats"
                temperature="${temperature//[!0-9]/}"
                usage="${usage//[!0-9]/}"
                vram_used="${vram_used//[!0-9]/}"
                vram_total="${vram_total//[!0-9]/}"
                [ -n "$temperature" ] || temperature=N/A
                [ -n "$usage" ] || usage=N/A
                if [[ "$vram_used" =~ ^[0-9]+$ ]] && [[ "$vram_total" =~ ^[0-9]+$ ]]; then
                    vram_info="$((vram_used / 1024))/$((vram_total / 1024)) MiB"
                fi
            fi
        else
            temperature=$(get_card_temperature "$device" "$vendor")
        fi
        if [ -z "$usage" ]; then
            get_card_gpu_usage "$device" "$vendor"
            [ "$CARD_GPU_USAGE" = "N/A" ] || usage="$CARD_GPU_USAGE"
        fi
        driver="${driver:-Unknown}"
        driver_version=$(get_gpu_driver_version "$driver" "$nvidia_id")
        if [ -z "$vram_info" ] && [ -r "$device/mem_info_vram_total" ]; then
            local vram_total_bytes vram_used_bytes
            vram_total_bytes=$(<"$device/mem_info_vram_total")
            vram_used_bytes=0
            [ -r "$device/mem_info_vram_used" ] && vram_used_bytes=$(<"$device/mem_info_vram_used")
            if [[ "$vram_total_bytes" =~ ^[0-9]+$ ]] && [[ "$vram_used_bytes" =~ ^[0-9]+$ ]]; then
                vram_info="$(awk -v used="$vram_used_bytes" -v total="$vram_total_bytes" \
                    'BEGIN { printf "%.1f/%.1f GB", used / 1000000000, total / 1000000000 }')"
            fi
        fi
        [ -n "$vram_info" ] || vram_info="Shared"

        if [ "$GPU_COUNT" -eq 0 ]; then
            GPU_INFO="$model"
            GPU_DRIVER="$driver"
            GPU_DRIVER_VERSION="$driver_version"
            GPU_USAGE="${usage:-N/A}"
            GPU_TEMP="$temperature"
            GPU_VRAM="$vram_info"
        else
            GPU2_INFO="$model"
            GPU2_DRIVER="$driver"
            GPU2_DRIVER_VERSION="$driver_version"
            GPU2_VRAM="$vram_info"
            GPU2_USAGE="${usage:-N/A}"
            GPU2_TEMP="$temperature"
        fi
        GPU_COUNT=$((GPU_COUNT + 1))
    done
}

update_system_metrics() {
    local now month
    METRICS_UPDATED=0
    now=$(date +%s)
    [ "$((now - LAST_METRICS_UPDATE))" -ge 1 ] || return 0
    LAST_METRICS_UPDATE="$now"
    METRICS_UPDATED=1

    RAM_USAGE=$(get_memory_info)
    if [ -r /proc/meminfo ]; then
        RAM_PERCENT=$(awk '
            /^MemTotal:/ { total = $2 }
            /^MemAvailable:/ { available = $2 }
            END {
                if (total > 0) printf "%d", (total - available) * 100 / total
                else print "N/A"
            }
        ' /proc/meminfo)
    fi
    update_cpu_usage
    CPU_TEMP=$(get_temperature)
    update_gpu_usage

    month=$(date +%m)
    if [ "$month" != "$CURRENT_MONTH" ]; then
        CURRENT_MONTH="$month"
        [ "$COLOR_STYLE" != "auto" ] || set_background_color "$CURRENT_MONTH" "$COLOR_STYLE"
        NEEDS_RENDER=1
    fi
}

make_usage_bar() {
    local usage="$1"
    local filled i bar=""
    if [[ ! "$usage" =~ ^[0-9]+$ ]]; then
        printf '[----------] N/A'
        return
    fi
    [ "$usage" -gt 100 ] && usage=100
    filled=$(( (usage + 5) / 10 ))
    for ((i = 0; i < 10; i++)); do
        if [ "$i" -lt "$filled" ]; then
            bar+="#"
        else
            bar+="-"
        fi
    done
    printf '[%s] %d%%' "$bar" "$usage"
}

draw_system_bars() {
    local cpu_bar gpu_bar gpu2_bar ram_bar
    cpu_bar=$(make_usage_bar "$CPU_USAGE")
    gpu_bar=$(make_usage_bar "$GPU_USAGE")
    gpu2_bar=$(make_usage_bar "$GPU2_USAGE")
    ram_bar=$(make_usage_bar "$RAM_PERCENT")

    paint_at 6 4
    printf '\033[K' > /dev/tty
    printf '\033[38;2;175;216;255mCPU %s  %s C' "$cpu_bar" "$CPU_TEMP" > /dev/tty
    paint_at 7 4
    printf '\033[K' > /dev/tty
    printf '\033[38;2;175;216;255mGPU %s  %s C' "$gpu_bar" "$GPU_TEMP" > /dev/tty
    paint_at 8 4
    printf '\033[K' > /dev/tty
    if [ "$GPU_COUNT" -gt 1 ]; then
        printf '\033[38;2;175;216;255mGPU2 %s  %s C' "$gpu2_bar" "$GPU2_TEMP" > /dev/tty
    fi
    paint_at 9 4
    printf '\033[K' > /dev/tty
    printf '\033[38;2;175;216;255mRAM %s  %s' "$ram_bar" "$RAM_USAGE" > /dev/tty
}

draw_gpu_info() {
    local header_width=$((TERM_COLS - 8))
    local gpu_line gpu2_line
    gpu_line="GPU: $GPU_INFO | $GPU_DRIVER v$GPU_DRIVER_VERSION | VRAM $GPU_VRAM"
    paint_at 4 4
    printf '\033[K' > /dev/tty
    printf '\033[38;2;175;216;255m%.*s' "$header_width" "$gpu_line" > /dev/tty
    paint_at 5 4
    printf '\033[K' > /dev/tty
    if [ "$GPU_COUNT" -gt 1 ]; then
        gpu2_line="GPU2: $GPU2_INFO | $GPU2_DRIVER v$GPU2_DRIVER_VERSION | VRAM $GPU2_VRAM"
        printf '\033[38;2;175;216;255m%.*s' "$header_width" "$gpu2_line" > /dev/tty
    fi
}

cycle_setting() {
    local setting="$1" i current_index=-1
    case "$setting" in
        setting-color)
            for i in "${!COLOR_OPTIONS[@]}"; do
                [ "${COLOR_OPTIONS[$i]}" = "$COLOR_STYLE" ] && current_index="$i"
            done
            COLOR_STYLE="${COLOR_OPTIONS[$(( (current_index + 1) % ${#COLOR_OPTIONS[@]} ))]}"
            set_background_color "$CURRENT_MONTH" "$COLOR_STYLE"
            ;;
        setting-icons)
            for i in "${!ICON_OPTIONS[@]}"; do
                [ "${ICON_OPTIONS[$i]}" = "$ICON_STYLE" ] && current_index="$i"
            done
            ICON_STYLE="${ICON_OPTIONS[$(( (current_index + 1) % ${#ICON_OPTIONS[@]} ))]}"
            apply_icon_style
            ;;
        *)
            return 1
            ;;
    esac
    save_settings
    update_settings_labels
    NEEDS_RENDER=1
}

start_gyro_sensor() {
    if ! command -v python3 >/dev/null 2>&1 || [ ! -r "$GYRO_SENSOR" ]; then
        return
    fi

    coproc GYRO_SENSOR_PROCESS { python3 "$GYRO_SENSOR"; }
    GYRO_FD="${GYRO_SENSOR_PROCESS[0]}"
    GYRO_PID="$GYRO_SENSOR_PROCESS_PID"
}

stop_gyro_sensor() {
    if [ -n "$GYRO_PID" ]; then
        kill "$GYRO_PID" 2>/dev/null || true
        wait "$GYRO_PID" 2>/dev/null || true
    fi
}

init_particles() {
    local i min_x max_y
    min_x=$((TERM_COLS / 2))
    [ "$min_x" -lt 30 ] && min_x=30
    max_y=$((TERM_ROWS - 6))
    [ "$max_y" -lt 12 ] && max_y=12

    for ((i = 0; i < PARTICLE_COUNT; i++)); do
        PARTICLE_X[$i]=$((min_x + RANDOM % (TERM_COLS - min_x - 2) + 1))
        PARTICLE_Y[$i]=$((15 + RANDOM % (max_y - 14)))
        PARTICLE_VX[$i]=$((RANDOM % 3 - 1))
        PARTICLE_VY[$i]=$((RANDOM % 3 - 1))
    done
}

read_gyro_updates() {
    local line kind x y
    [ -n "$GYRO_FD" ] || return 0

    while IFS= read -r -t 0.001 -u "$GYRO_FD" line; do
        IFS='|' read -r kind x y <<< "$line"
        case "$kind" in
            STATUS)
                if [ "$x" = "active" ]; then
                    GYRO_STATUS="gyro active"
                else
                    GYRO_STATUS="automatic drift (gyro unavailable)"
                fi
                NEEDS_RENDER=1
                ;;
            MOTION)
                [ -n "$x" ] && GYRO_X="$x"
                [ -n "$y" ] && GYRO_Y="$y"
                ;;
        esac
    done
}

update_particles() {
    local i min_x max_x max_y gyro_x gyro_y
    min_x=$((TERM_COLS / 2))
    [ "$min_x" -lt 30 ] && min_x=30
    max_x=$((TERM_COLS - 2))
    max_y=$((TERM_ROWS - 6))
    [ "$max_y" -lt 12 ] && max_y=12

    [ "$GYRO_X" -gt 8 ] || [ "$GYRO_X" -lt -8 ] || GYRO_X=0
    [ "$GYRO_Y" -gt 8 ] || [ "$GYRO_Y" -lt -8 ] || GYRO_Y=0
    gyro_x=$((GYRO_X / 25))
    gyro_y=$((GYRO_Y / 25))
    GYRO_X=$((GYRO_X * 3 / 4))
    GYRO_Y=$((GYRO_Y * 3 / 4))

    if [ "$PARTICLES_DRAWN" -eq 1 ]; then
        for i in "${!PARTICLE_X[@]}"; do
            paint_at "${PARTICLE_Y[$i]}" "${PARTICLE_X[$i]}"
            printf ' ' > /dev/tty
        done
    fi

    for i in "${!PARTICLE_X[@]}"; do
        PARTICLE_VX[$i]=$((PARTICLE_VX[$i] * 3 / 4 + gyro_x))
        PARTICLE_VY[$i]=$((PARTICLE_VY[$i] * 3 / 4 + gyro_y))
        [ "${PARTICLE_VX[$i]}" -gt 2 ] && PARTICLE_VX[$i]=2
        [ "${PARTICLE_VX[$i]}" -lt -2 ] && PARTICLE_VX[$i]=-2
        [ "${PARTICLE_VY[$i]}" -gt 2 ] && PARTICLE_VY[$i]=2
        [ "${PARTICLE_VY[$i]}" -lt -2 ] && PARTICLE_VY[$i]=-2
        if [ "${PARTICLE_VX[$i]}" -eq 0 ] && [ "${PARTICLE_VY[$i]}" -eq 0 ]; then
            PARTICLE_VX[$i]=$((RANDOM % 3 - 1))
            PARTICLE_VY[$i]=$((RANDOM % 3 - 1))
        fi

        PARTICLE_X[$i]=$((PARTICLE_X[$i] + PARTICLE_VX[$i]))
        PARTICLE_Y[$i]=$((PARTICLE_Y[$i] + PARTICLE_VY[$i]))
        if [ "${PARTICLE_X[$i]}" -le "$min_x" ] || [ "${PARTICLE_X[$i]}" -ge "$max_x" ]; then
            PARTICLE_VX[$i]=$((-PARTICLE_VX[$i]))
        fi
        if [ "${PARTICLE_Y[$i]}" -le 15 ] || [ "${PARTICLE_Y[$i]}" -ge "$max_y" ]; then
            PARTICLE_VY[$i]=$((-PARTICLE_VY[$i]))
        fi

        paint_at "${PARTICLE_Y[$i]}" "${PARTICLE_X[$i]}"
        printf '\033[38;2;116;177;222m·' > /dev/tty
    done
    PARTICLES_DRAWN=1
}

category_for_label() {
    local category="${1%%|*}"
    case "$category" in
        USERS|SETTINGS|PHOTO|MUSIC|VIDEO|GAME|NETWORK|FRIENDS) printf '%s' "$category" ;;
        SYSTEM|POWER) printf 'USERS' ;;
        *) printf 'SETTINGS' ;;
    esac
}

first_item_in_category() {
    local wanted="$1"
    local i
    for i in "${!ITEM_IDS[@]}"; do
        if [ "$(category_for_label "${ITEM_LABELS[$i]}")" = "$wanted" ]; then
            printf '%s' "$i"
            return
        fi
    done
    printf '%s' -1
}

paint_at() {
    local row="$1"
    local col="$2"
    local red=$((BG_R + row / 2))
    local green=$((BG_G + row * BG_GREEN_STEP))
    local blue=$((BG_B + row * BG_BLUE_STEP))
    [ "$red" -gt 255 ] && red=255
    [ "$green" -gt 255 ] && green=255
    [ "$blue" -gt 255 ] && blue=255
    printf '\033[%d;%dH\033[48;2;%d;%d;%dm' \
        "$row" "$col" "$red" "$green" "$blue" > /dev/tty
}

update_clock() {
    local clock_value
    clock_value=$(date '+%Y/%m/%d %H:%M')
    if [ "$clock_value" != "$CLOCK_VALUE" ]; then
        CLOCK_VALUE="$clock_value"
        paint_at 1 "$((TERM_COLS - 19))"
        printf '\033[38;2;205;228;250m%s' "$CLOCK_VALUE" > /dev/tty
    fi
}

CATEGORY_INDEX=5
SELECTED_ITEM=$(first_item_in_category "${CATEGORY_NAMES[$CATEGORY_INDEX]}")

render() {
    local selected_category="${CATEGORY_NAMES[$CATEGORY_INDEX]}"
    local selected_label="Explore $selected_category"
    local start_col=$(( (TERM_COLS - ${#CATEGORY_NAMES[@]} * 5) / 2 ))
    local row=1 visible_limit scroll_start selected_position offset
    local header_width=$((TERM_COLS - 8))
    local i item_category item_label icon
    local -a category_items=()

    if [ "$SELECTED_ITEM" -ge 0 ]; then
        selected_label="${ITEM_LABELS[$SELECTED_ITEM]#*|}"
    fi

    printf '\033[?25l\033[H\033[2J\033[38;2;238;247;255m' > /dev/tty

    for ((row = 1; row <= TERM_ROWS; row++)); do
        paint_at "$row" 1
        printf '%*s' "$TERM_COLS" '' > /dev/tty
    done

    if [ "$TERM_COLS" -ge 80 ]; then
        paint_at 12 "$((TERM_COLS - 11))"
        printf '\033[38;2;57;133;190m◦' > /dev/tty
        paint_at 15 "$((TERM_COLS - 20))"
        printf '\033[38;2;47;120;180m○' > /dev/tty
        paint_at 18 "$((TERM_COLS - 8))"
        printf '\033[38;2;58;137;193m·' > /dev/tty
        paint_at 20 "$((TERM_COLS - 17))"
        printf '\033[38;2;53;128;185m◦' > /dev/tty
    fi

    paint_at 2 4
    printf '\033[1;97mSGBU\033[38;2;175;216;255m  |  OS: %.*s' \
        "$((header_width - 15))" "$OS_NAME" > /dev/tty
    paint_at 3 4
    printf '\033[38;2;175;216;255mCPU: %.*s | %s cores / %s threads' \
        "$((header_width - 36))" "$CPU_INFO" "$CPU_CORES" "$CPU_THREADS" > /dev/tty
    draw_gpu_info
    CLOCK_VALUE=""
    update_clock
    draw_system_bars

    paint_at 11 "$start_col"
    for i in "${!CATEGORY_NAMES[@]}"; do
        icon="${CATEGORY_ICONS[$i]}"
        if [ "$i" -eq "$CATEGORY_INDEX" ]; then
            printf '\033[1;97m[%s]\033[22;38;2;132;184;235m ' "$icon" > /dev/tty
        else
            printf '\033[38;2;132;184;235m %s  ' "$icon" > /dev/tty
        fi
    done

    paint_at 12 "$((start_col + CATEGORY_INDEX * 5))"
    printf '\033[1;97m%s' "$selected_category" > /dev/tty
    paint_at 13 4
    printf '\033[38;2;111;185;242m────────────────────────────────────────────────────────────' > /dev/tty

    for i in "${!ITEM_IDS[@]}"; do
        item_category=$(category_for_label "${ITEM_LABELS[$i]}")
        if [ "$item_category" = "$selected_category" ]; then
            category_items+=("$i")
        fi
    done

    selected_position=-1
    for i in "${!category_items[@]}"; do
        if [ "${category_items[$i]}" -eq "$SELECTED_ITEM" ]; then
            selected_position=$i
            break
        fi
    done

    if [ "${#category_items[@]}" -eq 0 ]; then
        paint_at 15 9
        printf '\033[38;2;183;211;239mNo items available' > /dev/tty
        selected_label="Explore $selected_category"
    else
        visible_limit=$(( (TERM_ROWS - 19) / 2 ))
        [ "$visible_limit" -gt 0 ] || visible_limit=1
        scroll_start=0
        if [ "$selected_position" -ge "$visible_limit" ]; then
            scroll_start=$((selected_position - visible_limit + 1))
        fi

        row=15
        for ((offset = scroll_start; offset < ${#category_items[@]} && offset < scroll_start + visible_limit; offset++)); do
            i="${category_items[$offset]}"
            item_label="${ITEM_LABELS[$i]#*|}"
            if [ "$i" -eq "$SELECTED_ITEM" ]; then
                paint_at "$row" 6
                printf '\033[1;97m❯  %s' "$item_label" > /dev/tty
            else
                paint_at "$row" 9
                printf '\033[38;2;183;211;239m%s' "$item_label" > /dev/tty
            fi
            ((row += 2))
        done
    fi

    paint_at "$((TERM_ROWS - 4))" 4
    printf '\033[38;2;146;198;240m%s' "$selected_label" > /dev/tty
    paint_at "$((TERM_ROWS - 3))" 4
    printf '\033[38;2;137;187;230mParticles: %s' "$GYRO_STATUS" > /dev/tty
    paint_at "$((TERM_ROWS - 2))" 4
    printf '\033[38;2;137;187;230m← → Category   ↑ ↓ Select   Enter: Open   Esc: Exit\033[39m' > /dev/tty
}

restore_terminal() {
    stop_gyro_sensor
    stty "$SAVED_STTY" < /dev/tty
    printf '\033[0m\033[?25h\033[2J\033[H' > /dev/tty
}

GPU_DRIVER=$(get_gpu_driver)
GPU_DRIVER_VERSION=$(get_gpu_driver_version)
update_system_metrics

SAVED_STTY=$(stty -g < /dev/tty)
trap restore_terminal EXIT
stty -echo -icanon min 1 time 0 < /dev/tty
GYRO_X=0
GYRO_Y=0
start_gyro_sensor
init_particles

while true; do
    if [ "$NEEDS_RENDER" -eq 1 ]; then
        render
        NEEDS_RENDER=0
        PARTICLES_DRAWN=0
    fi

    read_gyro_updates
    update_system_metrics
    if [ "$METRICS_UPDATED" -eq 1 ]; then
        draw_gpu_info
        draw_system_bars
    fi
    update_clock
    update_particles
    key=""
    if ! IFS= read -r -s -N 1 -t 0.08 key < /dev/tty; then
        continue
    fi

    case "$key" in
        $'\x1b')
            sequence=""
            IFS= read -r -s -N 2 -t 0.1 sequence < /dev/tty || true
            case "$sequence" in
                "[A") key="up" ;;
                "[B") key="down" ;;
                "[C") key="right" ;;
                "[D") key="left" ;;
                *) exit 1 ;;
            esac
            ;;
        $'\r'|$'\n')
            if [ "$SELECTED_ITEM" -ge 0 ] &&
                [ "$(category_for_label "${ITEM_LABELS[$SELECTED_ITEM]}")" = "${CATEGORY_NAMES[$CATEGORY_INDEX]}" ]; then
                selected_id="${ITEM_IDS[$SELECTED_ITEM]}"
                case "$selected_id" in
                    setting-color|setting-icons)
                        cycle_setting "$selected_id"
                        continue
                        ;;
                esac
                if [ "$MODE" = "--preview" ]; then
                    printf 'Preview selection: %s (no action launched)\n' "${ITEM_LABELS[$SELECTED_ITEM]#*|}"
                else
                    printf '%s\n' "${ITEM_IDS[$SELECTED_ITEM]}"
                fi
                exit 0
            fi
            continue
            ;;
        q|Q)
            exit 1
            ;;
    esac

    case "$key" in
        left|right)
            if [ "$key" = "left" ]; then
                CATEGORY_INDEX=$(( (CATEGORY_INDEX + ${#CATEGORY_NAMES[@]} - 1) % ${#CATEGORY_NAMES[@]} ))
            else
                CATEGORY_INDEX=$(( (CATEGORY_INDEX + 1) % ${#CATEGORY_NAMES[@]} ))
            fi
            SELECTED_ITEM=$(first_item_in_category "${CATEGORY_NAMES[$CATEGORY_INDEX]}")
            NEEDS_RENDER=1
            ;;
        up|down)
            direction=1
            [ "$key" = "up" ] && direction=-1
            for ((step = 1; step <= ${#ITEM_IDS[@]}; step++)); do
                candidate=$(( (SELECTED_ITEM + direction * step + ${#ITEM_IDS[@]} * 2) % ${#ITEM_IDS[@]} ))
                if [ "$(category_for_label "${ITEM_LABELS[$candidate]}")" = "${CATEGORY_NAMES[$CATEGORY_INDEX]}" ]; then
                    SELECTED_ITEM=$candidate
                    NEEDS_RENDER=1
                    break
                fi
            done
            ;;
    esac
done
