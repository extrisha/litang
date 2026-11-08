$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$graphPath = Join-Path $repoRoot 'assets\map\walk_graph.json'
[xml]$osm = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'usst_516_raw.osm') -Raw
$graph = Get-Content -LiteralPath $graphPath -Raw | ConvertFrom-Json -AsHashtable
$nodes = [Collections.Generic.List[object]]::new()
$edges = [Collections.Generic.List[object]]::new()
foreach ($node in $graph.nodes) { $nodes.Add($node) }
foreach ($edge in $graph.edges) { $edges.Add($edge) }

# 思伊堂原接点是楼栋角点。原始 OSM 明确包含两段通路；不按最近距离猜连线。
$segments = @(
    @{ way = '155592168'; from = '1679908011'; to = '1679908010'; kind = 'steps'; factor = 1.25 },
    @{ way = '155592166'; from = '1679908010'; to = '1679908008'; kind = 'footway'; factor = 1.0 }
)
function Get-GraphNode([string]$osmId) {
    $source = @($osm.osm.node | Where-Object { $_.id -eq $osmId })
    if ($source.Count -ne 1) { throw "Missing OSM node: $osmId" }
    $lat = [double]::Parse($source[0].lat, [Globalization.CultureInfo]::InvariantCulture)
    $lon = [double]::Parse($source[0].lon, [Globalization.CultureInfo]::InvariantCulture)
    for ($index = 0; $index -lt $nodes.Count; $index++) {
        if ([Math]::Abs($nodes[$index][0] - $lat) -lt 0.00000005 -and
            [Math]::Abs($nodes[$index][1] - $lon) -lt 0.00000005) { return $index }
    }
    $nodes.Add(@($lat, $lon))
    return $nodes.Count - 1
}
foreach ($segment in $segments) {
    $way = @($osm.osm.way | Where-Object { $_.id -eq $segment.way })
    if ($way.Count -ne 1 -or $way[0].nd.Count -ne 2 -or
        $way[0].nd[0].ref -ne $segment.from -or $way[0].nd[1].ref -ne $segment.to -or
        -not ($way[0].tag | Where-Object { $_.k -eq 'highway' -and $_.v -eq $segment.kind }) -or
        -not ($way[0].tag | Where-Object { $_.k -eq 'access' -and $_.v -eq 'permissive' })) {
        throw "OSM evidence changed; inspect way $($segment.way) before repairing."
    }
    $a = Get-GraphNode $segment.from
    $b = Get-GraphNode $segment.to
    $exists = $edges | Where-Object { ($_[0] -eq $a -and $_[1] -eq $b) -or ($_[0] -eq $b -and $_[1] -eq $a) }
    if (-not $exists) {
        $radians = [Math]::PI / 180
        $dLat = ($nodes[$b][0] - $nodes[$a][0]) * $radians
        $dLon = ($nodes[$b][1] - $nodes[$a][1]) * $radians
        $h = [Math]::Pow([Math]::Sin($dLat / 2), 2) +
             [Math]::Cos($nodes[$a][0] * $radians) * [Math]::Cos($nodes[$b][0] * $radians) *
             [Math]::Pow([Math]::Sin($dLon / 2), 2)
        $meters = 6371000 * 2 * [Math]::Atan2([Math]::Sqrt($h), [Math]::Sqrt(1 - $h))
        $edges.Add(@($a, $b, [Math]::Round($meters * $segment.factor, 2)))
    }
}
$graph.nodes = $nodes.ToArray()
$graph.edges = $edges.ToArray()
$graph.meta.nodes = $nodes.Count
$graph.meta.edges = $edges.Count
$graph.meta.connectorRepair = @{
    source = 'tools/map/usst_516_raw.osm'
    ways = @('155592168', '155592166')
    note = 'Restored omitted steps and footway connecting the fourth dormitory to the existing service road; current field access remains to be verified.'
}
[IO.File]::WriteAllText($graphPath, ($graph | ConvertTo-Json -Depth 30 -Compress), [Text.UTF8Encoding]::new($false))
Write-Output "Graph updated from OSM evidence: $($nodes.Count) nodes, $($edges.Count) edges."
