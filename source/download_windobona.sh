#!/bin/bash
# Pure-macOS downloader for Windobona media pages: bash + curl + grep/sed only.
# No python, no third-party tools -- nothing here needs an install beyond
# what ships on every Mac out of the box.
#
# Usage: download_windobona.sh <destination_folder> <media_url> [<media_url> ...]
#
# One shared pool of CONCURRENCY downloads across *all* queued orders --
# testing showed Windobona throttles total concurrent connections from one
# machine, not per order, so running N orders at 6 each just queued behind
# each other instead of adding real throughput.
set -u

CONCURRENCY=6
MAX_RETRIES=3
RETRY_DELAY=1.5

DEST="${1:-}"
shift || true
URLS=("$@")

if [ -z "$DEST" ] || [ "${#URLS[@]}" -eq 0 ]; then
    echo "ERROR Usage: download_windobona.sh <destination_folder> <media_url> [<media_url> ...]"
    exit 1
fi

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/windobona.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
# a Stop click sends SIGTERM to this script's PID -- kill 0 takes down every
# curl/subshell/reporter child along with it instead of leaving them orphaned
trap 'kill 0 2>/dev/null; exit 1' TERM INT

mkdir -p "$DEST" "$WORKDIR/status" "$WORKDIR/pct" "$WORKDIR/pctname"
echo "WORKDIR $WORKDIR"

# ---------------------------------------------------------------- helpers --

get_field() {
    # $1 = json object string, $2 = string key -> prints its value
    # (tolerant of optional whitespace around ":" in case the API's JSON formatting ever changes)
    printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/^\"$2\"[[:space:]]*:[[:space:]]*\"(.*)\"\$/\\1/" | head -1
}

get_id_field() {
    printf '%s' "$1" | grep -oE '"id"[[:space:]]*:[[:space:]]*[0-9]+' | sed -E 's/^"id"[[:space:]]*:[[:space:]]*([0-9]+)$/\1/' | head -1
}

cam_number_of() {
    local n
    n=$(printf '%s' "$1" | sed -E 's/.*_cam([0-9]+)_.*/\1/')
    if [[ "$n" =~ ^[0-9]+$ ]]; then printf '%s' "$n"; else printf '999'; fi
}

flight_timestamp_of() {
    local fname parts hh mm ss
    fname=$(basename "$1")
    IFS='_' read -r -a parts <<< "$fname"
    hh="${parts[1]:-00}"; mm="${parts[2]:-00}"; ss="${parts[3]:-00}"
    printf '%s%s%s' "$hh" "$mm" "$ss"
}

flight_date_of() {
    local fname parts
    fname=$(basename "$1")
    IFS='_' read -r -a parts <<< "$fname"
    printf '%s' "${parts[0]:-unknown-date}"
}

truncated_filename_of() {
    local fname ext base_no_ext truncated
    fname=$(basename "$1")
    ext=".${fname##*.}"
    base_no_ext="${fname%.*}"
    truncated="${base_no_ext%_*}"
    printf '%s%s' "$truncated" "$ext"
}

team_name_of() {
    printf '%s' "$1" | tr -d ' '
}

# --------------------------------------------------- fetch & parse orders --
# Each order gets its own folder-naming pass (unchanged per-flight grouping
# logic), then its rows are tagged with the order number and appended to one
# combined plan.tsv that the single shared worker pool below reads from.

GLOBAL_PLAN="$WORKDIR/plan.tsv"
: > "$GLOBAL_PLAN"

declare -a ORDER_TOTAL
declare -a ORDER_PRE_SKIPPED

