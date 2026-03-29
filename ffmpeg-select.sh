#!/bin/bash

# =========================
# AUDIO PROBE
# =========================
ffprobe_audio() {
    ffprobe -v error \
        -select_streams a \
        -show_entries stream=index,codec_name,channels:stream_disposition=default:stream_tags=language,title \
        -of default=noprint_wrappers=1 "$1" | \
    awk '
        BEGIN { count = 0 }

        function lang_color(lang) {
            if (lang == "ENG") return 32
            if (lang == "JPN") return 35
            if (lang == "GER") return 34
            return 33
        }

        /^index=/ {
            if (count > 0) print_line()
            idx = substr($0,7)
            codec = ch = lang = title = ""
            def = 0
            count++
        }

        /^codec_name=/ { codec = substr($0,12) }
        /^channels=/   { ch = substr($0,10) }
        /^TAG:language=/ { lang = toupper(substr($0,14)) }
        /^TAG:title=/    { title = substr($0,11) }
        /^DISPOSITION:default=/ { def = substr($0,21) }

        END { print_line() }

        function print_line() {
            if (idx == "") return

            if (lang == "") lang = "UNK"
            if (title == "") title = "No Title"

            ch_label = (ch == 2 ? "Stereo" : (ch == 6 ? "5.1" : ch "ch"))

            flags = ""
            if (def == 1) flags = "[DEFAULT]"
            if (tolower(title) ~ /commentary/) flags = flags "[COMMENT]"

            color = lang_color(lang)

            printf "\033[%sm[%d]  %-3s  %-6s  (%-6s)  %-15s %s\033[0m\n",
                   color, count, lang, ch_label, codec, flags, title
        }
    '
}

# =========================
# SUBS PROBE
# =========================
ffprobe_subs() {
    ffprobe -v error \
        -select_streams s \
        -show_entries stream=index,codec_name:stream_tags=language,title \
        -of default=noprint_wrappers=1 "$1" | \
    awk '
        BEGIN { count = 0 }

        function lang_color(lang) {
            if (lang == "ENG") return 32
            if (lang == "JPN") return 35
            if (lang == "GER") return 34
            if (lang == "FRE") return 36
            return 33
        }

        /^index=/ {
            if (count > 0) print_line()
            idx = substr($0,7)
            codec = lang = title = ""
            count++
        }

        /^codec_name=/ { codec = substr($0,12) }
        /^TAG:language=/ { lang = toupper(substr($0,14)) }
        /^TAG:title=/    { title = substr($0,11) }

        END { print_line() }

        function print_line() {
            if (idx == "") return

            if (lang == "") lang = "UNK"
            if (title == "") title = "No Title"

            codec_label = codec
            if (codec == "ass") codec_label = "ASS"
            else if (codec == "subrip") codec_label = "SRT"

            color = lang_color(lang)

            printf "\033[%sm[%d]  %-3s  (%-6s)  %s\033[0m\n",
                   color, count, lang, codec_label, title
        }
    '
}

# =========================
# MAIN SELECTOR
# =========================
ffmpeg_select() {
    input="$1"

    if [ -z "$input" ]; then
        echo "Usage: ffmpeg-select <file>"
        return 1
    fi

    if [ ! -f "$input" ]; then
        echo "Error: File not found → $input"
        return 1
    fi

    echo "Input: $input"

    echo
    read -p "Output file (default: output.mkv): " output
    output=${output:-output.mkv}

    echo
    echo "==== AUDIO TRACKS ===="
    ffprobe_audio "$input"

    audio_real=($(ffprobe -v error -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 "$input"))

    echo
    read -p "Select audio tracks (e.g. 1 2, default: 1): " audio_sel
    audio_sel=${audio_sel:-1}

    echo
    read -p "Keep existing default track? (y/n): " keep_default

    if [[ "$keep_default" == "n" ]]; then
        read -p "Set new default track number (or Enter for none): " default_track
    fi

    echo
    read -p "Mark commentary tracks (e.g. 3 or Enter to skip): " commentary_sel

    echo
    echo "==== SUBTITLE TRACKS ===="
    ffprobe_subs "$input"

    sub_real=($(ffprobe -v error -select_streams s \
        -show_entries stream=index \
        -of csv=p=0 "$input"))

    echo
    read -p "Select subtitle tracks (Enter to skip): " sub_sel

    echo
    read -p "Custom encoder settings? (y/n): " custom_enc

    if [[ "$custom_enc" == "y" ]]; then
        read -p "CRF (default 20): " crf
        read -p "Preset (default medium): " preset
        read -p "Audio bitrate (default 192k): " abitrate
    fi

    crf=${crf:-20}
    preset=${preset:-medium}
    abitrate=${abitrate:-192k}

    echo
    echo "Building command..."

    cmd="ffmpeg -i \"$input\" -map 0:v"

    # AUDIO
    idx=0
    for a in $audio_sel; do
        real=${audio_real[$((a-1))]}
        cmd="$cmd -map 0:$real"

        if [[ "$keep_default" == "n" ]]; then
            if [[ "$default_track" == "$a" ]]; then
                cmd="$cmd -disposition:a:$idx default"
            else
                cmd="$cmd -disposition:a:$idx 0"
            fi
        fi

        if [[ " $commentary_sel " == *" $a "* ]]; then
            cmd="$cmd -metadata:s:a:$idx title=\"Commentary\""
        fi

        ((idx++))
    done

    # SUBS
    sidx=0
    for s in $sub_sel; do
        real=${sub_real[$((s-1))]}
        cmd="$cmd -map 0:$real"

        ((sidx++))
    done

    # Container compatibility
    if [[ "$output" == *.mp4 || "$output" == *.mov ]]; then
        acodec="-c:a aac -b:a $abitrate"
        scodec="-c:s mov_text"
    else
        acodec="-c:a libopus -b:a $abitrate -vbr on"
        scodec="-c:s copy"
    fi

    # Final command
    cmd="$cmd \
-c:v libx265 -crf $crf -preset $preset \
$acodec \
$scodec \"$output\""

    echo
    echo "=============================="
    echo "$cmd"
    echo "=============================="
    echo

    eval "$cmd"
}

# Run
ffmpeg_select "$1"