# SquadIQ Run Script
# Reads environment variables from .env file and runs the app

# Check if .env exists
if (-not (Test-Path ".env")) {
    Write-Host "Error: .env file not found!" -ForegroundColor Red
    Write-Host "Please copy .env.example to .env and fill in your Supabase credentials" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Cyan
    Write-Host "  Copy-Item .env.example .env"
    Write-Host "  # Then edit .env with your actual values"
    exit 1
}

# Read .env file and extract variables
$envVars = @{}
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+?)\s*=\s*(.+?)\s*$') {
        $key = $matches[1]
        $value = $matches[2]
        $envVars[$key] = $value
    }
}

# Check required variables
$required = @('SUPABASE_URL', 'SUPABASE_ANON_KEY')
$missing = @()
foreach ($var in $required) {
    if (-not $envVars[$var] -or $envVars[$var] -like '*your-*') {
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Error: Missing or incomplete environment variables:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Please edit .env and fill in your actual values" -ForegroundColor Cyan
    exit 1
}

# Build dart-define arguments
$defineArgs = @(
    "--dart-define=SUPABASE_URL=$($envVars['SUPABASE_URL'])",
    "--dart-define=SUPABASE_ANON_KEY=$($envVars['SUPABASE_ANON_KEY'])"
)

# Run the app
Write-Host "Starting SquadIQ..." -ForegroundColor Green
Write-Host "Supabase URL: $($envVars['SUPABASE_URL'])" -ForegroundColor Cyan
flutter run @defineArgs
