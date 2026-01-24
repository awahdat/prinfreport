#!/bin/bash

############################################
# Fetch Table A (Main CPI)
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
    echo "Failed to fetch Table A. Keeping existing data."
    exit 0
fi

TABLE=$(echo "$HTML" | tr '\n' ' ' | grep -oP '<table[^>]*id="cpi_pressa"[^>]*>.*?</table>')
[ -z "$TABLE" ] && echo "Table A not found" && exit 0

############################################
# Report month
############################################
MONTH_YEAR=$(echo "$TABLE" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*<br\s*/>\s*20[0-9]{2}' | tail -1 | sed 's/<br[^>]*>/ /')
REPORT_MONTH=$(echo "$MONTH_YEAR" | awk '{print $1}')
REPORT_YEAR=$(echo "$MONTH_YEAR" | awk '{print $2}')

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

############################################
# JSON init
############################################
JSON_DATA="{"

############################################
# Table A extractor
############################################
extract_category_data() {
  local search="$1"
  local name="$2"
  local row=$(echo "$TABLE" | grep -oP "<tr[^>]*>.*?$search.*?</tr>" | head -1)

  if [ -z "$row" ]; then
    JSON_DATA="${JSON_DATA}
      '${name}': { monthly: 0.0, annual: 0.0 },"
    return
  fi

  local values=($(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+'))
  local monthly="${values[-2]:-0.0}"
  local annual="${values[-1]:-0.0}"

  [ "$monthly" = "-" ] && monthly="0.0"
  [ "$annual" = "-" ] && annual="0.0"

  JSON_DATA="${JSON_DATA}
      '${name}': { monthly: ${monthly}, annual: ${annual} },"
}

############################################
# Table A categories (restricted)
############################################
extract_category_data "All items" "All Items"
extract_category_data "<p class=\"sub3\">Apparel</p>" "Apparel"

############################################
# Fetch Table 3 (Major groups)
############################################
echo "Fetching BLS Table 3..."

HTML3=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Connection: keep-alive" \
  -H "Upgrade-Insecure-Requests: 1" \
  "https://www.bls.gov/news.release/cpi.t03.htm")

if ! echo "$HTML3" | grep -q "Access Denied"; then
  TABLE3=$(echo "$HTML3" | tr '\n' ' ' | grep -oP '<table[^>]*id="cpipress3"[^>]*>.*?</table>')
fi

############################################
# Table 3 extractor (ID-based, correct)
############################################
extract_table3() {
  local pattern="$1"
  local name="$2"

  local row=$(echo "$TABLE3" | grep -oP "<tr[^>]*>.*?$pattern.*?</tr>" | head -1)

  local annual=$(echo "$row" | grep -oP 'headers="[^"]*cpipress3\.h\.2\.6[^"]*"[^>]*>\s*<span class="datavalue">[^<]+' | grep -oP '[0-9.-]+')
  local monthly=$(echo "$row" | grep -oP 'headers="[^"]*cpipress3\.h\.2\.10[^"]*"[^>]*>\s*<span class="datavalue">[^<]+' | grep -oP '[0-9.-]+')

  annual=${annual:-0.0}
  monthly=${monthly:-0.0}

  JSON_DATA="${JSON_DATA}
      '${name}': { monthly: ${monthly}, annual: ${annual} },"
}

############################################
# Table 3 categories (exact + correct)
############################################
extract_table3 "<p class=\"sub0\">Housing</p>" "Housing"
extract_table3 "<p class=\"sub0\">Food and beverages</p>" "Food and Beverages"
extract_table3 "<p class=\"sub0\">Transportation</p>" "Transportation"
extract_table3 "<p class=\"sub0\">Medical care</p>" "Medical Care"
extract_table3 "<p class=\"sub1\">Education</p>" "Education"
extract_table3 "<p class=\"sub1\">Communication</p>" "Communication"
extract_table3 "<p class=\"sub0\">Recreation</p>" "Recreation"
extract_table3 "<p class=\"sub0\">Other goods and services</p>" "Other Goods and Services"

############################################
# Finalize JSON
############################################
JSON_DATA="${JSON_DATA%,}
      }"

############################################
# Dates
############################################
get_previous_month() {
  case "$1" in
    *January*) echo "December";;
    *February*) echo "January";;
    *March*) echo "February";;
    *April*) echo "March";;
    *May*) echo "April";;
    *June*) echo "May";;
    *July*) echo "June";;
    *August*) echo "July";;
    *September*) echo "August";;
    *October*) echo "September";;
    *November*) echo "October";;
    *December*) echo "November";;
  esac
}

PREV_MONTH=$(get_previous_month "$FULL_MONTH")
PREV_YEAR="${FULL_MONTH/20*/$((REPORT_YEAR - 1))}"
REPORT_DATE=$(date +'%B %d, %Y')

############################################
# Inject into index.astro
############################################
NEW_MOCK_DATA="  function useMockData() {
    cpiData = {
      reportDate: '$REPORT_DATE',
      reportMonth: '$FULL_MONTH',
      previousMonth: '$PREV_MONTH',
      previousYear: '$PREV_YEAR',
      categories: ${JSON_DATA}
    };
    renderPage();
  }"

perl -i -0pe 's/function useMockData\(\) \{.*?\n  \}/'"$(echo "$NEW_MOCK_DATA" | sed 's/[&/\]/\\&/g')"'/s' src/pages/index.astro

echo "✅ CPI data updated successfully!"