order_idx=0
for media_url in "${URLS[@]}"; do
    order_idx=$((order_idx + 1))
    ORDER_TOTAL[$order_idx]=0
    ORDER_PRE_SKIPPED[$order_idx]=0

    SEC=$(printf '%s' "$media_url" | sed -E 's#/+$##' | sed -E 's#.*/##')
    SCHEME_HOST=$(printf '%s' "$media_url" | sed -E 's#^(https?://[^/]+).*#\1#')
    API_URL="${SCHEME_HOST}/api/media?sec=${SEC}"

    RAW_JSON="$WORKDIR/raw_${order_idx}.json"
    if ! curl -sS -X POST -H "Content-Type: application/json" --max-time 30 -o "$RAW_JSON" "$API_URL"; then
        echo "ERROR order=$order_idx Could not load media list"
        continue
    fi
    if [ ! -s "$RAW_JSON" ]; then
        echo "ERROR order=$order_idx Could not load media list: empty response"
        continue
    fi

    grep -oE '\{[^{}]*\}' "$RAW_JSON" > "$WORKDIR/objects_${order_idx}.txt"

    pre_skipped=0
    raw_plan="$WORKDIR/raw_plan_${order_idx}.tsv"
    : > "$raw_plan"
    while IFS= read -r obj; do
        path=$(get_field "$obj" "videoPath")
        preview=$(get_field "$obj" "videoPreview")
        if [ -z "$path" ] || [ -z "$preview" ]; then
            pre_skipped=$((pre_skipped + 1))
            continue
        fi
        id=$(get_id_field "$obj")
        name=$(get_field "$obj" "name")
        camnum=$(cam_number_of "$path")
        printf '%s\t%s\t%s\t%s\n' "$id" "$camnum" "$name" "$path" >> "$raw_plan"
    done < "$WORKDIR/objects_${order_idx}.txt"
    ORDER_PRE_SKIPPED[$order_idx]=$pre_skipped

    sorted_plan="$WORKDIR/sorted_plan_${order_idx}.tsv"
    sort -t "$(printf '\t')" -k1,1n -k2,2n "$raw_plan" > "$sorted_plan"

    this_total=0
    prev_id=""
    folder_name=""
    while IFS=$'\t' read -r id camnum name path; do
        if [ "$id" != "$prev_id" ]; then
            ts=$(flight_timestamp_of "$path")
            dt=$(flight_date_of "$path")
            team=$(team_name_of "$name")
            folder_name="${dt}/${ts}_${team}"
            prev_id="$id"
        fi
        outname=$(truncated_filename_of "$path")
        printf '%s\t%s\t%s\t%s\n' "$order_idx" "$folder_name" "$outname" "$path" >> "$GLOBAL_PLAN"
        this_total=$((this_total + 1))
    done < "$sorted_plan"
    ORDER_TOTAL[$order_idx]=$this_total

    if [ "$this_total" -eq 0 ]; then
        echo "ERROR order=$order_idx No downloadable videos were found at that URL."
    fi
done

GRAND_TOTAL=$(wc -l < "$GLOBAL_PLAN" | tr -d ' ')
if [ "$GRAND_TOTAL" -eq 0 ]; then
    exit 0
fi

# -------------------------------------------------------------- workers ----

process_item() {
    local global_idx="$1" order="$2" folder="$3" outname="$4" url="$5"
    local key outpath head_info status_line expected actual attempt outcome curl_pid cur pct http_code

    key="${order}-${global_idx}"
    mkdir -p "$DEST/$folder"
    outpath="$DEST/$folder/$outname"
    echo 0 > "$WORKDIR/pct/$key"
    # the full path is kept (not removed on completion, unlike pct/) so the
    # UI can look up "what file is this" for a finished item too, to rotate
    # it immediately rather than waiting for the whole batch
    echo "$outpath" > "$WORKDIR/pctname/$key"

    head_info=$(curl -sI -L --max-time 20 "$url" 2>/dev/null)
    status_line=$(printf '%s\n' "$head_info" | grep -E '^HTTP/' | tail -1)
    if printf '%s' "$status_line" | grep -qE '^HTTP/[0-9.]+ 404'; then
        echo "skipped" > "$WORKDIR/status/$key"
        rm -f "$WORKDIR/pct/$key"
        return
    fi
    expected=$(printf '%s\n' "$head_info" | tr -d '\r' | grep -i '^content-length:' | tail -1 | awk '{print $2}')
    [ -z "$expected" ] && expected=0

    # rotating rewrites a file into a new container, so its size no longer
    # matches the server's un-rotated Content-Length and the plain size
    # check below would otherwise re-download it every time; the marker
    # lives in a shared per-date folder, not next to the video itself, so
    # it doesn't clutter the user's per-flight folders
    rotated_marker="$DEST/$(dirname "$folder")/z_non-video_data/$outname.rotated"
    if [ -f "$rotated_marker" ]; then
        echo "success" > "$WORKDIR/status/$key"
        rm -f "$WORKDIR/pct/$key"
        return
    fi
    if [ "$expected" != "0" ] && [ -f "$outpath" ]; then
        actual=$(stat -f%z "$outpath" 2>/dev/null || echo 0)
        if [ "$actual" = "$expected" ]; then
            # already downloaded correctly in an earlier run
            echo "success" > "$WORKDIR/status/$key"
            rm -f "$WORKDIR/pct/$key"
            return
        fi
    fi
    rm -f "$outpath"

    attempt=1
    outcome="failed"
    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        rm -f "$outpath"
        curl -sS -L --max-time 300 -o "$outpath" -w "%{http_code}" "$url" > "$WORKDIR/http_$key.txt" 2>/dev/null &
        curl_pid=$!

        while kill -0 "$curl_pid" 2>/dev/null; do
            if [ "$expected" != "0" ] && [ -f "$outpath" ]; then
                cur=$(stat -f%z "$outpath" 2>/dev/null || echo 0)
                pct=$(( cur * 100 / expected ))
                [ "$pct" -gt 100 ] && pct=100
                echo "$pct" > "$WORKDIR/pct/$key"
            fi
            sleep 0.3
        done
        wait "$curl_pid"
        http_code=$(cat "$WORKDIR/http_$key.txt" 2>/dev/null)
        rm -f "$WORKDIR/http_$key.txt"

        if [ "$http_code" = "404" ]; then
            outcome="skipped"
            rm -f "$outpath"
            break
        elif [[ "$http_code" =~ ^2 ]]; then
            outcome="success"
            echo 100 > "$WORKDIR/pct/$key"
            break
        else
            rm -f "$outpath"
            attempt=$((attempt + 1))
            [ "$attempt" -le "$MAX_RETRIES" ] && sleep "$RETRY_DELAY"
        fi
    done

    echo "$outcome" > "$WORKDIR/status/$key"
    rm -f "$WORKDIR/pct/$key"
}

