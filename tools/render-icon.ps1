# Renders assets/claudecode-color.svg -> assets/claude-icon.png using WPF (built into Windows).
# Run once to regenerate the toast app-logo. No external dependencies.
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$here = Split-Path -Parent $PSCommandPath
$out  = Join-Path (Split-Path -Parent $here) 'assets\claude-icon.png'

# Single-path Claude Code mark. 'F0' = EvenOdd fill rule (keeps the two cutout squares hollow).
$pathData = 'F0 M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z'
$geo   = [System.Windows.Media.Geometry]::Parse($pathData)
$brush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0xD9, 0x77, 0x57))

$size = 256
$pad  = 36
$scale = ($size - 2 * $pad) / 24.0

$visual = [System.Windows.Media.DrawingVisual]::new()
$dc = $visual.RenderOpen()
$tg = [System.Windows.Media.TransformGroup]::new()
$tg.Children.Add([System.Windows.Media.ScaleTransform]::new($scale, $scale))
$tg.Children.Add([System.Windows.Media.TranslateTransform]::new($pad, $pad))
$dc.PushTransform($tg)
$dc.DrawGeometry($brush, $null, $geo)
$dc.Pop()
$dc.Close()

$rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new($size, $size, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
$rtb.Render($visual)
$enc = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
$enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
$fs = [System.IO.File]::Create($out)
$enc.Save($fs)
$fs.Close()
Write-Output "Wrote $out ($size x $size)"
