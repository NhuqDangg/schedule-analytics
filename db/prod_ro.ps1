# Chay psql toi PROD o che do CHI DOC. Khong in connection string.
# Doc PROD_DATABASE_URL tu file .env o thu muc goc repo. File nay KHONG chua mat khau.
# Dung:  .\db\prod_ro.ps1 -Sql "SELECT 1"
#        .\db\prod_ro.ps1 -File cau_truy_van.sql
param([string]$Sql, [string]$File)

$envFile = Join-Path $PSScriptRoot "..\.env"
$line = Select-String -Path $envFile -Pattern '^PROD_DATABASE_URL=(.+)$' | Select-Object -First 1
if (-not $line) { Write-Error "Khong thay PROD_DATABASE_URL trong .env"; exit 2 }
$url = $line.Matches[0].Groups[1].Value.Trim()

# Chan cau SQL co y tat che do chi doc (kiem tra tren may, khong gui len server).
$body = if ($File) { Get-Content $File -Raw } else { $Sql }
if ($body -match "(?i)read_only\s*(=|to)\s*'?(off|false|0)|read\s+write|set_config\s*\(\s*'(default_)?transaction_read_only'") {
  Write-Error "Tu choi: cau SQL co y tat che do chi doc."; exit 3
}

# Supabase pooler bo qua PGOPTIONS (tham so luc mo ket noi), nen phai SET ngay trong phien,
# la lenh DAU TIEN. psql chay cac -c / -f lien tiep trong cung 1 phien.
$env:PGCONNECT_TIMEOUT = "15"
$env:PGCLIENTENCODING = "UTF8"
$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
$psqlArgs = @("-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", $url,
              "-c", "SET default_transaction_read_only = on")
if ($File) { $psqlArgs += @("-f", $File) } else { $psqlArgs += @("-c", $Sql) }
& $psql @psqlArgs
exit $LASTEXITCODE
