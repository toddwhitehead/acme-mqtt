# Generate SAS token for Event Grid MQTT client
# Uses namespace shared access keys via REST API (az cli eventgrid extension has a pip install bug)

$resourceGroup = "sandpit-todd"
$namespaceName = "acme-mqtt-dev-egns"
$clientName = "mqtt_proxy"
$expiryUtc = "2026-12-31T23:59:59Z"

# Get namespace keys via ARM REST API
$subscriptionId = (az account show --query id -o tsv)
$token = az account get-access-token --query accessToken -o tsv

$keysUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.EventGrid/namespaces/$namespaceName/listKeys?api-version=2024-06-01-preview"
$keys = Invoke-RestMethod -Uri $keysUri -Method POST -Headers @{
    Authorization  = "Bearer $token"
    "Content-Type" = "application/json"
}

$sharedKey = $keys.key1

# Build SAS token
$encodedResource = [System.Web.HttpUtility]::UrlEncode($namespaceName)
$expiryEpoch = [long](([DateTime]::Parse($expiryUtc).ToUniversalTime() - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds)

$stringToSign = "$encodedResource`n$expiryEpoch"
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [Convert]::FromBase64String($sharedKey)
$signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))
$encodedSignature = [System.Web.HttpUtility]::UrlEncode($signature)

$sasToken = "SharedAccessSignature sr=$encodedResource&sig=$encodedSignature&se=$expiryEpoch&skn=key1"

Write-Host "`nSAS Token:" -ForegroundColor Green
Write-Host $sasToken
Write-Host "`nMQTT Connection Details:" -ForegroundColor Green
Write-Host "  Username: $clientName"
Write-Host "  Password: $sasToken"