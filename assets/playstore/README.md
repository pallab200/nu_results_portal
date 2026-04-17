Placeholder graphics and screenshot template

Files created:
- assets/playstore/icon.svg — 512×512 SVG placeholder for app icon (export to PNG for Play Store)
- assets/playstore/feature.svg — 1024×500 SVG placeholder for feature graphic
- assets/playstore/screenshot-template.html — phone screenshot mockup template (open in browser and capture at desired resolution)

How to export to PNG (recommended):

Option A — Use a vector editor (Inkscape / Illustrator):
1. Open the SVG file.
2. Export as PNG at required size:
   - Icon: 512×512 px
   - Feature graphic: 1024×500 px
3. Save as PNG and compress if needed (<= file size limits).

Option B — Use command line (Inkscape) on Windows (PowerShell):

```powershell
# Install Inkscape and ensure it's in PATH, then:
inkscape assets/playstore/icon.svg --export-type=png --export-width=512 --export-height=512 --export-filename=assets/playstore/icon.png
inkscape assets/playstore/feature.svg --export-type=png --export-width=1024 --export-height=500 --export-filename=assets/playstore/feature.png
```

Option C — For the screenshot template:
1. Open `assets/playstore/screenshot-template.html` in your browser.
2. Resize the browser to match target screenshot resolution (e.g., 1080×1920) or use DevTools to set device dimensions.
3. Capture a screenshot (OS-level screenshot or DevTools capture) and save as PNG.

Notes:
- Play Console requires PNG/JPEG assets; these SVGs are placeholders you should replace with branded artwork before publishing.
- If you want, I can export PNG files here as base64-encoded images and write them to disk. Tell me which PNGs and sizes you want me to generate.