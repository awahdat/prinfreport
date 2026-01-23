#!/bin/bash

# Fetch BLS page
echo "Fetching BLS data..."
HTML=$(curl -s "https://www.bls.gov/news.release/cpi.nr0.htm")

if [ -z "$HTML" ]; then
    echo "Failed to fetch BLS page. Keeping existing data."
    exit 0
fi

# Extract Table A (find table after "Table A" text)
TABLE=$(echo "$HTML" | sed -n '/<.*Table A/,/<\/table>/p' | tail -n +2)

if [ -z "$TABLE" ]; then
    echo "Table A not found. Keeping existing data."
    exit 0
fi

# Function to extract value from table row
extract_value() {
    local category="$1"
    local column_offset="$2"  # -2 for monthly, -1 for annual
    
    # Find the row containing the category
    ROW=$(echo "$TABLE" | grep -i "$category" | head -1)
    
    if [ -z "$ROW" ]; then
        echo "0.0"
        return
    fi
    
    # Extract all <td> values
    VALUES=$(echo "$ROW" | grep -oP '(?<=<td[^>]*>)[^<]+(?=</td>)')
    
    # Get the specific column (second-to-last or last)
    if [ "$column_offset" -eq "-2" ]; then
        VALUE=$(echo "$VALUES" | tail -2 | head -1)
    else
        VALUE=$(echo "$VALUES" | tail -1)
    fi
    
    # Clean up (remove spaces, convert to number)
    VALUE=$(echo "$VALUE" | tr -d ' ' | grep -oP '[-]?[0-9]+\.[0-9]+|[-]?[0-9]+')
    
    echo "${VALUE:-0.0}"
}

# Extract report month from second-to-last column header
HEADER_ROW=$(echo "$TABLE" | grep -m1 '<th' | head -1)
REPORT_MONTH=$(echo "$HEADER_ROW" | grep -oP '(?<=<th[^>]*>)[^<]+(?=</th>)' | tail -2 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$REPORT_MONTH" ]; then
    REPORT_MONTH="Latest Month"
fi

echo "Report month: $REPORT_MONTH"

# Extract data for each category
declare -A CATEGORIES
CATEGORIES["All items"]="All Items"
CATEGORIES["Food"]="Food"
CATEGORIES["Food at home"]="Food at Home"
CATEGORIES["Food away from home"]="Food Away from Home"
CATEGORIES["Gasoline (all types)"]="Gasoline"
CATEGORIES["Energy services"]="Energy Services"
CATEGORIES["New vehicles"]="New Vehicles"
CATEGORIES["Used cars and trucks"]="Used Cars and Trucks"
CATEGORIES["Apparel"]="Apparel"
CATEGORIES["Shelter"]="Shelter"
CATEGORIES["Transportation services"]="Transportation Services"
CATEGORIES["Medical care services"]="Medical Services"

# Build JSON object
JSON_DATA="{"

for key in "${!CATEGORIES[@]}"; do
    display_name="${CATEGORIES[$key]}"
    monthly=$(extract_value "$key" -2)
    annual=$(extract_value "$key" -1)
    
    echo "  $display_name: monthly=$monthly, annual=$annual"
    
    JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: ${monthly}, annual: ${annual} },"
done

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

PREV_MONTH=$(get_previous_month "$REPORT_MONTH")
PREV_YEAR=$(get_previous_year "$REPORT_MONTH")
REPORT_DATE=$(date +'%B %d, %Y')

# Create the new mock data function
NEW_MOCK_DATA="  function useMockData() {
    cpiData = {
      reportDate: '$REPORT_DATE',
      reportMonth: '$REPORT_MONTH',
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
perl -i -0pe 's/function useMockData\(\)\s*\{[\s\S]*?\}/'"$(echo "$NEW_MOCK_DATA" | sed 's/[&/\]/\\&/g')"'/s' "$FILE"

echo "----- DIFF AFTER REPLACEMENT -----"
git diff src/pages/index.astro || echo "NO DIFF"

echo "✅ Mock data updated successfully!"
