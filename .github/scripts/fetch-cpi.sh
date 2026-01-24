#!/bin/bash
set -e

echo "============================================"
echo "Fetching CPI data from BLS"
echo "============================================"

FILE="src/pages/index.astro"
declare -A CATEGORY_DATA

##############################################
# FETCH TABLE A (All items, Apparel)
##############################################
echo "Fetching BLS Table A..."

HTML=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Connection: keep-alive" \
  -H "Upgrade-Insecure-Requests: 1" \
  "https://www.bls.gov/news.release/cpi.nr0.htm")

if [ -z "$HTML" ] || echo "$HTML" | grep -q "Access Denied"; then
  echo "⚠️ BLS blocked Table A. Keeping existing data."
  exit 0
fi

TABLE_A=$(echo "$HTML" | tr '\n' ' ' | grep -oP '<table[^>]*id="cpi_pressa"[^>]*>.*?</table>')
[ -z "$TABLE_A" ] && echo "⚠️ Table A not found" && exit 0

# Extract report month/year
MONTH_YEAR=$(echo "$TABLE_A" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*<br\s*/>\s*20[0-9]{2}' | tail -1 | sed 's/<br[^>]*>/ /')
REPORT_MONTH=$(echo "$MONTH_YEAR" | cut -d' ' -f1)
REPORT_YEAR=$(echo "$MONTH_YEAR" | cut -d' ' -f2)

declare -A MONTH_MAP=(
  [Jan]=January [Feb]=February [Mar]=March [Apr]=April
  [May]=May [Jun]=June [Jul]=July [Aug]=August
  [Sep]=September [Oct]=October [Nov]=November [Dec]=December
)

FULL_MONTH="${MONTH_MAP[$REPORT_MONTH]} $REPORT_YEAR"

extract_table_a() {
  local pattern="$1"
  local label="$2"

  row=$(echo "$TABLE_A" | grep -oP "<tr[^>]*>.*?$pattern.*?</tr>" | head -1)
  values=($(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+'))

  monthly="${values[-2]}"
  annual="${values[-1]}"

  [[ "$monthly" == "-" ]] && monthly="0.0"
  [[ "$annual" == "-" ]] && annual="0.0"

  CATEGORY_DATA["$label"]="$monthly|$annual"
  echo "✓ $label (A): $monthly / $annual"
}

extract_table_a "All items" "All Items"
extract_table_a "<p class=\"sub3\">Apparel</p>" "Apparel"

##############################################
# FETCH TABLE 3 (Major groups)
##############################################
echo "Fetching BLS Table 3..."

HTML3=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Connection: keep-alive" \
  -H "Upgrade-Insecure-Requests: 1" \
  "https://www.bls.gov/news.release/cpi.t03.htm")

if [ -z "$HTML3" ] || echo "$HTML3" | grep -q "Access Denied"; then
  echo "⚠️ BLS blocked Table 3. Continuing with Table A only."
else
  TABLE_3=$(echo "$HTML3" | tr '\n' ' ' | grep -oP '<table[^>]*id="cpipress3"[^>]*>.*?</table>')

  extract_table_3() {
    local pattern="$1"
    local label="$2"

    row=$(echo "$TABLE_3" | grep -oP "<tr[^>]*>.*?$pattern.*?</tr>" | head -1)

    annual=$(echo "$row" | grep -oP 'headers="[^"]*cpipress3\.h\.2\.6[^"]*"[^>]*>[^<]*<span class="datavalue">([^<]+)' | grep -oP '[0-9.-]+')
    monthly=$(echo "$row" | grep -oP 'headers="[^"]*cpipress3\.h\.2\.10[^"]*"[^>]*>[^<]*<span class="datavalue">([^<]+)' | grep -oP '[0-9.-]+')

    [[ -z "$monthly" ]] && monthly="0.0"
    [[ -z "$annual" ]] && annual="0.0"

    CATEGORY_DATA["$label"]="$monthly|$annual"
    echo "✓ $label (3): $monthly / $annual"
  }

  extract_table_3 "<p class=\"sub0\">Housing</p>" "Housing"
  extract_table_3 "<p class=\"sub0\">Food and beverages</p>" "Food and Beverages"
  extract_table_3 "<p class=\"sub0\">Transportation</p>" "Transportation"
  extract_table_3 "<p class=\"sub0\">Medical care</p>" "Medical Care"
  extract_table_3 "<p class=\"sub1\">Education</p>" "Education"
  extract_table_3 "<p class=\"sub1\">Communication</p>" "Communication"
  extract_table_3 "<p class=\"sub0\">Recreation</p>" "Recreation"
  extract_table_3 "<p class=\"sub0\">Other goods and services</p>" "Other Goods and Services"
fi

##############################################
# BUILD JSON (strict order)
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
    JSON+="
    '$c': { monthly: $m, annual: $a },"
  fi
done
JSON="${JSON%,}
}"

##############################################
# UPDATE index.astro
##############################################
REPORT_DATE=$(date +'%B %d, %Y')

NEW_DATA="  function useMockData() {
    cpiData = {
      reportDate: '$REPORT_DATE',
      reportMonth: '$FULL_MONTH',
      categories: $JSON
    };
    renderPage();
  }"

perl -i -0pe "s/function useMockData\(\) \{.*?\n  \}/$NEW_DATA/s" "$FILE"

echo "✅ CPI data updated successfully"
