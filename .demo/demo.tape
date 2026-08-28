Output .demo/demo.gif

Set Shell bash
Set FontSize 17
Set Width 1180
Set Height 660
Set Padding 22
Set Framerate 20
Set Theme "Catppuccin Mocha"

Hide
Type "export PS1='$ '" Enter
Type "clear" Enter
Show

Sleep 700ms
Type "# System audio in the built-in screen recorder." Enter
Sleep 900ms
Type "screend status" Enter
Sleep 2600ms

Type "# Now play something and watch the meter." Enter
Sleep 700ms
Type "afplay .demo/demo-audio.wav &" Enter
Sleep 400ms
Type "screend monitor" Enter
Sleep 7500ms
Ctrl+C
Sleep 900ms

Type "clear" Enter
Sleep 300ms
Type "# Audio settings after recording — unchanged." Enter
Sleep 700ms
Type "screend status" Enter
Sleep 3200ms
