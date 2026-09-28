param([string]$Source = 'D:\resiclasai\testing')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$target = Join-Path $project 'assets\bench'
$annotations = Get-Content -LiteralPath (Join-Path $Source 'info.labels') -Raw | ConvertFrom-Json
$labels = Get-Content -LiteralPath (Join-Path $project 'assets\labels.txt')
New-Item -ItemType Directory -Path $target -Force | Out-Null
$samples = @()
foreach ($label in $labels) {
    $label = $label.Trim()
    $entries = @($annotations.files | Where-Object { $_.label.label -eq $label } | Sort-Object path)
    if ($entries.Count -lt 5) { throw "Menos de cinco muestras para $label" }
    for ($i = 0; $i -lt 5; $i++) {
        # Deterministic, spread across the sorted dataset rather than adjacent bursts.
        $entry = $entries[[Math]::Floor($i * ($entries.Count - 1) / 4)]
        $sourceFile = [IO.Path]::GetFullPath((Join-Path $Source $entry.path))
        $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\') + '\'
        if (-not $sourceFile.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta fuera del dataset' }
        $name = "${label}_$($i + 1).jpg"
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $target $name)
        $samples += [ordered]@{ asset = "assets/bench/$name"; label = $label; source = $entry.path }
    }
}
$manifest = [ordered]@{ version = 1; selection = '5 por clase, espaciado determinista por nombre'; samples = $samples }
[IO.File]::WriteAllText((Join-Path $target 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
Write-Output "Bench: $($samples.Count) muestras extraidas en $target"
