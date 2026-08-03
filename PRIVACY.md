# Privacy

The app collects nothing and sends nothing. The website that distributes it does measure its
traffic, which is described under [The website](#the-website).

## No network access

There is no networking code in the app. Not disabled, not opt-in — absent. You can check:

```bash
grep -rE "URLSession|URLRequest|NWConnection|CFStream|socket\(" Sources/
```

That returns nothing, and it is part of what the build is reviewed against. There is no
account, no telemetry, no crash reporting, no update check, and no analytics. This holds for
the app only; the website that distributes it is described under
[The website](#the-website).

## What the app can see

Trimshot needs macOS **Screen Recording** permission, because capturing the screen is what
it does. With that permission it can read the contents of your displays. It uses that to:

- grab a full-resolution still of each display when you press the shortcut, held in memory
  for the length of one capture and released when the overlay closes;
- read individual pixels from that still for the magnifier and the colour picker;
- recognise text with Apple's on-device Vision framework when you use OCR.

## No audio, despite what macOS asks for

macOS calls the permission **Screen & System Audio Recording**, and its periodic reminder
mentions audio, because one grant covers both. Trimshot captures **still images only**. It
never enables audio capture and has no way to record sound:

```bash
grep -rn "capturesAudio" Sources/
```

That returns nothing.

## Where your captures go

Only where you send them:

- the clipboard, when you copy;
- a folder you chose, when you save — `~/Desktop` unless you change it in Settings.

Nothing is written anywhere else. Trimshot keeps no history of past captures.

## What is stored on disk

Preferences only, in the standard macOS location
`~/Library/Preferences/com.thienho.trimshot.plist`: your shortcut, save folder, image
format, and two boolean settings. No capture data.

## OCR

Text recognition runs entirely on your Mac through Apple's Vision framework. Images are
never uploaded to perform it.

## The website

[trimshot.vercel.app](https://trimshot.vercel.app) is a static page on Vercel, and unlike the
app it does measure its traffic. It loads Google Tag Manager and Google Analytics, which set a
`_ga` cookie and record page views, how far down the page you scroll, clicks on the download
link and clicks through to GitHub, alongside coarse details such as country, browser and
referring site. That is there to answer one question — whether anyone is finding Trimshot —
and Google's handling of it falls under
[Google's privacy policy](https://policies.google.com/privacy). No advertising or remarketing
tags are loaded.

The host, Vercel, keeps standard server-side request logs that include IP addresses, as any web
host does; see [Vercel's privacy policy](https://vercel.com/legal/privacy-policy). Nothing
beyond this is collected. None of it reaches the app, which still sends nothing at all, and
none of it is combined with anything else.

To opt out, block the scripts with your browser's tracking protection or a content blocker, or
install Google's [opt-out add-on](https://tools.google.com/dlpage/gaoptout).

## Contact

Questions or corrections: open an issue at
<https://github.com/anhthienonline/trimshot/issues>.

---

*Last updated: 3 August 2026.*
