# One existing icon for Android and Google Play

The canonical design remains `assets/icon.svg`: white **99.9**, yellow **%**, blue progress bar, original dark background and border. Do not substitute newly designed Store artwork.

`icon-512.png` is its Google Play export for **every language and custom listing**. Android uses raster exports of that same source, including explicit adaptive layers. The lettering is baked into PNG files so Godot's SVG import cannot drop the text. Adaptive padding keeps the percentage and progress bar visible under launcher masks.

Generate using `python3 scripts/export_launcher_icons.py` (Inkscape). Validate using `python3 scripts/check_launcher_icons.py` (Pillow). Compare the launcher from the final signed AAB against this Store asset before resubmission. Existing upload signing keys and application ID remain unchanged.

Android launcher reference: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html#providing-launcher-icons
