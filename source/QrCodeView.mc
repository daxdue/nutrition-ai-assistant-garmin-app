using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Communications as Comm;
using Toybox.Lang as Lang;
import Toybox.Graphics;

/**
 * Simple QR code view that displays device ID as text
 * Note: Connect IQ doesn't support downloading/displaying arbitrary images easily,
 * so we display the device ID text which can be scanned if the user generates
 * a QR code on their phone, or entered manually in the pairing page.
 */
class QrCodeView extends Ui.View {
    var mDeviceId as Lang.String;
    var mQrCodeUrl as Lang.String?;

    function initialize(deviceId as Lang.String) {
        View.initialize();
        mDeviceId = deviceId;
        mQrCodeUrl = null;
    }

    function onShow() as Void {
        // Optionally fetch QR code URL (for reference, though we can't easily display it)
        // The QR code can be accessed at: BACKEND_URL + "/api/pairing/qrcode/" + mDeviceId
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.clear();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);

        var w = dc.getWidth();
        var h = dc.getHeight();

        // Title
        dc.drawText(
            w / 2,
            20,
            Gfx.FONT_SMALL,
            "Pairing Code",
            Gfx.TEXT_JUSTIFY_CENTER
        );

        // Device ID label
        dc.drawText(
            w / 2,
            50,
            Gfx.FONT_XTINY,
            "Device ID:",
            Gfx.TEXT_JUSTIFY_CENTER
        );

        // Display device ID (split if too long)
        var deviceIdDisplay = mDeviceId;
        if (deviceIdDisplay.length() > 16) {
            // Split into multiple lines
            var lines = splitDeviceId(deviceIdDisplay, 16);
            var yPos = h / 2 - (lines.size() * 15) / 2;
            for (var i = 0; i < lines.size(); i++) {
                dc.drawText(
                    w / 2,
                    yPos + (i * 15),
                    Gfx.FONT_XTINY,
                    lines[i],
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }
        } else {
            dc.drawText(
                w / 2,
                h / 2,
                Gfx.FONT_XTINY,
                deviceIdDisplay,
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }

        // Instructions
        dc.drawText(
            w / 2,
            h - 40,
            Gfx.FONT_XTINY,
            "Scan QR or enter",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            w / 2,
            h - 25,
            Gfx.FONT_XTINY,
            "in pairing page",
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    function splitDeviceId(deviceId as Lang.String, maxLength as Lang.Number) as Lang.Array<Lang.String> {
        var lines = [] as Lang.Array<Lang.String>;
        var remaining = deviceId;
        
        while (remaining.length() > maxLength) {
            lines.add(remaining.substring(0, maxLength));
            remaining = remaining.substring(maxLength, remaining.length());
        }
        
        if (remaining.length() > 0) {
            lines.add(remaining);
        }
        
        return lines;
    }
}
