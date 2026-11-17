# Bluprints Print Service — iOS

Version 1.0 source project · iOS 16+ · SwiftUI + Core Bluetooth · no third-party runtime dependencies

This companion app lets a website in Chrome on iPhone open an iOS app to send ESC/POS, TSPL or raw bytes to a BLE printer. Chrome does not perform the BLE operation. The app must be installed and foregrounded. This package contains source, not a signed IPA or App Store release.

## What is included

- Ready-to-open `BluprintsPrintService.xcodeproj`, shared scheme and Info.plist.
- Scan nearby BLE devices; connect and verify the supplied service and characteristics.
- Read FFE2 when supported and subscribe to notifications/indications when supported.
- Write FFE3 with response when available; otherwise use iOS without-response flow control.
- Sequential chunking, negotiated write-size limit, configurable delay, stalled-write timeout and cancellation.
- ESC/POS receipt and TSPL label test jobs. Nothing prints automatically on connection.
- Import BIN, PRN, TXT (raw bytes) or JSON with the file picker.
- `bluprintsprint://print` link handler for Chrome and other browsers.
- Small inline binary payloads and bounded HTTPS JSON downloads for larger jobs.
- Job review and confirmation; warning for the last 100 previously sent job IDs.
- Standalone web demo, JavaScript integration helper and protocol unit tests.

## 1. Install from Xcode on a Mac

1. Extract this ZIP on a Mac. Install Xcode with an iOS SDK compatible with your iPhone's installed iOS version.
2. Open **BluprintsPrintService.xcodeproj** (not Package.swift; that file is only for protocol tests).
3. Select the **BluprintsPrintService** target → **Signing & Capabilities**.
4. Enable **Automatically manage signing** and select your Apple development team. Change `com.bluprints.printservice` to a unique bundle identifier registered to that team if required. No team is embedded in this source.
5. Connect your iPhone to the Mac, trust the computer, and enable Developer Mode if iOS/Xcode requests it.
6. Choose your physical iPhone as the run destination and press **Run**.
7. Allow Bluetooth when requested. The usage-description key is already in Info.plist.
8. For TestFlight/App Store distribution, use your organization's Apple Developer enrollment, complete App Store Connect metadata and privacy declarations, add an app icon, archive/sign the app, and follow Apple's current distribution workflow. Those account-specific steps are not included or performed here.

Windows / VS Code: you can edit this project on Windows. Building, signing and installing this native iOS app requires a Mac with Xcode or a configured macOS build service. The ZIP cannot be installed directly on an iPhone.

## 2. First printer test

1. Turn on the printer and disconnect it from other apps/phones.
2. Open Bluprints Print Service → **Scan printers**. The scan stops after 12 seconds; tap again to rescan.
3. Select the correct printer. The unfiltered list may contain other BLE devices; the app verifies FFE1/FFE3 before enabling Send.
4. Wait for **Connected**.
5. Select **Load ESC/POS receipt test** for an ESC/POS receipt printer, or **Load TSPL label test** only for a TSPL label printer with suitable media.
6. Review the job, tap **Send to printer**, and confirm.
7. Keep the app visible and iPhone unlocked until transmission completes. Inspect the printed output.

The TSPL test assumes a 203 dpi printer, 50 × 30 mm labels and 2 mm gaps. Modify `PrintJob.label()` for other media. Raw payloads are never converted: a format of `tspl` or `escpos` is descriptive, not a command-language converter.

## 3. BLE configuration

| Purpose | UUID |
|---|---|
| Service | `0000ffe1-0000-1000-8000-00805f9b34fb` |
| Read/notify | `0000ffe2-0000-1000-8000-00805f9b34fb` |
| Write | `0000ffe3-0000-1000-8000-00805f9b34fb` |

Defaults are 20 bytes per write with 30 ms between writes. These are conservative trial values, not validated printer throughput limits. Size is capped by `maximumWriteValueLength(for:)`. With-response mode waits for the write callback; without-response mode checks `canSendWriteWithoutResponse` and resumes through `peripheralIsReady(toSendWriteWithoutResponse:)`.

GATT acknowledgements confirm transport-level writes, not paper output or printer-buffer processing. Without-response completion means bytes have been queued to Core Bluetooth, not confirmed delivered. Your printer's application-level ACK/credit protocol was not supplied; it is not invented in this app. Test larger jobs for buffer overruns before increasing speed. Printer responses are displayed as hex; they are not interpreted as paper/battery status.

## 4. Chrome integration — small jobs, no print backend required

After installing the app, host the two files in `WebDemo/` on any HTTPS static host, then open `index.html` in Chrome on iPhone. This is a separate demo from the previously hosted Web Bluetooth tester. Tap **Open app with test receipt** and accept the browser's open-app prompt if shown.

Your website can include `print-service.js` and create a normal link:

```html
<script src="print-service.js"></script>
<a id="print">Print receipt</a>
<script>
  const bytes = new TextEncoder().encode('\x1b@BLUPRINTS\nHello from Chrome\n\n\n');
  document.getElementById('print').href = BluprintsPrint.printLink(
    bytes, 'invoice-123-attempt-1', 'escpos'
  );
</script>
```

`TextEncoder` is suitable for this ASCII demonstration. For Hindi/Marathi, images, barcode raster data or printer code pages, generate the exact supported printer bytes before calling `printLink`. PDF files are not rendered by this app.

The customer taps the link; iOS opens the app. The app displays the job, and the customer selects/connects the printer and confirms Send. Return to Chrome manually through the app switcher. No automatic callback or guaranteed automatic return to Chrome is implemented.

Direct link protocol:

```text
bluprintsprint://print?jobId=invoice-123-attempt-1&format=escpos&data=G0BIZWxsbwoKCg
```

