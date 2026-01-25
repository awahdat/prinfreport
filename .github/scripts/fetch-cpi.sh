#!/bin/bash

############################################
# FETCH TABLE A (unchanged, working)
############################################

echo "Fetching BLS Table A..."
HTML=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Connection: keep-alive" \
  -H "Upgrade-Insecure-Requests: 1" \
  "https://www.bls.gov/news.release/cpi.nr0.htm")

if [ -z "$HTML" ] || echo "$HTML" | grep -q "Access Denied"; then
    echo "Table A fetch blocked. Keeping existing data."
    exit 0
fi

TABLE=$(echo "$HTML" | tr '\n' ' ' | grep -oP '<table[^>]*id="cpi_pressa"[^>]*>.*?</table>')
[ -z "$TABLE" ] && exit 0

MONTH_YEAR=$(echo "$TABLE" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*<br\s*/>\s*20[0-9]{2}' | tail -1 | sed 's/<br[^>]*>/ /')
REPORT_MONTH=$(echo "$MONTH_YEAR" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)')
REPORT_YEAR=$(echo "$MONTH_YEAR" | grep -oP '20[0-9]{2}')

case "$REPORT_MONTH" in
  Jan) REPORT_MONTH="January";;
  Feb) REPORT_MONTH="February";;
  Mar) REPORT_MONTH="March";;
  Apr) REPORT_MONTH="April";;
  May) REPORT_MONTH="May";;
  Jun) REPORT_MONTH="June";;
  Jul) REPORT_MONTH="July";;
  Aug) REPORT_MONTH="August";;
  Sep) REPORT_MONTH="September";;
  Oct) REPORT_MONTH="October";;
  Nov) REPORT_MONTH="November";;
  Dec) REPORT_MONTH="December";;
esac

FULL_MONTH="$REPORT_MONTH $REPORT_YEAR"
echo "Report month: $FULL_MONTH"

declare -A CATEGORY_DATA

extract_table_a() {
  local search="$1"
  local name="$2"
  row=$(echo "$TABLE" | grep -oP "<tr[^>]*>.*?$search.*?</tr>" | head -1)
  vals=($(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+'))
  monthly="${vals[-2]:-0.0}"
  annual="${vals[-1]:-0.0}"
  CATEGORY_DATA["$name"]="$monthly|$annual"
}

extract_table_a "All items" "All Items"
extract_table_a "<p class=\"sub3\">Apparel</p>" "Apparel"

############################################
# FETCH TABLE 3 (FIXED & ROBUST)
############################################

echo "Fetching BLS Table 3..."
HTML3=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Connection: keep-alive" \
  -H "Upgrade-Insecure-Requests: 1" \
  "https://www.bls.gov/news.release/cpi.t03.htm")

if [ -z "$HTML3" ] || echo "$HTML3" | grep -q "Access Denied"; then
    echo "Table 3 blocked — continuing with Table A only."
else
    TABLE3=$(echo "$HTML3" | tr '\n' ' ' | grep -oP '<table[^>]*id="cpipress3"[^>]*>.*?</table>')

extract_table3() {
    local row_id="$1"
    local name="$2"

    # Get full row containing this category
    local row
    row=$(echo "$TABLE3" | tr '\n' ' ' | grep -oP \
        "<tr[^>]*>\\s*<th[^>]*id=\"$row_id\".*?</tr>")

    if [ -z "$row" ]; then
        echo "  $name: row not found"
        CATEGORY_DATA["$name"]="0.0|0.0"
        return
    fi

    # Annual (12-month change)
    local annual
    annual=$(echo "$row" | grep -oP \
        "<td[^>]*headers=\"$row_id cpipress3.h.1.6 cpipress3.h.2.6\"[^>]*>.*?</td>" \
        | sed -n 's/.*<span class="datavalue">\([^<]*\)<\/span>.*/\1/p')

    # Monthly (1-month change)
    local monthly
    monthly=$(echo "$row" | grep -oP \
        "<td[^>]*headers=\"$row_id cpipress3.h.1.8 cpipress3.h.2.10\"[^>]*>.*?</td>" \
        | sed -n 's/.*<span class="datavalue">\([^<]*\)<\/span>.*/\1/p')

    # Normalize dashes / empty
    [[ -z "$annual"  || "$annual"  == "-" ]] && annual="0.0"
    [[ -z "$monthly" || "$monthly" == "-" ]] && monthly="0.0"

    echo "  $name: monthly=$monthly annual=$annual"
    CATEGORY_DATA["$name"]="$monthly|$annual"
}


    extract_table3 "cpipress3.r.12"   "Housing"
    extract_table3 "cpipress3.r.13.1" "Education"
    extract_table3 "cpipress3.r.13.2" "Communication"
    extract_table3 "cpipress3.r.14"   "Recreation"
    extract_table3 "cpipress3.r.15"   "Food and Beverages"
    extract_table3 "cpipress3.r.19"   "Medical Care"
    extract_table3 "cpipress3.r.20"   "Transportation"
    extract_table3 "cpipress3.r.23"   "Other Goods and Services"

fi

############################################
# BUILD JSON (ORDER GUARANTEED)
############################################

ORDER=(
  "All Items"
  "Housing"
  "Food and Beverages"
  "Transportation"
  "Medical Care"
  "Education"
  "Communication"
  "Recreation"
  "Apparel"
  "Other Goods and Services"
)

JSON_DATA="{"
for k in "${ORDER[@]}"; do
  if [ -n "${CATEGORY_DATA[$k]}" ]; then
    IFS='|' read m a <<< "${CATEGORY_DATA[$k]}"
    JSON_DATA="$JSON_DATA
    '$k': { monthly: $m, annual: $a },"
  fi
done
JSON_DATA="${JSON_DATA%,}
}"

# Get previous month
get_previous_month() {
    local current="$1"
    case "$current" in
        *January*) echo "December" ;;
        *February*) echo "January" ;;
        *March*) echo "February" ;;
        *April*) echo "March" ;;
        *May*) echo "April" ;;
        *June*) echo "May" ;;
        *July*) echo "June" ;;
        *August*) echo "July" ;;
        *September*) echo "August" ;;
        *October*) echo "September" ;;
        *November*) echo "October" ;;
        *December*) echo "November" ;;
        *) echo "Previous Month" ;;
    esac
}

############################################
# UPDATE index.astro (unchanged)
############################################

REPORT_DATE=$(date +'%B %d, %Y')
PREV_YEAR="${FULL_MONTH/$REPORT_YEAR/$((REPORT_YEAR-1))}"
PREV_MONTH=$(get_previous_month "$FULL_MONTH")

NEW_MOCK_DATA="  function useMockData() {
    cpiData = {
      reportDate: '$REPORT_DATE',
      reportMonth: '$FULL_MONTH',
      previousMonth: '$PREV_MONTH',
      previousYear: '$PREV_YEAR',
      categories: $JSON_DATA
    };
    renderPage();
  }"

perl -i -0pe 's/function useMockData\(\) \{.*?\n  \}/'"$(echo "$NEW_MOCK_DATA" | sed 's/[&/\]/\\&/g')"'/s' src/pages/index.astro

echo "✅ CPI data updated successfully!"
