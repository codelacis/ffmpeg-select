#!/bin/sh

##How to use##
# Mac:
#   chmod +x ffmpeg-select.sh
#   ./ffmpeg-select.sh input.mkv
# iPad (a-Shell):
#   sh ffmpeg-select.sh input.mkv

# =========================
# AUDIO PROBE
# =========================
ffprobe_audio() {
    ffprobe -v error \
        -select_streams a \
        -show_entries stream=index,codec_name,channels:stream_disposition=default:stream_tags=language,title \
        -of default=noprint_wrappers=1 "$1" | awk '
        BEGIN { count = 0 }

        function get_color(lang) {
            if (lang == "ENG") return 32
            if (lang == "JPN") return 35
            if (lang == "GER") return 34
            return 33
        }

        /^index=/ {
            if (count>0) print_line()
            idx=substr($0,7)
            codec=ch=lang=title=""
            def=0
            count++
        }

        /^codec_name=/ { codec=substr($0,12) }
        /^channels=/ { ch=substr($0,10) }
        /^TAG:language=/ { lang=toupper(substr($0,14)) }
        /^TAG:title=/ { title=substr($0,11) }
        /^DISPOSITION:default=/ { def=substr($0,21) }

        END { print_line() }

        function print_line() {
            if (idx=="") return
            if (lang=="") lang="UNK"
            if (title=="") title="No Title"

            ch_label=(ch==2?"Stereo":(ch==6?"5.1":ch "ch"))

            flags=""
            if (def==1) flags="[DEFAULT]"
            if (tolower(title) ~ /commentary/) flags=flags"[COMMENT]"

            color=get_color(lang)

            printf "\033[%sm[%d] %-3s %-6s (%-6s) %-12s %s\033[0m\n",
                   color, count, lang, ch_label, codec, flags, title
        }'
}

# =========================
# SUBS PROBE
# =========================
ffprobe_subs() {
    ffprobe -v error \
        -select_streams s \
        -show_entries stream=index,codec_name:stream_tags=language,title \
        -of default=noprint_wrappers=1 "$1" | awk '
        BEGIN { count = 0 }

        function get_color(lang) {
            if (lang == "ENG") return 32
            if (lang == "JPN") return 35
            if (lang == "GER") return 34
            return 33
        }

        /^index=/ {
            if (count>0) print_line()
            idx=substr($0,7)
            codec=lang=title=""
            count++
        }

        /^codec_name=/ { codec=substr($0,12) }
        /^TAG:language=/ { lang=toupper(substr($0,14)) }
        /^TAG:title=/ { title=substr($0,11) }

        END { print_line() }

        function print_line() {
            if (idx=="") return
            if (lang=="") lang="UNK"
            if (title=="") title="No Title"

            color=get_color(lang)

            printf "\033[%sm[%d] %-3s (%-6s) %s\033[0m\n",
                   color, count, lang, codec, title
        }'
}

# =========================
# COLOR HELPER
# =========================
get_color_shell() {
    case "$1" in
        ENG) echo 32 ;;
        JPN) echo 35 ;;
        GER) echo 34 ;;
        *) echo 33 ;;
    esac
}

