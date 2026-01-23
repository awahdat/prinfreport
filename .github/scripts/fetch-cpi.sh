#!/bin/bash

# Fetch BLS page
echo "Fetching BLS data..."
HTML=$(curl -s "https://www.bls.gov/news.release/cpi.nr0.htm")

if [ -z "$HTML" ]; then
    echo "Failed to fetch BLS page. Keeping existing data."
    exit 0
fi

# Extract Table A (the first table with id="cpi_pressa")
TABLE=$(echo "$HTML" | sed -n '/<table.*id="cpi_pressa"/,/<\/table>/p')

if [ -z "$TABLE" ]; then
    echo "Table A not found. Keeping existing data."
    exit 0
fi

# Extract report month from the last <th> in the second header row
# This is the "Dec. 2025" column header
REPORT_MONTH=$(echo "$TABLE" | grep -A1 'Seasonally adjusted' | tail -1 | grep -oP '(?<=<th[^>]*>)[^<]*(?=<br />2025</th>)' | tail -1)
REPORT_YEAR=$(echo "$TABLE" | grep -A1 'Seasonally adjusted' | tail -1 | grep -oP '2025(?=</th>)' | tail -1)

# Combine month and year
FULL_MONTH="${REPORT_MONTH} ${REPORT_YEAR}"

if [ -z "$FULL_MONTH" ]; then
    FULL_MONTH="Latest Month"
fi

echo "Report month: $FULL_MONTH"

# Function to extract values for a specific category
extract_category_data() {
    local search_pattern="$1"
    local display_name="$2"
    
    # Find the row containing this category
    local row=$(echo "$TABLE" | grep -i "<p class=\"sub[0-9]\">$search_pattern</p>" | head -1)
    
    if [ -z "$row" ]; then
        echo "  $display_name: NOT FOUND"
        return
    fi
    
    # Extract all datavalues from the row
    local values=$(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+(?=</span>)')
    
    # Get second-to-last value (monthly) and last value (annual)
    local monthly=$(echo "$values" | tail -2 | head -1 | tr -d ' ')
    local annual=$(echo "$values" | tail -1 | tr -d ' ')
    
    # Handle dash (-) as 0.0
    if [ "$monthly" = "-" ]; then
        monthly="0.0"
    fi
    if [ "$annual" = "-" ]; then
        annual="0.0"
    fi
    
    echo "  $display_name: monthly=$monthly, annual=$annual"
    
    # Add to JSON
    JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: ${monthly}, annual: ${annual} },"
}

# Initialize JSON object
JSON_DATA="{"

# Extract data for each category (using exact text from HTML)
extract_category_data "All items" "All Items"
extract_category_data "Food" "Food"
extract_category_data "Food at home" "Food at Home"
extract_category_data "Food away from home" "Food Away from Home"
extract_category_data "Gasoline \\(all types\\)" "Gasoline"
extract_category_data "Energy services" "Energy Services"
extract_category_data "New vehicles" "New Vehicles"
extract_category_data "Used cars and trucks" "Used Cars and Trucks"
extract_category_data "Apparel" "Apparel"
extract_category_data "Shelter" "Shelter"
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
        *Jan*) echo "December" ;;
        *Feb*) echo "January" ;;
        *Mar*) echo "February" ;;
        *Apr*) echo "March" ;;
        *May*) echo "April" ;;
        *Jun*) echo "May" ;;
        *Jul*) echo "June" ;;
        *Aug*) echo "July" ;;
        *Sep*) echo "August" ;;
        *Oct*) echo "September" ;;
        *Nov*) echo "October" ;;
        *Dec*) echo "November" ;;
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
