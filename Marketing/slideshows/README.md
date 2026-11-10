# Gainlapse slideshow maker

Free, local replacement for the slideshow-building part of Volume. Describe a slideshow in a small JSON file, run one command, get branded slide images (and a zip) ready to post.

## Setup (once)

You need [Node.js](https://nodejs.org) 18 or newer. Then, from this folder:

```bash
npm run setup
```

## Make a slideshow

```bash
node make.js examples/progress-pic.json
```

The slides land in `out/progress-pic/` (`slide-01.jpg`, `slide-02.jpg`, …), with `out/progress-pic.zip` and `caption.txt` next to them. You can pass several files at once: `node make.js examples/*.json`.

Headlines shrink automatically to fit their space, so long text never runs into anything else.

## The slideshow file

```json
{
  "format": "tiktok",
  "caption": "Your post caption #gymtok",
  "slides": [ { "type": "cover", "...": "..." } ]
}
```

- `format`: `"tiktok"` (1080 × 1920) or `"instagram"` (1080 × 1350).
- Wrap words in `[[double brackets]]` to make them orange.
- A blank line (`\n\n`) in body text starts a new paragraph. A single `\n` breaks the line.
- Image paths are relative to the JSON file, or a full `https://` link.

### Slide types

| `type` | Fields | Looks like |
|---|---|---|
| `cover` | `photo`, `headline`, `sub`, optional `focus` (0–100, where the photo crop looks) | Full photo, dark fade, big headline at the bottom |
| `tip` | `heading`, `body`, optional `number` (defaults to the slide's position: 01, 02, …) | Big orange number, heading, paragraphs |
| `statement` | `headline`, optional `sub`, `stamp`, `background` (`"dark"`, default orange) | One huge line on orange or dark |
| `app` | `heading`, `body`, `screenshot` | An app screenshot in a phone frame |
| `cta` | `headline` (defaults to "Search Gainlapse on the App Store"), `body`, `pill` | App icon, headline, orange pill |

Any slide can take `size` to set the largest headline size before auto-fit.

App screenshots live in `../screenshots/`. Stock photos: [Pexels](https://www.pexels.com) is free; copy the image link into `photo`.

## What this doesn't do

It makes the slides. It doesn't find trending formats or post to TikTok for you. Post by hand from your phone.