# =========================
# MAIN
# =========================
ffmpeg_select() {
    input="$1"

    [ -z "$input" ] && echo "Usage: ffmpeg-select <file>" && return 1
    [ ! -f "$input" ] && echo "Error: File not found → $input" && return 1

    echo "Input: $input"
    echo

    printf "Choose output format (mkv/mp4/mov) [mkv]: "
    read format
    format=$(echo "$format" | xargs)
    [ -z "$format" ] && format="mkv"

    printf "Output filename [output.%s]: " "$format"
    read output
    output=$(echo "$output" | xargs)
    [ -z "$output" ] && output="output.$format"

    echo
    printf "Rename video track name? (y/n) [keep]: "
    read rename_video

    if [ "$rename_video" = "y" ]; then
        current_video=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream_tags=title \
            -of default=noprint_wrappers=1:nokey=1 "$input")

        [ -z "$current_video" ] && current_video="No Title"

        printf "Current: %s\nNew name [keep]: " "$current_video"
        read video_name
    fi

    echo
    echo "==== AUDIO TRACKS ===="
    ffprobe_audio "$input"

    printf "\nSelect audio tracks (e.g. 1 2 3) [all]: "
    read audio_sel
    audio_sel=$(echo "$audio_sel" | xargs)

    if [ -z "$audio_sel" ]; then
        total=$(ffprobe -v error -select_streams a \
            -show_entries stream=index -of csv=p=0 "$input" | wc -l)
        i=1
        while [ "$i" -le "$total" ]; do
            audio_sel="$audio_sel $i"
            i=$((i+1))
        done
    fi

    echo
    printf "Keep existing default track flag? (y/n) [y]: "
    read keep_default

    echo
    printf "Keep existing commentary track flag? (y/n) [y]: "
    read keep_commentary

    echo
    printf "Rename audio track names? (y/n) [n]: "
    read rename_audio

    if [ "$rename_audio" = "y" ]; then
        echo
        audio_names=""

        for a in $audio_sel; do
            info=$(ffprobe -v error -select_streams a \
                -show_entries stream=codec_name,channels:stream_tags=language,title \
                -of default=noprint_wrappers=1 "$input" | \
                awk -v n="$a" '
                BEGIN{c=0}
                /^codec_name=/ {codec=substr($0,12)}
                /^channels=/ {ch=substr($0,10)}
                /^TAG:language=/ {lang=toupper(substr($0,14))}
                /^TAG:title=/ {
                    title=substr($0,11); c++
                    if (c==n) {
                        ch_label=(ch==2?"Stereo":(ch==6?"5.1":ch "ch"))
                        printf "%s %s (%s)|%s", lang, ch_label, codec, title
                        exit
                    }
                }')

            label=$(echo "$info" | awk -F'|' '{print $1}')
            current=$(echo "$info" | awk -F'|' '{print $2}')
            lang=$(echo "$label" | awk '{print $1}')
            color=$(get_color_shell "$lang")

            printf "\033[%sm[%s] %s\033[0m\nCurrent: %s\nNew name [keep]: " \
                "$color" "$a" "$label" "$current"
            read name

            [ -n "$name" ] && audio_names="$audio_names;$a=$name"
        done
    fi

    echo
    echo "==== SUBTITLE TRACKS ===="
    ffprobe_subs "$input"

    printf "\nSelect subtitle tracks (e.g. 1 2 3) [none]: "
    read sub_sel

    echo
    printf "Rename subtitle track names? (y/n) [n]: "
    read rename_subs

    if [ "$rename_subs" = "y" ]; then
        echo
        sub_names=""

        for s in $sub_sel; do
            info=$(ffprobe -v error -select_streams s \
                -show_entries stream=codec_name:stream_tags=language,title \
                -of default=noprint_wrappers=1 "$input" | \
                awk -v n="$s" '
                BEGIN{c=0}
                /^codec_name=/ {codec=substr($0,12)}
                /^TAG:language=/ {lang=toupper(substr($0,14))}
                /^TAG:title=/ {
                    title=substr($0,11); c++
                    if (c==n) {
                        printf "%s (%s)|%s", lang, codec, title
                        exit
                    }
                }')

            label=$(echo "$info" | awk -F'|' '{print $1}')
            current=$(echo "$info" | awk -F'|' '{print $2}')
            lang=$(echo "$label" | awk '{print $1}')
            color=$(get_color_shell "$lang")

            printf "\033[%sm[%s] %s\033[0m\nCurrent: %s\nNew name [keep]: " \
                "$color" "$s" "$label" "$current"
            read name

            [ -n "$name" ] && sub_names="$sub_names;$s=$name"
        done
    fi

    echo
    printf "Custom encoder settings? (y/n) [n]: "
    read custom_enc

    if [ "$custom_enc" = "y" ]; then
        printf "CRF (default 20): "
        read crf
        printf "Preset (default medium): "
        read preset
        printf "Audio bitrate (default 192k): "
        read abitrate
    fi

    [ -z "$crf" ] && crf=20
    [ -z "$preset" ] && preset=medium
    [ -z "$abitrate" ] && abitrate=192k

    echo
    echo "Building command..."

    cmd="ffmpeg -i \"$input\" -map 0:v"

    [ -n "$video_name" ] && cmd="$cmd -metadata:s:v:0 title=\"$video_name\""

    # Detect encoder
    if ffmpeg -encoders 2>/dev/null | grep -q libx265; then
        vcodec="libx265"
    else
        vcodec="libx264"
    fi

    idx=0
    for a in $audio_sel; do
        real=$(ffprobe -v error -select_streams a \
            -show_entries stream=index -of csv=p=0 "$input" | sed -n "${a}p")
        cmd="$cmd -map 0:$real"

        name=$(echo "$audio_names" | tr ';' '\n' | awk -F= -v n="$a" '$1==n {sub($1"=",""); print}')
        [ -n "$name" ] && cmd="$cmd -metadata:s:a:$idx title=\"$name\""

        idx=$((idx+1))
    done

    sidx=0
    for s in $sub_sel; do
        real=$(ffprobe -v error -select_streams s \
            -show_entries stream=index -of csv=p=0 "$input" | sed -n "${s}p")
        cmd="$cmd -map 0:$real"

        name=$(echo "$sub_names" | tr ';' '\n' | awk -F= -v n="$s" '$1==n {sub($1"=",""); print}')
        [ -n "$name" ] && cmd="$cmd -metadata:s:s:$sidx title=\"$name\""

        sidx=$((sidx+1))
    done

    cmd="$cmd -c:v $vcodec -crf $crf -preset $preset $acodec $scodec \"$output\""

    echo
    echo "$cmd"
    echo

    eval "$cmd"
}

ffmpeg_select "$1"