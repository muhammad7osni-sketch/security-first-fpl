# Apply schema.sql to Supabase project
# Requires Supabase CLI to be installed and logged in

param(
    [string]$ProjectRef = ""
)

Write-Host "SquadIQ - Apply Database Schema" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if schema.sql exists
if (-not (Test-Path "supabase/schema.sql")) {
    Write-Host "Error: supabase/schema.sql not found!" -ForegroundColor Red
    exit 1
}

# Check if Supabase CLI is installed
try {
    $version = supabase --version 2>&1
    Write-Host "✓ Supabase CLI found: $version" -ForegroundColor Green
} catch {
    Write-Host "✗ Supabase CLI not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install it with:" -ForegroundColor Yellow
    Write-Host "  winget install --id Supabase.CLI" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or use the manual method:" -ForegroundColor Yellow
    Write-Host "  1. Open https://supabase.com/dashboard" -ForegroundColor Cyan
    Write-Host "  2. Go to SQL Editor" -ForegroundColor Cyan
    Write-Host "  3. Copy/paste supabase/schema.sql" -ForegroundColor Cyan
    Write-Host "  4. Click Run" -ForegroundColor Cyan
    exit 1
}

# Get project ref if not provided
if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
    Write-Host "Enter your Supabase project reference:" -ForegroundColor Yellow
    Write-Host "(Find it in: Project Settings → General → Reference ID)" -ForegroundColor Gray
    $ProjectRef = Read-Host "Project Ref"
}

if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
    Write-Host "Error: Project reference is required!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Linking to project: $ProjectRef" -ForegroundColor Cyan

try {
    supabase link --project-ref $ProjectRef
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error linking to project!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Project linked successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "Applying schema..." -ForegroundColor Cyan
    
    # Apply schema using psql
    $schemaContent = Get-Content "supabase/schema.sql" -Raw
    $schemaContent | supabase db execute
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✓ Schema applied successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Copy .env.example to .env" -ForegroundColor White
        Write-Host "  2. Fill in your Supabase URL and anon key" -ForegroundColor White
        Write-Host "  3. Run: .\run.ps1" -ForegroundColor White
    } else {
        Write-Host ""
        Write-Host "✗ Failed to apply schema!" -ForegroundColor Red
        Write-Host "Check the error messages above" -ForegroundColor Yellow
        exit 1
    }
    
} catch {
    Write-Host "✗ Error: $_" -ForegroundColor Red
    exit 1
}
