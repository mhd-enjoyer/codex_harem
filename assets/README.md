# App icon

`app-icon.png` is the full-color master artwork generated with Imagegen from the user's white-haired, horned anime character reference. Its design reference is [zipzippipe](https://github.com/zipzippipe).

`./scripts/build-icon.sh` creates ten standard and Retina PNG representations and a native PNG-backed ICNS container under `.build/`. The delivery mask provides a consistent rounded tile and transparent margin. `./scripts/package.sh` embeds `AppIcon.icns` in the app's Resources directory and declares it with `CFBundleIconFile`.

The small monochrome menu-bar icon remains a separate code-drawn template in `Sources/CodexHarem/MenuBarIcon.swift`.
