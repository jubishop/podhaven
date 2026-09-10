---
status: current
---

# Universal Links

PodHaven accepts HTTPS podcast and episode links on `artisanalsoftware.com`
and `www.artisanalsoftware.com`. Both hosts are in the app's Associated Domains
entitlement. SwiftUI delivers Universal Links through the existing `onOpenURL`
handler, which routes them to `ShareService`.

The supported paths are `/podhaven/podcast`, `/podhaven/episode`,
`/podhaven/open/podcast`, and `/podhaven/open/episode`. Links carry `feedURL`,
an episode `guid` when applicable, and an optional `startTime` in seconds.
The app validates the domain, path, feed URL, and required query values before
opening a podcast or episode. Existing custom-scheme links remain supported.

The website's association file lists only the production app identifier,
`34TKMKM889.com.artisanalsoftware.PodHaven`. Development and test builds do not
take over public links. Only `applinks` is configured; the association does not
enable shared web credentials.

## Release order

1. Deploy the association file and fallback endpoints in the
   [website repository](https://github.com/jubishop/artisanalsoftware.com).
2. Enable Associated Domains for the production app identifier in Apple's
   developer account. Regenerate signing profiles when prompted. Xcode's
   automatic signing can update them during a signed build.
3. Distribute a build containing this entitlement and URL handling. Test the
   production app through TestFlight on a physical device, without installing
   a development build on the user's iPhone.
4. After the compatible build is available in the App Store, set
   `PODHAVEN_UNIVERSAL_LINKS_ENABLED=true` on the Railway website service and
   redeploy it.

The website flag controls its buttons. With the flag disabled, they keep using
`podhaven://`, so existing app versions still open correctly. When enabled,
each button points to `/podhaven/open/podcast` or `/podhaven/open/episode` on
the other associated hostname. Safari can then open the app instead of treating
the tap as navigation within the current host.

If the operating system does not open the app, the `/podhaven/open/` endpoints
redirect to the App Store. Normal share URLs retain their web content fallback.

## Verification

- Both hosts must serve `/.well-known/apple-app-site-association` as JSON with
  HTTP 200 and no redirect. Apple's CDN must be able to retrieve the same JSON.
- On a compatible installed build, tap a podcast and timestamped episode link
  from Notes, then from each website hostname. Verify the destination and time.
- On a device without PodHaven, verify the open endpoints reach its App Store
  page and ordinary share URLs still show podcast or episode content.
- Check that marketing and guide URLs continue to open in the browser.

Apple caches associations. A cached response from before deployment can delay
activation. Browser preferences and third-party browser support also affect
whether a link opens the app.

See [Apple's troubleshooting guide](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links)
and [SwiftUI URL handling](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)).
