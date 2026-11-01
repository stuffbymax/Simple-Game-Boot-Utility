#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---preview}"
if [ "$MODE" = "--preview" ]; then
    ITEM_IDS=(retroarch steam desktop bluetooth terminal diagnostics reboot shutdown exit)
    ITEM_LABELS=(
        "GAME|RetroArch"
        "GAME|Steam (GamepadUI)"
        "SETTINGS|Desktop Session"
        "NETWORK|Bluetooth Manager"
        "SETTINGS|Terminal"
        "SETTINGS|Run Diagnostics"
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
CATEGORY_ICONS=("☺" "⚙" "▧" "♫" "▣" "◆" "◎" "☻")
CATEGORY_INDEX=0
SELECTED_ITEM=-1
TERM_SIZE=$(stty size < /dev/tty)
read -r TERM_ROWS TERM_COLS <<< "$TERM_SIZE"
TERM_ROWS="${TERM_ROWS:-24}"
TERM_COLS="${TERM_COLS:-80}"
(( TERM_ROWS < 18 )) && TERM_ROWS=18
(( TERM_COLS < 60 )) && TERM_COLS=60

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
    local gradient_green=$((27 + row * 2))
    local gradient_blue=$((74 + row * 3))
    printf '\033[%d;%dH\033[48;2;5;%d;%dm' \
        "$row" "$col" "$gradient_green" "$gradient_blue" > /dev/tty
}

CATEGORY_INDEX=5
SELECTED_ITEM=$(first_item_in_category "${CATEGORY_NAMES[$CATEGORY_INDEX]}")

render() {
    local selected_category="${CATEGORY_NAMES[$CATEGORY_INDEX]}"
    local selected_label="Explore $selected_category"
    local start_col=$(( (TERM_COLS - ${#CATEGORY_NAMES[@]} * 5) / 2 ))
    local row=1 visible_limit scroll_start selected_position offset gradient_green gradient_blue
    local i item_category item_label icon
    local -a category_items=()

    if [ "$SELECTED_ITEM" -ge 0 ]; then
        selected_label="${ITEM_LABELS[$SELECTED_ITEM]#*|}"
    fi

    printf '\033[?25l\033[H\033[2J\033[38;2;238;247;255m' > /dev/tty

    for ((row = 1; row <= TERM_ROWS; row++)); do
        gradient_green=$((27 + row * 2))
        gradient_blue=$((74 + row * 3))
        printf '\033[%d;1H\033[48;2;5;%d;%dm%*s' \
            "$row" "$gradient_green" "$gradient_blue" "$TERM_COLS" '' > /dev/tty
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
    printf '\033[1;97mPLAYSTATION 3\033[38;2;175;216;255m  |  GAME OS' > /dev/tty
    paint_at 2 "$((TERM_COLS - 10))"
    printf '\033[38;2;175;216;255mSGBU' > /dev/tty

    paint_at 5 "$start_col"
    for i in "${!CATEGORY_NAMES[@]}"; do
        icon="${CATEGORY_ICONS[$i]}"
        if [ "$i" -eq "$CATEGORY_INDEX" ]; then
            printf '\033[1;97m[%s]\033[22;38;2;132;184;235m ' "$icon" > /dev/tty
        else
            printf '\033[38;2;132;184;235m %s  ' "$icon" > /dev/tty
        fi
    done

    paint_at 7 "$((start_col + CATEGORY_INDEX * 5))"
    printf '\033[1;97m%s' "$selected_category" > /dev/tty
    paint_at 8 4
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
        paint_at 11 9
        printf '\033[38;2;183;211;239mNo items available' > /dev/tty
        selected_label="Explore $selected_category"
    else
        visible_limit=$(( (TERM_ROWS - 13) / 2 ))
        [ "$visible_limit" -gt 0 ] || visible_limit=1
        scroll_start=0
        if [ "$selected_position" -ge "$visible_limit" ]; then
            scroll_start=$((selected_position - visible_limit + 1))
        fi

        row=10
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
    paint_at "$((TERM_ROWS - 2))" 4
    printf '\033[38;2;137;187;230m← → Category   ↑ ↓ Select   Enter: Open   Esc: Exit\033[39m' > /dev/tty
}

restore_terminal() {
    stty "$SAVED_STTY" < /dev/tty
    printf '\033[0m\033[?25h\033[2J\033[H' > /dev/tty
}

SAVED_STTY=$(stty -g < /dev/tty)
trap restore_terminal EXIT
stty -echo -icanon min 1 time 0 < /dev/tty

while true; do
    render
    key=""
    if ! IFS= read -r -s -N 1 key < /dev/tty; then
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
            ;;
        up|down)
            direction=1
            [ "$key" = "up" ] && direction=-1
            for ((step = 1; step <= ${#ITEM_IDS[@]}; step++)); do
                candidate=$(( (SELECTED_ITEM + direction * step + ${#ITEM_IDS[@]} * 2) % ${#ITEM_IDS[@]} ))
                if [ "$(category_for_label "${ITEM_LABELS[$candidate]}")" = "${CATEGORY_NAMES[$CATEGORY_INDEX]}" ]; then
                    SELECTED_ITEM=$candidate
                    break
                fi
            done
            ;;
    esac
done
