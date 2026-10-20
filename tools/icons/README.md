# VI icons

The toolkit's icons were drawn in LabVIEW's icon editor with the Windows raster
font **Small Fonts** at 7 px. `New-VIIcon.ps1` draws a 32x32 PNG in exactly that
style, so a new VI gets an icon that matches the existing ones pixel for pixel.

| Style | Banner | Used for |
|---|---|---|
| `Toolkit` | green, "MCP" | VIs of `MCP Server.lvlib` |
| `Class` | yellow, `-BannerText` | member VIs of a class, e.g. "SSE" for `MCP SSE Response.lvclass` |
| `Test` | red, empty | VIs of `MCP Server tests.lvlib` |

The body holds one to three lines of capitals, each at most 28 px wide (about
six letters), centred.

```powershell
.\tools\icons\New-VIIcon.ps1 -Lines 'REPORT','PROGR' -OutFile "$env:TEMP\icon.png" -Show
.\tools\icons\New-VIIcon.ps1 -Lines 'NEXT','SEGMT' -Style Class -BannerText 'SSE' -OutFile "$env:TEMP\icon.png"
.\tools\icons\New-VIIcon.ps1 -Lines 'TEST','ELICIT' -Style Test -OutFile "$env:TEMP\icon.png"
```

## Why a script

- GDI+ (`System.Drawing.Font`) cannot use raster fonts and silently substitutes
  another font, so the script draws the text through GDI.
- The line drawing of the labview-mcp tool `lvai_set_vi_icon` uses a bitmap font
  of its own, which looks different from the existing icons. Give that tool the
  PNG from this script (`iconImagePath`) instead.

## Applying an icon

`lvai_set_vi_icon` opens the VI in LabVIEW's main application instance and saves
it there, which writes the LabVIEW 2026 format. To keep the 20.0 format, set the
icon in the application instance of `src\LabVIEW MCP Server SDK.lvproj` (its
`SaveVersion` is 20.0). The project must be open in the IDE. Then:
`Open VI Reference` in the project's application, `Set VI Icon from File`,
`Save.Instrument`. Check the saved format afterwards.
