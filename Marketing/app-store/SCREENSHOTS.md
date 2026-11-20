# Making the App Store screenshots

The screenshots are real captures of the app, composed by `Scripts/make-store-screenshots.swift`.

1. Optional: put sample progress photos in `Marketing/app-store/sample-photos/` as `1.jpg` to `8.jpg` (week 1 first).
2. Run the Debug build in the iPhone 17 simulator with screenshot mode on. Set these in the app's defaults:
   `debug.storeShots` = true, `debug.previewEntitled` = true, and `debug.photoDir` = the name of a folder of photos
   copied into the app's `Library/Caches` (the simulator can't read the Desktop). One week is created per photo;
   a folder with a single photo gives the first check-in, used for `checkin-start.png`.
   Delete the app's saved `state.json` first so the sample data is created fresh.
3. Set a clean status bar: `xcrun simctl status_bar booted override --time "9:41" --batteryLevel 100 --batteryState discharging --cellularBars 4 --wifiBars 3`
4. Capture each screen at 1206 x 2622 into `Marketing/app-store/captures/`:
   - `home.png`: Home, at the top
   - `weight.png`: Home, scrolled so the weight chart and measurements show
   - `recap.png`: open `gainlapse://shot/recap`
   - `checkin.png`: open `gainlapse://shot/checkin`
   - `share.png`: open `gainlapse://shot/share`, on Before & after
   - `checkin-start.png`: the same check-in link, run with a one-photo folder (`sample-photos-2`)

   If a changed default doesn't take effect, the simulator has cached the old value: quit the app and run
   `pkill -f RuntimeRoot/usr/sbin/cfprefsd` before relaunching.
5. Compose: `swift Scripts/make-store-screenshots.swift Marketing/app-store/captures Marketing/app-store/screenshots`

That writes `screenshots/` (1290 x 2796) and `screenshots-6.3in/` (1206 x 2622). Screenshot mode and the
`gainlapse://shot/` links exist only in Debug builds.