report_progress() {
    local order total done_count succeeded_count active_count pct_sum avgpct f v grand_done

    while true; do
        grand_done=0
        for order in "${!ORDER_TOTAL[@]}"; do
            total="${ORDER_TOTAL[$order]}"

            done_count=0
            succeeded_count=0
            for f in "$WORKDIR"/status/"${order}-"*; do
                [ -e "$f" ] || continue
                done_count=$((done_count + 1))
                [ "$(cat "$f" 2>/dev/null)" = "success" ] && succeeded_count=$((succeeded_count + 1))
            done

            active_count=0
            pct_sum=0
            for f in "$WORKDIR"/pct/"${order}-"*; do
                [ -e "$f" ] || continue
                active_count=$((active_count + 1))
                v=$(cat "$f" 2>/dev/null)
                [ -z "$v" ] && v=0
                pct_sum=$((pct_sum + v))
            done
            avgpct=0
            [ "$active_count" -gt 0 ] && avgpct=$((pct_sum / active_count))

            # "done" (total processed, including skips) drives the progress
            # bar fill so it reliably reaches 100%; "succeeded" is the count
            # the UI shows, so a skipped/no-video link doesn't look like a
            # finished download before anything has actually downloaded
            echo "STATE order=$order total=$total done=$done_count succeeded=$succeeded_count active=$active_count avgpct=$avgpct"
            grand_done=$((grand_done + done_count))
        done

        [ "$grand_done" -ge "$GRAND_TOTAL" ] && break
        sleep 0.4
    done
}

report_progress &
REPORTER_PID=$!

PIPE="$WORKDIR/pool.fifo"
mkfifo "$PIPE"
exec 3<>"$PIPE"
rm -f "$PIPE"
for ((i = 0; i < CONCURRENCY; i++)); do echo >&3; done

global_idx=0
job_pids=()
while IFS=$'\t' read -r order folder outname url; do
    global_idx=$((global_idx + 1))
    read -u 3
    (
        process_item "$global_idx" "$order" "$folder" "$outname" "$url"
        echo >&3
    ) &
    job_pids+=($!)
done < "$GLOBAL_PLAN"

# wait only for the download jobs here -- a blanket "wait" would also reap
# the still-running progress reporter (it is a background job of this same
# shell too), which then makes the explicit wait on it below fail
for pid in "${job_pids[@]}"; do
    wait "$pid" 2>/dev/null
done
exec 3>&-

wait "$REPORTER_PID" 2>/dev/null

# -------------------------------------------------------------- summary ----

for order in "${!ORDER_TOTAL[@]}"; do
    total="${ORDER_TOTAL[$order]}"
    succeeded=0
    no_file_skipped=0
    failed_names=()

    for f in "$WORKDIR"/status/"${order}-"*; do
        [ -e "$f" ] || continue
        key=$(basename "$f")
        v=$(cat "$f")
        case "$v" in
            success) succeeded=$((succeeded + 1)) ;;
            skipped) no_file_skipped=$((no_file_skipped + 1)) ;;
            *)
                global_idx="${key#*-}"
                name=$(sed -n "${global_idx}p" "$GLOBAL_PLAN" | awk -F'\t' '{print $3}')
                failed_names+=("$name")
                ;;
        esac
    done

    real_total=$((total - no_file_skipped))
    total_skipped=$((ORDER_PRE_SKIPPED[$order] + no_file_skipped))
    if [ "${#failed_names[@]}" -eq 0 ]; then
        failed_field="none"
    else
        failed_field=$(IFS=,; echo "${failed_names[*]}")
    fi

    echo "FINAL order=$order done=$succeeded total=$real_total skipped=$total_skipped failed=$failed_field dest=$DEST"
done
