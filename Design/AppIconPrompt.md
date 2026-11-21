# Todos app icon

A calm, grown-up mark: a flat matte ink background, a thin off-white checkbox outline, and a single brass checkmark that breaks out of the box towards the top right. There is no glow, gradient lighting, or glass; the only tonal change is a very faint shift from top to bottom of the background. It stays legible at small home-screen sizes.

The icon is drawn by `Design/make-icon.swift`, so it can be regenerated or tweaked (colours and geometry are at the top of the script) instead of re-prompting an image tool:

```sh
xcrun swiftc Design/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
```

It writes `todos/Assets.xcassets/AppIcon.appiconset/AppIcon.png`: 1024 x 1024, opaque, full bleed with square corners. iOS applies the corner mask and derives its appearance treatments from this single universal icon.

| Part | Colour |
| --- | --- |
| Background | ink slate, `#222C36` fading to `#182029` |
| Checkbox | warm off-white, `#ECE7DD` |
| Check | muted brass, `#C9A66B` |

The first version was a glowing blue glass checkmark. It was replaced because it looked too showy for a quiet app.
