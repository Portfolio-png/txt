Ran command: `~/Library/Android/sdk/platform-tools/adb connect 192.168.0.106:46431`

Since Wireless Debugging pairing is acting up (sometimes Wi-Fi routers have "AP Isolation" enabled which blocks devices from seeing each other, or the Mac's firewall interrupts the pairing protocol), there is a much more reliable "classic" way to do wireless debugging that completely skips the pairing code process.

If you don't mind plugging your phone into your Mac with a **USB cable for just 5 seconds**, we can force it to work:

1. **Plug your phone in** via USB.
2. Run this command to restart the ADB daemon in network mode:
   ```bash
   ~/Library/Android/sdk/platform-tools/adb tcpip 5555
   ```
3. Look up your phone's Wi-Fi IP address (usually found in Settings > Network > Wi-Fi > network details, e.g., `192.168.0.106`), and run:
   ```bash
   ~/Library/Android/sdk/platform-tools/adb connect 192.168.0.106:5555
   ```
4. **Unplug the USB cable.** You are now connected wirelessly!
5. Finally, run our port forwarding command so the app can reach your backend:
   ```bash
   ~/Library/Android/sdk/platform-tools/adb reverse tcp:18080 tcp:18080
   ```

After this, `flutter run` will work perfectly over Wi-Fi without any pairing errors.
