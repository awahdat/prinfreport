#!/bin/bash

# Fetch BLS page with browser-like headers
echo "Fetching BLS data..."
HTML=$(curl -s -L \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.5" \
  -H "Accept-Encoding: gzip, deflate, br" \
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
    echo "This is normal - BLS has bot protection."
    exit 0
fi

# Try multiple methods to find Table A
# Method 1: Look for table with id="cpi_pressa"
TABLE=$(echo "$HTML" | sed -n '/<table.*id="cpi_pressa"/,/<\/table>/p')

# Method 2: If not found, look for first table after "Table A" text
if [ -z "$TABLE" ]; then
    echo "Method 1 failed, trying method 2..."
    TABLE=$(echo "$HTML" | sed -n '/Table A\./,/<\/table>/p' | sed -n '/<table/,/<\/table>/p')
fi

# Method 3: Look for table with caption containing "Table A"
if [ -z "$TABLE" ]; then
    echo "Method 2 failed, trying method 3..."
    TABLE=$(echo "$HTML" | awk '/<caption>.*Table A/,/<\/table>/' | sed -n '/<table/,/<\/table>/p')
fi

# Method 4: Get the first table in the document (usually Table A)
if [ -z "$TABLE" ]; then
    echo "Method 3 failed, trying method 4..."
    TABLE=$(echo "$HTML" | sed -n '/<table/,/<\/table>/p' | head -n 300)
fi

if [ -z "$TABLE" ]; then
    echo "Table A not found with any method. Keeping existing data."
    echo "Saving HTML snippet for debugging..."
    echo "$HTML" | head -n 50
    exit 0
fi

echo "Table found! Extracting data..."

# Extract report month and year from header
# Look for pattern like "Dec.<br />2025" or "Dec. 2025" in headers
MONTH_HEADER=$(echo "$TABLE" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.[^<]*<br\s*/>\s*20[0-9]{2}' | tail -1)

if [ -z "$MONTH_HEADER" ]; then
    # Try without <br/> tag
    MONTH_HEADER=$(echo "$TABLE" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.\s*20[0-9]{2}' | tail -1)
fi

# Extract month and year
REPORT_MONTH=$(echo "$MONTH_HEADER" | grep -oP '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.' | sed 's/\.$//')
REPORT_YEAR=$(echo "$MONTH_HEADER" | grep -oP '20[0-9]{2}')

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

if [ -z "$REPORT_MONTH" ] || [ -z "$REPORT_YEAR" ]; then
    FULL_MONTH="Latest Month"
fi

echo "Report month: $FULL_MONTH"

# Function to extract values for a specific category
extract_category_data() {
    local search_pattern="$1"
    local display_name="$2"
    
    # Try multiple patterns to find the row
    local row=""
    
    # Pattern 1: Look for exact match in <p> tags
    row=$(echo "$TABLE" | grep -i "<p[^>]*>$search_pattern</p>" | head -1)
    
    # Pattern 2: Look for pattern in <th> tags
    if [ -z "$row" ]; then
        row=$(echo "$TABLE" | grep -i "<th[^>]*>[^<]*$search_pattern" | head -1)
    fi
    
    # Pattern 3: Simple grep for the pattern
    if [ -z "$row" ]; then
        row=$(echo "$TABLE" | grep -i "$search_pattern" | grep '<td' | head -1)
    fi
    
    if [ -z "$row" ]; then
        echo "  $display_name: NOT FOUND (pattern: $search_pattern)"
        # Use default values
        JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: 0.0, annual: 0.0 },"
        return
    fi
    
    # Extract all values from <td> or <span class="datavalue"> tags
    local values=$(echo "$row" | grep -oP '(?<=<span class="datavalue">)[^<]+(?=</span>)')
    
    # If no datavalue spans found, try extracting from <td> directly
    if [ -z "$values" ]; then
        values=$(echo "$row" | grep -oP '(?<=<td[^>]*>)[^<]+(?=</td>)')
    fi
    
    # Get second-to-last value (monthly) and last value (annual)
    local monthly=$(echo "$values" | tail -2 | head -1 | tr -d ' ')
    local annual=$(echo "$values" | tail -1 | tr -d ' ')
    
    # Handle dash (-) as 0.0 and ensure we have numbers
    if [ "$monthly" = "-" ] || [ -z "$monthly" ]; then
        monthly="0.0"
    fi
    if [ "$annual" = "-" ] || [ -z "$annual" ]; then
        annual="0.0"
    fi
    
    echo "  $display_name: monthly=$monthly, annual=$annual"
    
    # Add to JSON
    JSON_DATA="${JSON_DATA}
        '${display_name}': { monthly: ${monthly}, annual: ${annual} },"
}

# Initialize JSON object
JSON_DATA="{"

# Extract data for each category
extract_category_data "All items" "All Items"
extract_category_data "Food[^<]*</p>" "Food"
extract_category_data "Food at home" "Food at Home"
extract_category_data "Food away from home" "Food Away from Home"
extract_category_data "Gasoline.*all types" "Gasoline"
extract_category_data "Energy services" "Energy Services"
extract_category_data "New vehicles" "New Vehicles"
extract_category_data "Used cars and trucks" "Used Cars and Trucks"
extract_category_data "Apparel[^<]*</p>" "Apparel"
extract_category_data "Shelter[^<]*</p>" "Shelter"
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
