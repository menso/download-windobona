#!/bin/bash
# Pure-macOS downloader for Windobona media pages: bash + curl + grep/sed only.
# No python, no third-party tools -- nothing here needs an install beyond
# what ships on every Mac out of the box.
set -u

CONCURRENCY=6
MAX_RETRIES=3
RETRY_DELAY=1.5

MEDIA_URL="${1:-}"
DEST="${2:-}"

if [ -z "$MEDIA_URL" ] || [ -z "$DEST" ]; then
    echo "ERROR Usage: download_windobona.sh <media_url> <destination_folder>"
    exit 1
fi

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/windobona.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "$DEST"

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

# -------------------------------------------------------- fetch & parse ----

SEC=$(printf '%s' "$MEDIA_URL" | sed -E 's#/+$##' | sed -E 's#.*/##')
SCHEME_HOST=$(printf '%s' "$MEDIA_URL" | sed -E 's#^(https?://[^/]+).*#\1#')
API_URL="${SCHEME_HOST}/api/media?sec=${SEC}"

RAW_JSON="$WORKDIR/raw.json"
if ! curl -sS -X POST -H "Content-Type: application/json" --max-time 30 -o "$RAW_JSON" "$API_URL"; then
    echo "ERROR Could not load media list"
    exit 1
fi
if [ ! -s "$RAW_JSON" ]; then
    echo "ERROR Could not load media list: empty response"
    exit 1
fi

grep -oE '\{[^{}]*\}' "$RAW_JSON" > "$WORKDIR/objects.txt"

PRE_SKIPPED=0
: > "$WORKDIR/raw_plan.tsv"
while IFS= read -r obj; do
    path=$(get_field "$obj" "videoPath")
    preview=$(get_field "$obj" "videoPreview")
    if [ -z "$path" ] || [ -z "$preview" ]; then
        PRE_SKIPPED=$((PRE_SKIPPED + 1))
        continue
    fi
    id=$(get_id_field "$obj")
    name=$(get_field "$obj" "name")
    camnum=$(cam_number_of "$path")
    printf '%s\t%s\t%s\t%s\n' "$id" "$camnum" "$name" "$path" >> "$WORKDIR/raw_plan.tsv"
done < "$WORKDIR/objects.txt"

sort -t "$(printf '\t')" -k1,1n -k2,2n "$WORKDIR/raw_plan.tsv" > "$WORKDIR/sorted_plan.tsv"

: > "$WORKDIR/plan.tsv"
prev_id=""
folder_name=""
while IFS=$'\t' read -r id camnum name path; do
    if [ "$id" != "$prev_id" ]; then
        ts=$(flight_timestamp_of "$path")
        team=$(team_name_of "$name")
        folder_name="${ts}_${team}"
        prev_id="$id"
    fi
    outname=$(truncated_filename_of "$path")
    printf '%s\t%s\t%s\n' "$folder_name" "$outname" "$path" >> "$WORKDIR/plan.tsv"
done < "$WORKDIR/sorted_plan.tsv"

TOTAL=$(wc -l < "$WORKDIR/plan.tsv" | tr -d ' ')
if [ "$TOTAL" -eq 0 ]; then
    echo "ERROR No downloadable videos were found at that URL."
    exit 1
fi

mkdir -p "$WORKDIR/status" "$WORKDIR/pct"

# -------------------------------------------------------------- workers ----

