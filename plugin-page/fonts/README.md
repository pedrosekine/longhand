# The page's face

Adwaita Sans, GNOME's interface face (Inter's design), in the six cuts the
page draws with: Regular, Italic, SemiBold, SemiBold Italic, Bold, Bold
Italic. The page loads them only on a machine that has no Adwaita Sans of
its own (Windows, a Linux without GNOME's fonts); one that has it uses its
own (`Page.qml`, `bundledFace`).

They are fixed cuts made from GNOME's variable files, adwaita-fonts 51.0 as
Arch packages it (`/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf` and
`-Italic.ttf`), by `tools/font-cuts.py`:

```
python tools/font-cuts.py /usr/share/fonts/Adwaita plugin-page/fonts
```

(it needs `fonttools`). Why not the variable files themselves: Windows' font
engine names a variable font's cuts "Text Bold", "Text SemiBold", so a
heading that asks for "Bold" by name was drawn in the Regular.

Licensed under the SIL Open Font License 1.1, which declares no Reserved
Font Name, so the cuts keep the name: `OFL.txt`.
