#!/bin/bash
set -e

FILE="src/pages/index.astro"

echo "============================================"
echo "Fetching CPI data from BLS"
echo "============================================"

##############################################
# FETCH TABLE A (All Items, Apparel)
##############################################
echo "Fetching BLS Table A..."

HTML_A=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0" \
  "https://www.bls.gov/news.release/cpi.nr0.htm")

if [[ -z "$HTML_A" || "$HTML_A" == *"Access Denied"* ]]; then
  echo "❌ Failed to fetch Table A"
  exit 0
fi

TABLE_A=$(echo "$HTML_A" | tr '\n' ' ' \
  | grep -oP '<table[^>]*id="cpi_pressa"[^>]*>.*?</table>')

if [ -z "$TABLE_A" ]; then
  echo "❌ Table A not found"
  exit 0
fi

##############################################
# REPORT MONTH
##############################################
MONTH_YEAR=$(echo "$TABLE_A" \
  | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*<br\s*/>\s*20[0-9]{2}' \
  | tail -1 | sed 's/<br[^>]*>/ /')

MONTH_ABBR=$(echo "$MONTH_YEAR" | awk '{print $1}')
YEAR=$(echo "$MONTH_YEAR" | awk '{print $2}')

case "$MONTH_ABBR" in
  Jan) MONTH="January" ;;
  Feb) MONTH="February" ;;
  Mar) MONTH="March" ;;
  Apr) MONTH="April" ;;
  May) MONTH="May" ;;
  Jun) MONTH="June" ;;
  Jul) MONTH="July" ;;
  Aug) MONTH="August" ;;
  Sep) MONTH="September" ;;
  Oct) MONTH="October" ;;
  Nov) MONTH="November" ;;
  Dec) MONTH="December" ;;
esac

FULL_MONTH="$MONTH $YEAR"
REPORT_DATE=$(date +"%B %d, %Y")

##############################################
# HELPERS
##############################################
declare -A CATEGORY_DATA

extract_tableA() {
  local label="$1"
  local name="$2"

  row=$(echo "$TABLE_A" | grep -oP "<tr[^>]*>.*?$label.*?</tr>" | head -1)
  values=$(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+')

  arr=($values)
  monthly="${arr[-2]}"
  annual="${arr[-1]}"

  [[ "$monthly" == "-" ]] && monthly="0.0"
  [[ "$annual" == "-" ]] && annual="0.0"

  CATEGORY_DATA["$name"]="$monthly|$annual"
  echo "✓ $name (A): $monthly / $annual"
}

##############################################
# TABLE A EXTRACTION
##############################################
extract_tableA "All items" "All Items"
extract_tableA "<p class=\"sub3\">Apparel</p>" "Apparel"

##############################################
# FETCH TABLE 3
##############################################
echo ""
echo "Fetching BLS Table 3..."

HTML_3=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0" \
  "https://www.bls.gov/news.release/cpi.t03.htm")

if [[ -z "$HTML_3" || "$HTML_3" == *"Access Denied"* ]]; then
  echo "⚠️ Table 3 blocked — continuing"
else
  TABLE_3=$(echo "$HTML_3" | tr '\n' ' ' \
    | grep -oP '<table[^>]*id="cpipress3"[^>]*>.*?</table>')

  extract_table3() {
    local label="$1"
    local name="$2"

    row=$(echo "$TABLE_3" | tr '\n' ' ' \
      | grep -oP "<tr[^>]*>[^<]*$label.*?</tr>" | head -1)

    annual=$(echo "$row" | grep -oP \
      '<td[^>]*headers="[^"]*cpipress3\.h\.2\.6[^"]*"[^>]*>.*?<span class="datavalue">([^<]+)</span>' \
      | grep -oP '(?<=datavalue>)[^<]+')

    monthly=$(echo "$row" | grep -oP \
      '<td[^>]*headers="[^"]*cpipress3\.h\.2\.10[^"]*"[^>]*>.*?<span class="datavalue">([^<]+)</span>' \
      | grep -oP '(?<=datavalue>)[^<]+')

    [[ -z "$monthly" || "$monthly" == "-" ]] && monthly="0.0"
    [[ -z "$annual" || "$annual" == "-" ]] && annual="0.0"

    CATEGORY_DATA["$name"]="$monthly|$annual"
    echo "✓ $name (3): $monthly / $annual"
  }

  extract_table3 "<p class=\"sub0\">Housing</p>" "Housing"
  extract_table3 "<p class=\"sub0\">Food and beverages</p>" "Food and Beverages"
  extract_table3 "<p class=\"sub0\">Transportation</p>" "Transportation"
  extract_table3 "<p class=\"sub0\">Medical care</p>" "Medical Care"
  extract_table3 "<p class=\"sub1\">Education</p>" "Education"
  extract_table3 "<p class=\"sub1\">Communication</p>" "Communication"
  extract_table3 "<p class=\"sub0\">Recreation</p>" "Recreation"
  extract_table3 "<p class=\"sub0\">Other goods and services</p>" "Other Goods and Services"
fi

##############################################
# BUILD JSON (ORDERED)
##############################################
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

JSON="{"
for c in "${ORDER[@]}"; do
  if [ -n "${CATEGORY_DATA[$c]}" ]; then
    IFS='|' read m a <<< "${CATEGORY_DATA[$c]}"
    JSON="$JSON
        '$c': { monthly: $m, annual: $a },"
  fi
done
JSON="${JSON%,}
      }"

##############################################
# PREVIOUS PERIODS
##############################################
PREV_MONTH=$(date -d "$FULL_MONTH -1 month" +"%B")
PREV_YEAR=$(date -d "$FULL_MONTH -1 year" +"%B %Y")

##############################################
# UPDATE index.astro
##############################################
NEW_DATA="  function useMockData() {
    cpiData = {
      reportDate: '$REPORT_DATE',
      reportMonth: '$FULL_MONTH',
      previousMonth: '$PREV_MONTH',
      previousYear: '$PREV_YEAR',
      categories: $JSON
    };
    renderPage();
  }"

perl -i -0pe 's/function useMockData\(\) \{.*?\n  \}/'"$(echo "$NEW_DATA" | sed 's/[\/&]/\\&/g')"'/s' "$FILE"

echo ""
echo "✅ CPI data updated successfully"
