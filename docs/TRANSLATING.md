# Translating Calma

Thanks for helping make Calma available in more languages. You don't need Xcode or any Swift knowledge, just a text editor.

## How localisation works

Calma uses classic `.strings` files. The **key** is the English text exactly as it appears in the app, and the **value** is your translation:

```
/* Menu bar popover: label under the big percentage */
"Charge limit" = "चार्ज सीमा";
```

The files live in:

```
Resources/Localization/
├── en.lproj/Localizable.strings   ← source of truth (English)
└── hi.lproj/Localizable.strings   ← Hindi (partial)
```

Strings that aren't translated fall back to English, so a partial translation is perfectly fine to submit.

## Adding a new language

1. Find your language code, such as `gu` (Gujarati), `de` (German), `es` (Spanish), `pt-BR` or `zh-Hans`.
2. Copy the English file:
   ```sh
   mkdir -p Resources/Localization/gu.lproj
   cp Resources/Localization/en.lproj/Localizable.strings Resources/Localization/gu.lproj/
   ```
3. Translate the **right-hand side** of each line. Don't change the left-hand keys.
4. Add your code to `CFBundleLocalizations` in `Resources/Info.plist`:
   ```xml
   <key>CFBundleLocalizations</key>
   <array>
       <string>en</string>
       <string>hi</string>
       <string>gu</string>
   </array>
   ```
5. Open a pull request titled `i18n: add Gujarati translation`.

## Rules for translators

- **Keep placeholders exactly as written:** `%@`, `%d`, `%lld`, `%.1f` and `%%` (a literal percent sign). If your grammar needs a different order, use positional forms such as `%1$@` and `%2$lld`.
- **Keep the product name "Calma"** untranslated.
- **Keep feature names consistent** throughout the file (for example, always use the same word for "Drift Range").
- **Keep it short.** The menu bar popover is narrow, so aim for about the length of the English text.
- **Don't translate** SMC key names (`CHTE`), commands (`calma limit 80`) or file paths.
- Every line must end with a semicolon. Escape quotes inside strings as `\"`.

## Checking your file

Validate the syntax before opening a PR:

```sh
plutil -lint Resources/Localization/gu.lproj/Localizable.strings
```

To see your language in the app, build it (`Scripts/build-app.sh`), then run it in that language without changing your system settings:

```sh
dist/Calma.app/Contents/MacOS/Calma -AppleLanguages "(gu)"
```

## Updating an existing translation

When new English strings are added, missing keys show in English until someone translates them. To list keys missing from your language:

```sh
diff <(grep -o '^"[^"]*"' Resources/Localization/en.lproj/Localizable.strings | sort) \
     <(grep -o '^"[^"]*"' Resources/Localization/gu.lproj/Localizable.strings | sort)
```