`data` is Base64URL (URL-safe Base64), preferably unpadded. The helper supports up to 20 KiB raw data; the app rejects complete links over 32 KiB. Browser/OS URL handling may impose lower practical limits. Use the remote-job route for large jobs. Job IDs are 1–100 letters/digits/underscore/hyphen/dot. Allowed formats are `escpos`, `tspl`, `raw`. The app rejects duplicate/unknown parameters and empty or oversized payloads.

For a simulator URL-routing test on a Mac (UI only; use physical iPhone for BLE):

```bash
xcrun simctl openurl booted 'bluprintsprint://print?jobId=demo-1&format=escpos&data=G0BIZWxsbwoKCg'
```

## 5. Larger jobs through HTTPS

Your backend creates the print bytes and returns a short-lived authorized job URL. Example JSON at that URL:

```json
{
  "jobId": "invoice-123-attempt-1",
  "format": "escpos",
  "dataBase64": "G0BIZWxsbwoKCg=="
}
```

The website creates the app link:

```javascript
const link = BluprintsPrint.remoteLink('https://your-server.example/jobs/short-lived-token');
document.getElementById('print').href = link;
```

The app first displays the source URL and requires **Download job**. It then validates the JSON and displays the job for separate Send confirmation. Requirements:

- HTTPS with a trusted certificate. No plaintext HTTP or certificate bypass.
- Final endpoint must return HTTP 200. Redirects are rejected.
- JSON response at most 3 MiB; decoded print bytes at most 2 MiB.
- Use scoped, short-lived authorization in the job URL or implement native authentication. The app does not inherit Chrome cookies/login sessions.
- Do not place permanent credentials in the URL. Review URL handling and host restrictions for your production environment.
- No backend, token issuer, job-status API or server-side deduplication is included in this source. These are integration points for your application.
- Local JSON imports are read with the 2 MiB file limit; use HTTPS for a larger JSON envelope.

## 6. Operation and failure behavior

- No auto-print on app launch, incoming link, download or connection.
- Single active send. Incoming links during a send/download are rejected with a message; open them again later.
- Connection/service discovery timeout: 20 seconds. Stalled send/read timeouts disconnect rather than retry.
- Cancel disconnects. Bytes already queued or printed cannot be recalled.
- Entering background stops scanning and cancels active connection/transfer. Background printing is intentionally not implemented. Do not lock the phone or switch to Chrome mid-transfer.
- No automatic reconnect/reprint. Inspect partial output before resending after a failure.
- Recent sent IDs only generate a duplicate warning. This is not exactly-once printing, durable job delivery, or proof that a receipt printed.
- Import file using the app's picker. Share-extension printing and system-wide AirPrint integration are not included.
- Custom URL schemes can be claimed by other apps. For a production rollout, implement Universal Links using your owned domain and team ID; configure Associated Domains/AASA and test Chrome handoff. No invented domain association is included here.

## 7. Build and verification

On a Mac in the extracted directory:

```bash
chmod +x build-check.sh
./build-check.sh
```

This runs `swift test` for the Foundation-only link parser and a simulator build without signing. The test package imports the actual `PrintJob.swift`; it does not test a duplicate implementation. Run physical-device BLE checks separately.

Validation performed during generation:

- JavaScript syntax check passed.
- Six JavaScript assertions passed: binary Base64URL round-trip, expected encoding, HTTP rejection, payload-size rejection, invalid-format rejection and HTTPS URL preservation.
- Info.plist, Xcode scheme XML and project reference/source inventory checks passed.
- No Swift compiler, Xcode or iOS SDK was available in the generation environment. Native compilation, XCTest execution, signing, iPhone launch and hardware printing have NOT been verified. Treat this as a development source project pending the Mac checks below.

## 8. Device acceptance checklist

- [ ] Build and parser tests pass in Xcode/macOS toolchain.
- [ ] Bluetooth denied/off states show useful messages.
- [ ] FFE1/FFE2/FFE3 discovered on your exact printer/firmware.
- [ ] ESC/POS and TSPL tests used only with the corresponding printer.
- [ ] Chrome link opens the installed app from a genuine user tap.
- [ ] Inline binary data arrives byte-for-byte (including 00, 80, FF).
- [ ] Imported BIN/PRN is transmitted unchanged.
- [ ] Read/notification bytes match firmware expectations.
- [ ] Larger receipt/image jobs complete without printer buffer loss.
- [ ] Disconnect, power loss, timeout, cancel and background interruption do not trigger automatic duplicate prints.
- [ ] Duplicate job warning and explicit reprint behavior are acceptable.
- [ ] HTTPS download tested for bad certificate, redirect, HTTP error, malformed JSON, excess size and expiry.
- [ ] Production icon, bundle ID, signing, distribution and privacy declarations completed.

## Source map

- `BLEPrinter.swift`: BLE connection and send state machine.
- `PrintJob.swift`: validated byte payload, JSON and URL protocol.
- `JobInbox.swift`: bounded download and file import.
- `ContentView.swift`: connect/review/send/import/settings UI.
- `BluprintsPrintServiceApp.swift`: application lifecycle and incoming links.
- `WebDemo/`: Chrome handoff demo and JavaScript helper.
- `Tests/`: Swift parser tests.

## Apple references

- Core Bluetooth: https://developer.apple.com/documentation/corebluetooth
- Write limits: https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)
- Without-response readiness: https://developer.apple.com/documentation/corebluetooth/cbperipheral/cansendwritewithoutresponse
- Bluetooth permission: https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription
- Incoming URLs: https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)
- Custom URL schemes: https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app
- Universal Links: https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app
