#!/bin/bash

# Fetch BLS page with browser-like headers and automatic decompression
echo "Fetching BLS data..."
HTML=$(curl -s -L --compressed \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Connection: keep-alive" \
  -H "Upgrade-Insecure-Requests: 1" \
  "https://www.bls.gov/news.release/cpi.nr0.htm")

if [ -z "$HTML" ]; then
    echo "Failed to fetch BLS page. Keeping existing data."
    exit 0
fi

# Check if we got blocked
if echo "$HTML" | grep -q "Access Denied"; then
    echo "BLS blocked the request. Keeping existing data."
    exit 0
fi

echo "Valid HTML received. Parsing table..."

# Extract Table A by ID
TABLE=$(echo "$HTML" | sed -n '/<table.*id="cpi_pressa"/,/<\/table>/p')

if [ -z "$TABLE" ]; then
    echo "Table with id=cpi_pressa not found. Keeping existing data."
    exit 0
fi

echo "Table found! Extracting data..."

# Extract report month and year from the last column header (Dec. 2025)
MONTH_YEAR=$(echo "$TABLE" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*<br\s*/>\s*20[0-9]{2}' | tail -1 | sed 's/<br[^>]*>//' | sed 's/\s\+/ /')

# If not found, try simpler pattern
if [ -z "$MONTH_YEAR" ]; then
    MONTH_YEAR=$(echo "$TABLE" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*20[0-9]{2}' | tail -1)
fi

REPORT_MONTH=$(echo "$MONTH_YEAR" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)')
REPORT_YEAR=$(echo "$MONTH_YEAR" | grep -oP '20[0-9]{2}')

# Expand abbreviated month
case "$REPORT_MONTH" in
    Jan) REPORT_MONTH="January" ;;
    Feb) REPORT_MONTH="February" ;;
    Mar) REPORT_MONTH="March" ;;
    Apr) REPORT_MONTH="April" ;;
    May) REPORT_MONTH="May" ;;
    Jun) REPORT_MONTH="June" ;;
    Jul) REPORT_MONTH="July" ;;
    Aug) REPORT_MONTH="August" ;;
    Sep) REPORT_MONTH="September" ;;
    Oct) REPORT_MONTH="October" ;;
    Nov) REPORT_MONTH="November" ;;
    Dec) REPORT_MONTH="December" ;;
esac

FULL_MONTH="${REPORT_MONTH} ${REPORT_YEAR}"
echo "Report month: $FULL_MONTH"

# Function to extract values for a specific category
extract_category_data() {
    local search_text="$1"
    local display_name="$2"
    
    # Find the complete row for this category
    # Look for the text within <p> tags, then get the entire <tr> row
    local row=$(echo "$TABLE" | grep -B1 -A1 "$search_text" | grep -A1 "<tr" | head -5)
    
    if [ -z "$row" ]; then
        echo "  $display_name: Row not found for pattern: $search_text"
        JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: 0.0, annual: 0.0 },"
        return
    fi
    
    # Extract all datavalue spans from this row
    local all_values=$(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+(?=</span>)' | tr '\n' ' ')
    
    echo "  $display_name - All values: [$all_values]"
    
    # Convert to array
    local values_array=($all_values)
    local num_values=${#values_array[@]}
    
    if [ $num_values -lt 2 ]; then
        echo "  $display_name: Not enough values found"
        JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: 0.0, annual: 0.0 },"
        return
    fi
    
    # Get second-to-last (monthly) and last (annual) values
    local monthly_idx=$((num_values - 2))
    local annual_idx=$((num_values - 1))
    
    local monthly="${values_array[$monthly_idx]}"
    local annual="${values_array[$annual_idx]}"
    
    # Handle dash as 0.0
    if [ "$monthly" = "-" ]; then
        monthly="0.0"
    fi
    if [ "$annual" = "-" ]; then
        annual="0.0"
    fi
    
    echo "  $display_name: monthly=$monthly, annual=$annual"
    
    JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: ${monthly}, annual: ${annual} },"
}

# Initialize JSON object
JSON_DATA="{"

# Extract data - use exact text from the HTML
extract_category_data "All items" "All Items"
extract_category_data ">Food</p>" "Food"
extract_category_data "Food at home" "Food at Home"
extract_category_data "Food away from home" "Food Away from Home"
extract_category_data "Gasoline (all types)" "Gasoline"
extract_category_data "Energy services" "Energy Services"
extract_category_data "New vehicles" "New Vehicles"
extract_category_data "Used cars and trucks" "Used Cars and Trucks"
extract_category_data ">Apparel</p>" "Apparel"
extract_category_data ">Shelter</p>" "Shelter"
extract_category_data "Transportation services" "Transportation Services"
extract_category_data "Medical care services" "Medical Services"

# Remove trailing comma
JSON_DATA="${JSON_DATA%,}"
JSON_DATA="${JSON_DATA}
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

# Get previous year
get_previous_year() {
    local current="$1"
    if [[ "$current" =~ ([0-9]{4}) ]]; then
        local year="${BASH_REMATCH[1]}"
        local prev_year=$((year - 1))
        echo "${current/$year/$prev_year}"
    else
        echo "One Year Ago"
    fi
}

PREV_MONTH=$(get_previous_month "$FULL_MONTH")
PREV_YEAR=$(get_previous_year "$FULL_MONTH")
REPORT_DATE=$(date +'%B %d, %Y')

# Create the new mock data function
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

# Update index.astro
FILE="src/pages/index.astro"

if [ ! -f "$FILE" ]; then
    echo "Error: $FILE not found"
    exit 1
fi

# Use perl for multi-line regex replacement (available in GitHub Actions)
perl -i -0pe 's/function useMockData\(\) \{.*?\n  \}/'"$(echo "$NEW_MOCK_DATA" | sed 's/[&/\]/\\&/g')"'/s' "$FILE"

echo "✅ Mock data updated successfully!"
