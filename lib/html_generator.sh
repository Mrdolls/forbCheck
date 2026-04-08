#!/bin/bash

# ==============================================================================
#  FORBCHECK HTML GENERATOR MODULE
# ==============================================================================

generate_html_report() {
    local html_dir="$INSTALL_DIR/reports_html"
    mkdir -p "$html_dir"

    local timestamp=$(date +"%Y-%m-%d_%Hh%M")
    local html_file="$html_dir/forb_report_${timestamp}.html"

    local count_val=0
    if [ "$IS_SOURCE_SCAN" = true ]; then
        [ -n "$JSON_RAW_DATA" ] && count_val=$(echo "$JSON_RAW_DATA" | grep -c "MATCH")
    else
        [ -n "$forbidden_list" ] && count_val=$(echo "$forbidden_list" | wc -w | tr -d ' ')
    fi

    local status="PERFECT"
    local status_color="#10b981"
    if [ "$count_val" -gt 0 ]; then
        status="FAILURE"
        status_color="#ef4444"
    fi
    local mode_name="Whitelist"
    [ "$BLACKLIST_MODE" = true ] && mode_name="Blacklist"

    # Head
    cat <<EOF > "$html_file"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ForbCheck Report - $TARGET</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: rgba(30, 41, 59, 0.7);
            --text-main: #f8fafc;
            --text-sub: #94a3b8;
            --accent: #38bdf8;
            --success: #10b981;
            --danger: #ef4444;
        }
        body {
            margin: 0; padding: 2rem;
            font-family: 'Segoe UI', system-ui, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
        }
        .container { max-width: 1000px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 3rem; animation: fadeIn 0.8s ease-out; }
        .header h1 {
            font-size: 2.5rem;
            background: linear-gradient(to right, #38bdf8, #818cf8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
        }
        .summary-card {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 16px;
            padding: 2rem;
            display: flex;
            justify-content: space-around;
            margin-bottom: 3rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        .stat { text-align: center; }
        .stat-value { font-size: 2rem; font-weight: bold; margin-bottom: 0.5rem; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 1.5rem;
        }
        .issue-card {
            background: var(--card-bg);
            border-left: 4px solid var(--danger);
            border-radius: 12px;
            padding: 1.5rem;
            transition: transform 0.2s, box-shadow 0.2s;
            animation: slideUp 0.5s ease-out backwards;
        }
        .issue-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.4);
        }
        .func-name { font-size: 1.25rem; font-weight: bold; color: var(--danger); margin: 0 0 1rem 0; }
        .location { font-family: monospace; color: var(--accent); font-size: 0.9rem; }
        .perfect-msg {
            text-align: center;
            font-size: 2rem;
            color: var(--success);
            padding: 4rem;
            background: var(--card-bg);
            border-radius: 16px;
        }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes slideUp { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>ForbCheck Full Report</h1>
            <p>Target: <b>${TARGET:-$PWD}</b> | Version: $VERSION | Mode: $mode_name | Date: $timestamp</p>
        </div>
        <div class="summary-card">
            <div class="stat">
                <div class="stat-value" style="color: $status_color;">$status</div>
                <div style="color: var(--text-sub);">Final Result</div>
            </div>
            <div class="stat">
                <div class="stat-value">$count_val</div>
                <div style="color: var(--text-sub);">Forbidden Calls</div>
            </div>
        </div>
EOF

    # Content
    if [ "$count_val" -eq 0 ]; then
        echo "        <div class='perfect-msg'>🎉 Perfect! No unauthorized functions found.</div>" >> "$html_file"
    else
        echo "        <div class='grid'>" >> "$html_file"
        local delay=0.1
        if [ "$IS_SOURCE_SCAN" = true ]; then
            local match_data=$(echo "$JSON_RAW_DATA" | grep "MATCH")
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local fname=$(echo "$line" | perl -nle 'print $1 if /-> ([^|]+)/')
                local fpath=$(echo "$line" | perl -nle 'print $1 if /in (\S+?):/')
                local lnum=$(echo "$line"  | perl -nle 'print $1 if /:([0-9]+)$/')
                lnum=${lnum:-0}

                cat <<EOF >> "$html_file"
            <div class="issue-card" style="animation-delay: ${delay}s;">
                <h3 class="func-name">$fname</h3>
                <div class="location">📄 $fpath:$lnum</div>
            </div>
EOF
            done <<< "$match_data"
        else
            for f_name in $forbidden_list; do
                safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')
                local locations=$(grep -E ":.*\b${safe_name}\b" <<< "$grep_res")
                while read -r line; do
                    [ -z "$line" ] && continue
                    local f_path=$(echo "$line" | cut -d: -f1 | sed 's|^\./||')
                    local l_num=$(echo "$line" | cut -d: -f2)
                    l_num=${l_num:-0}
                    cat <<EOF >> "$html_file"
            <div class="issue-card" style="animation-delay: ${delay}s;">
                <h3 class="func-name">$f_name</h3>
                <div class="location">📄 $f_path:$l_num</div>
            </div>
EOF
                done <<< "$locations"
            done
        fi
        echo "        </div>" >> "$html_file"
    fi

    # Footer
    cat <<EOF >> "$html_file"
    </div>
</body>
</html>
EOF

    echo -ne "\n${BLUE}ℹ Rapport HTML généré avec succès dans : ${YELLOW}$html_file${NC}\n"
}