process_item() {
    local idx="$1" folder="$2" outname="$3" url="$4"
    local outpath head_info status_line expected actual attempt outcome curl_pid cur pct http_code

    mkdir -p "$DEST/$folder"
    outpath="$DEST/$folder/$outname"
    echo 0 > "$WORKDIR/pct/$idx"

    head_info=$(curl -sI -L --max-time 20 "$url" 2>/dev/null)
    status_line=$(printf '%s\n' "$head_info" | grep -E '^HTTP/' | tail -1)
    if printf '%s' "$status_line" | grep -qE '^HTTP/[0-9.]+ 404'; then
        echo "skipped" > "$WORKDIR/status/$idx"
        rm -f "$WORKDIR/pct/$idx"
        return
    fi
    expected=$(printf '%s\n' "$head_info" | tr -d '\r' | grep -i '^content-length:' | tail -1 | awk '{print $2}')
    [ -z "$expected" ] && expected=0

    if [ "$expected" != "0" ] && [ -f "$outpath" ]; then
        actual=$(stat -f%z "$outpath" 2>/dev/null || echo 0)
        if [ "$actual" = "$expected" ]; then
            # already downloaded correctly in an earlier run
            echo "success" > "$WORKDIR/status/$idx"
            rm -f "$WORKDIR/pct/$idx"
            return
        fi
    fi
    rm -f "$outpath"

    attempt=1
    outcome="failed"
    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        rm -f "$outpath"
        curl -sS -L --max-time 300 -o "$outpath" -w "%{http_code}" "$url" > "$WORKDIR/http_$idx.txt" 2>/dev/null &
        curl_pid=$!

        while kill -0 "$curl_pid" 2>/dev/null; do
            if [ "$expected" != "0" ] && [ -f "$outpath" ]; then
                cur=$(stat -f%z "$outpath" 2>/dev/null || echo 0)
                pct=$(( cur * 100 / expected ))
                [ "$pct" -gt 100 ] && pct=100
                echo "$pct" > "$WORKDIR/pct/$idx"
            fi
            sleep 0.3
        done
        wait "$curl_pid"
        http_code=$(cat "$WORKDIR/http_$idx.txt" 2>/dev/null)
        rm -f "$WORKDIR/http_$idx.txt"

        if [ "$http_code" = "404" ]; then
            outcome="skipped"
            rm -f "$outpath"
            break
        elif [[ "$http_code" =~ ^2 ]]; then
            outcome="success"
            echo 100 > "$WORKDIR/pct/$idx"
            break
        else
            rm -f "$outpath"
            attempt=$((attempt + 1))
            [ "$attempt" -le "$MAX_RETRIES" ] && sleep "$RETRY_DELAY"
        fi
    done

    echo "$outcome" > "$WORKDIR/status/$idx"
    rm -f "$WORKDIR/pct/$idx"
}

report_progress() {
    local done_count active_count pct_sum avgpct f v
    while true; do
        done_count=0
        for f in "$WORKDIR"/status/*; do
            [ -e "$f" ] || continue
            done_count=$((done_count + 1))
        done
        active_count=0
        pct_sum=0
        for f in "$WORKDIR"/pct/*; do
            [ -e "$f" ] || continue
            active_count=$((active_count + 1))
            v=$(cat "$f" 2>/dev/null)
            [ -z "$v" ] && v=0
            pct_sum=$((pct_sum + v))
        done
        avgpct=0
        [ "$active_count" -gt 0 ] && avgpct=$((pct_sum / active_count))
        echo "STATE total=$TOTAL done=$done_count active=$active_count avgpct=$avgpct"
        [ "$done_count" -ge "$TOTAL" ] && break
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

idx=0
job_pids=()
while IFS=$'\t' read -r folder outname url; do
    idx=$((idx + 1))
    read -u 3
    (
        process_item "$idx" "$folder" "$outname" "$url"
        echo >&3
    ) &
    job_pids+=($!)
done < "$WORKDIR/plan.tsv"

# wait only for the download jobs here -- a blanket "wait" would also reap
# the still-running progress reporter (it is a background job of this same
# shell too), which then makes the explicit wait on it below fail
for pid in "${job_pids[@]}"; do
    wait "$pid" 2>/dev/null
done
exec 3>&-

wait "$REPORTER_PID" 2>/dev/null

# -------------------------------------------------------------- summary ----

succeeded=0
no_file_skipped=0
failed_names=()
for f in "$WORKDIR"/status/*; do
    [ -e "$f" ] || continue
    idx=$(basename "$f")
    v=$(cat "$f")
    case "$v" in
        success) succeeded=$((succeeded + 1)) ;;
        skipped) no_file_skipped=$((no_file_skipped + 1)) ;;
        *)
            name=$(sed -n "${idx}p" "$WORKDIR/plan.tsv" | awk -F'\t' '{print $2}')
            failed_names+=("$name")
            ;;
    esac
done

real_total=$((TOTAL - no_file_skipped))
total_skipped=$((PRE_SKIPPED + no_file_skipped))
if [ "${#failed_names[@]}" -eq 0 ]; then
    failed_field="none"
else
    failed_field=$(IFS=,; echo "${failed_names[*]}")
fi

echo "FINAL done=$succeeded total=$real_total skipped=$total_skipped failed=$failed_field dest=$DEST"
