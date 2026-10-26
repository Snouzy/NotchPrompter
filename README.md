> **Fork personnel (Snouzy) : mode studio.** Ce fork ajoute un mode studio relié à video-studio : le bouton « Lire au prompteur » ouvre `notchprompter://open?server=…&short=…&items=…`, le prompteur affiche les passages Face cam un par un sous l'encoche, filme chaque passage (caméra du Mac ou iPhone) et renvoie la prise au studio avec les temps de chaque essai. Code dans `notch-prompter/Studio/`. Construire : `xcodegen generate` puis `xcodebuild -scheme NotchPrompter test`. Bout à bout : `node scripts/e2e-studio.mjs`. Usage personnel et non commercial, selon la licence d'origine.



<img width="128" height="128" alt="logo" src="https://github.com/user-attachments/assets/e8429fed-37be-427c-b7ab-ae0ad7537983" />


# NotchPrompter for macOS

Super simple-to-use, always-on-top floating text prompter for macOS.
Perfect for quick videos or keeping important text visible while you work.

<a href="https://apps.apple.com/pl/app/notchprompter/id6760967658?mt=12">
  <img src="download.svg" alt="Download on the Mac App Store" width="250">
</a>

## Features
- Always on top
- **Not visible on screen recording apps**
- Voice activation
- Minimalist design
- Quick options
- Customizable speed, size, font style
- Multi-monitor support
- [Multi-language support](https://simplelocalize.io/suggestions/?id=f1f11f9305dc44a2872b6a154dea6edc)
- Custom position

## Screenshot

<img width="1465" height="780" alt="screen-frame-no-text" src="https://github.com/user-attachments/assets/8fcca82b-2628-4fcf-8b64-28e19474703b" />

## Translations
Translations are made via DeepL, so they might be incorrect in some places, but feel free to [suggest better translations!](https://simplelocalize.io/suggestions/?id=f1f11f9305dc44a2872b6a154dea6edc).


## Star History

[![Star History Chart](https://star-history.dera.page/svg?repos=jpomykala/NotchPrompter&type=date&legend=top-left)](https://star-history.dera.page/#jpomykala/NotchPrompter&type=date&legend=top-left)
