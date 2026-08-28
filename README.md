# RedRock IT website

Static site for [redrockit.com](https://www.redrockit.com/). No frameworks, no
runtime dependencies, no database. GitHub Pages serves the `.html` files in the
repository root exactly as they are.

## How it is put together

The root `.html` files are **generated output** - don't edit them directly, they get
overwritten. The sources live in `_src/`:

```
_src/partials/head.html    <head>, utility bar, header, mobile menu   (every page)
_src/partials/foot.html    footer, sticky call bar, back-to-top       (every page)
_src/partials/cta.html     the closing call-to-action band            (most pages)
_src/partials/trust.html   accreditation badges + capability chips
_src/pages/*.html          the <main> content of each page
_src/brand/                original logo and badge files as supplied
```

Rebuild after any change:

```powershell
pwsh -File build.ps1
```

That regenerates all 21 pages and rewrites `sitemap.xml`. It fails loudly on a
missing `META` block, an unknown `<!--INCLUDE:-->`, or an unsubstituted placeholder,
so a broken build won't ship silently.

### Page front matter

Every file in `_src/pages/` opens with a `META` block:

```html
<!--META
title:  Shown in the browser tab and as the search result headline
desc:   The description under that headline (aim for 120-158 characters)
nav:    services          optional - highlights that top-menu item
robots: noindex,follow    optional - defaults to index,follow
head:   <link ...>        optional - extra tags injected into <head>
-->
```

`<!--INCLUDE:cta-->` and `<!--INCLUDE:trust-->` pull in the shared blocks.
Structured data (JSON-LD) sits inline at the foot of each page source.

## Conventions

- **No inline styles.** Everything is a class in `assets/css/site.css`. A small set
  of `.u-*` spacing utilities exists for one-off adjustments.
- **Design tokens** are CSS custom properties at the top of the stylesheet - colour,
  spacing, radii, shadows, fonts. Change a brand colour in one place.
- **Icons are inline SVG.** No icon font, no sprite request.
- **Fonts are self-hosted** (`assets/fonts/`) and preloaded. The site makes no
  third-party requests apart from the embedded Microsoft Form on the contact page.
- **Images are WebP**, sized to their display size, with `width`/`height` set so the
  page doesn't reflow while loading.

## Deploying

1. Push to `main`.
2. **Settings → Pages** → Source: *Deploy from a branch*, branch `main`, folder `/ (root)`.

For the custom domain, set `www.redrockit.com` under **Settings → Pages → Custom
domain** (GitHub writes the `CNAME` file), then add a DNS record:

| Type  | Name | Value                  |
|-------|------|------------------------|
| CNAME | www  | `<username>.github.io` |

Enable **Enforce HTTPS** once the certificate is issued.

Links between pages are relative, so the site also works unchanged from a project
URL like `username.github.io/RRITSite/`. Only the canonical tags, Open Graph URLs,
`sitemap.xml` and `robots.txt` assume the real domain.

## Contact form

The contact page embeds a Microsoft Form. To change the questions, edit it in
Microsoft Forms - nothing on this site needs updating.

Microsoft Forms does not report its height to the parent page, so the iframe height
is set manually in `.ms-form` (`assets/css/site.css`). If you add or remove
questions, re-measure: too short gives an inner scrollbar, too tall leaves blank
space below the form.

## SEO

- Unique title, meta description and canonical URL per page, all within length limits
- JSON-LD: `Organization`, `LocalBusiness` (both offices), `Service`, `FAQPage`,
  `BreadcrumbList`, `ItemList`, `WebSite`
- `sitemap.xml` generated at build time; `robots.txt` allows the major AI crawlers
- `llms.txt` - a plain-text summary for AI assistants, including explicit notes that
  RedRock IT does not claim to make anyone HIPAA compliant and does not publish fixed
  pricing, so answer engines don't invent either
- 404 page is `noindex` and excluded from the sitemap

Deliberately **not** included: `aggregateRating` / `Review` markup. Google does not
allow self-serving review markup for your own business, and using it risks a
structured-data penalty. Reviews link out to the Google Business Profile instead.

## Still outstanding

- [ ] **Confirm the Microsoft Form is set to "Anyone can respond."** Work accounts
      default to organization-only, which silently blocks every prospect.
- [ ] **Remove the Number restriction on the Phone question** in Forms - it rejects
      `(801) 562-2300` and any other formatted number.
- [ ] **Verify the "15+ years" claim.** Inferred from a client review mentioning
      16 years; several pages use it.
- [ ] **Have the legal pages reviewed.** Privacy, Terms and Refund policies are
      drafted from supplied text plus standard clauses - not legal advice.
- [ ] **Swap the stock photography** for real photos of the team and offices. Keep
      the same filenames in `assets/img/` and nothing else needs to change.
- [ ] Add a founder bio and team photo to `about.html` - the main thing that page
      is still missing.
- [ ] Submit `sitemap.xml` in Google Search Console.

## Pages

```
index.html            Home
services.html         Services overview
  managed-it-services.html        Everyday IT Support
  endpoint-security.html          Cybersecurity (4TressCyber)
  microsoft-365.html              Email, Teams & Microsoft 365
  network-infrastructure.html     Wi-Fi & Networking
  servers-infrastructure.html     Servers & Computers
  backup-disaster-recovery.html   Backup & Recovery
industries.html       Industries overview (+ finance, healthcare, warehouse sections)
  pharmacy-it-support.html
  construction-it-support.html
  manufacturing-it-support.html
  property-management-it-support.html
pricing.html   about.html   faq.html   contact.html
privacy-policy.html   terms-conditions.html   refund-policy.html   404.html
```

File names stay keyword-friendly for search even where the visible wording is
plainer - `managed-it-services.html` is titled "Everyday IT Support" for readers but
still targets the phrase people actually search for.
