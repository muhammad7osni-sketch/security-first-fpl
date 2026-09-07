# Deploy Supabase Edge Functions

Write-Host "SquadIQ - Deploy Edge Functions" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if Supabase CLI is installed
try {
    $version = supabase --version 2>&1
    Write-Host "✓ Supabase CLI found: $version" -ForegroundColor Green
} catch {
    Write-Host "✗ Supabase CLI not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install it with:" -ForegroundColor Yellow
    Write-Host "  winget install --id Supabase.CLI" -ForegroundColor Cyan
    exit 1
}

Write-Host ""
Write-Host "Deploying FPL Proxy (required for web)..." -ForegroundColor Cyan
supabase functions deploy fpl-proxy

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ FPL Proxy deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Test it at:" -ForegroundColor Cyan
    Write-Host "  https://psgqhiqcxnupzbbunydx.supabase.co/functions/v1/fpl-proxy?path=/bootstrap-static/" -ForegroundColor Gray
} else {
    Write-Host "✗ FPL Proxy deployment failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure you're logged in and linked:" -ForegroundColor Yellow
    Write-Host "  supabase login" -ForegroundColor Cyan
    Write-Host "  supabase link --project-ref psgqhiqcxnupzbbunydx" -ForegroundColor Cyan
    exit 1
}

Write-Host ""
Write-Host "Deploy AI Assistant too? (y/N)" -ForegroundColor Yellow
$deploy_ai = Read-Host

if ($deploy_ai -eq 'y' -or $deploy_ai -eq 'Y') {
    Write-Host ""
    Write-Host "Deploying AI Assistant..." -ForegroundColor Cyan
    supabase functions deploy ai-assistant
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ AI Assistant deployed successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "⚠️  Don't forget to set your Anthropic API key:" -ForegroundColor Yellow
        Write-Host "  supabase secrets set ANTHROPIC_API_KEY=sk-ant-..." -ForegroundColor Cyan
    } else {
        Write-Host "✗ AI Assistant deployment failed!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "✓ Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart your Flutter app (hot reload won't work)" -ForegroundColor White
Write-Host "  2. Try linking your FPL account again" -ForegroundColor White
Write-Host "  3. CORS errors should be gone!" -ForegroundColor White
