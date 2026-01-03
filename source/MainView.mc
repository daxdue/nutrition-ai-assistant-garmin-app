using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Communications as Comm;
using Toybox.Lang as Lang;
import Toybox.Graphics;

class MainView extends Ui.View {

    const BACKEND_URL = "https://nutrition-assistant-backend-production-cd64.up.railway.app";
    const API_KEY_STORAGE_KEY = "apiKey";
    var mStatus as Lang.String;
    var mIsPaired as Lang.Boolean;
    var mDeviceId as Lang.String;
    var mApiKey as Lang.String?;
    var mQrBitmap as Gfx.BitmapReference?;
    var mQrStatus as Lang.String;
    var mQrRequestInFlight as Lang.Boolean;
    var mDelegate as MainDelegate?;

    function initialize() {
        View.initialize();
        mStatus = "Loading…";
        mIsPaired = false;
        mDeviceId = "";
        mApiKey = null;
        mQrBitmap = null;
        mQrStatus = "Loading QR…";
        mQrRequestInFlight = false;
        
        // Load stored API key
        var app = App.getApp();
        var storedKey = app.getProperty(API_KEY_STORAGE_KEY);
        if (storedKey != null) {
            mApiKey = storedKey as Lang.String;
        }
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        // Get device ID first
        var settings = Sys.getDeviceSettings();
        mDeviceId = (settings != null && (settings has :uniqueIdentifier) && settings.uniqueIdentifier != null)
            ? settings.uniqueIdentifier
            : "unknown";
        mQrBitmap = null;
        mQrStatus = "Loading QR…";
        mQrRequestInFlight = false;
        Ui.requestUpdate();

        // Check pairing status
        mStatus = "Checking…";
        Ui.requestUpdate();
        checkPairingStatus();

        // Kick off QR download so it is ready if not paired
        requestQrCode();
    }

    // Update the view
    function onUpdate(dc as Graphics.Dc) as Void {
        // Full-screen black view with centered white text
        dc.clear();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (!mIsPaired) {
            // Pairing UI with downloadable QR code
            dc.drawText(
                w / 2,
                20,
                Gfx.FONT_SMALL,
                "Pair Device",
                Gfx.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                w / 2,
                42,
                Gfx.FONT_XTINY,
                mStatus,
                Gfx.TEXT_JUSTIFY_CENTER
            );

            if (mQrBitmap != null) {
                var qr = mQrBitmap;
                var qrW = ((qr has :getWidth) && qr.getWidth() != null) ? qr.getWidth() : 0;
                var qrH = ((qr has :getHeight) && qr.getHeight() != null) ? qr.getHeight() : 0;
                var qrX = (w - qrW) / 2;
                var qrY = (h - qrH) / 2 - 8;
                dc.drawBitmap(qrX, qrY, qr);
            } else {
                dc.drawText(
                    w / 2,
                    h / 2 - 10,
                    Gfx.FONT_XTINY,
                    mQrStatus,
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }

            // Device ID for manual entry fallback
            dc.drawText(
                w / 2,
                h - 48,
                Gfx.FONT_XTINY,
                "Device ID",
                Gfx.TEXT_JUSTIFY_CENTER
            );

            var deviceIdDisplay = mDeviceId;
            var maxLineLength = 18;
            var lines = splitDeviceId(deviceIdDisplay, maxLineLength);
            var startY = h - 36;
            for (var i = 0; i < lines.size(); i++) {
                dc.drawText(
                    w / 2,
                    startY + (i * 11),
                    Gfx.FONT_XTINY,
                    lines[i],
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }
        } else {
            // Show status
            dc.drawText(
                w / 2,
                h / 2,
                Gfx.FONT_MEDIUM,
                mStatus,
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    function setDelegate(delegate as MainDelegate) as Void {
        mDelegate = delegate;
    }

    // Check if device is paired
    function checkPairingStatus() as Void {
        if (mDeviceId.equals("unknown")) {
            mStatus = "Error: No Device ID";
            mIsPaired = false;
            Ui.requestUpdate();
            mQrStatus = "No Device ID";
            return;
        }

        var url = BACKEND_URL + "/api/pairing/status/" + mDeviceId;
        var options = {
            :method       => Comm.HTTP_REQUEST_METHOD_GET,
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Comm.makeWebRequest(
            url,
            null,
            options,
            method(:onPairingStatusResponse)
        );
    }

    function onPairingStatusResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode >= 200 && responseCode < 300) {
            var payload = data;

            var pairedValue = null;
            if (payload != null && payload instanceof Lang.Dictionary) {
                if (payload has :paired) {
                    pairedValue = payload.get(:paired);
                } else {
                    pairedValue = payload.get("paired");
                }
            } else if (payload != null && payload instanceof Lang.String) {
                var payloadStr = payload as Lang.String;
                if (payloadStr.find("\"paired\":true") != null || payloadStr.find("\"paired\": true") != null) {
                    pairedValue = true;
                } else if (payloadStr.find("\"paired\":false") != null || payloadStr.find("\"paired\": false") != null) {
                    pairedValue = false;
                } else if (payloadStr.find("\"paired\":1") != null || payloadStr.find("\"paired\": 1") != null) {
                    pairedValue = 1;
                } else if (payloadStr.find("\"paired\":0") != null || payloadStr.find("\"paired\": 0") != null) {
                    pairedValue = 0;
                }
            }

            var isPaired = false;
            if (pairedValue != null) {
                if (pairedValue instanceof Lang.Boolean) {
                    isPaired = pairedValue;
                } else if (pairedValue instanceof Lang.Number) {
                    isPaired = (pairedValue == 1);
                } else if (pairedValue instanceof Lang.String) {
                    isPaired = pairedValue.equals("true");
                }
            }

            if (isPaired) {
                mIsPaired = true;
                
                // Store API key if provided
                if (payload != null && payload instanceof Lang.Dictionary) {
                    var apiKeyValue = null;
                    if (payload has :apiKey) {
                        apiKeyValue = payload.get(:apiKey);
                    } else {
                        apiKeyValue = payload.get("apiKey");
                    }

                    if (apiKeyValue != null) {
                        var apiKey = apiKeyValue as Lang.String;
                        mApiKey = apiKey;
                        // Persist API key
                        var app = App.getApp();
                        app.setProperty(API_KEY_STORAGE_KEY, apiKey);
                    }
                } else if (payload != null && payload instanceof Lang.String) {
                    var payloadStr = payload as Lang.String;
                    var apiKeyMarker = "\"apiKey\":\"";
                    var apiKeyStart = payloadStr.find(apiKeyMarker);
                    if (apiKeyStart != null) {
                        var start = apiKeyStart + apiKeyMarker.length();
                        var after = payloadStr.substring(start, payloadStr.length());
                        var end = after.find("\"");
                        if (end != null && end > 0) {
                            var apiKey = after.substring(0, end);
                            mApiKey = apiKey;
                            var app = App.getApp();
                            app.setProperty(API_KEY_STORAGE_KEY, apiKey);
                        }
                    }
                }
                
                mStatus = "Paired ✓";
                Ui.requestUpdate();
                // Auto-send data after pairing check
                sendNow();
            } else {
                mIsPaired = false;
                mStatus = "Not Paired";
                Ui.requestUpdate();
                requestQrCode();
            }
        } else {
            // On error, assume not paired
            mIsPaired = false;
            mStatus = "Check Failed";
            Ui.requestUpdate();
            requestQrCode();
        }
    }

    // Public method for manual resend via delegate
    function sendNow() as Void {
        if (!mIsPaired) {
            mStatus = "Not Paired";
            Ui.requestUpdate();
            return;
        }

        if (mApiKey == null) {
            mStatus = "No API Key";
            Ui.requestUpdate();
            return;
        }

        if (mDelegate == null) {
            mStatus = "Missing Delegate";
            Ui.requestUpdate();
            return;
        }

        var payload = mDelegate.buildGarminDailySnapshotV2(mDeviceId);

        if (payload == null) {
            mStatus = "Error No data";
            Ui.requestUpdate();
            return;
        }

        var options = {
            :method       => Comm.HTTP_REQUEST_METHOD_POST,
            :headers      => {
                "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + mApiKey
            },
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        mStatus = "Uploading…";
        Ui.requestUpdate();

        Comm.makeWebRequest(
            BACKEND_URL + "/api/garmin/daily",
            payload,      // Dictionary → JSON because of content-type
            options,
            method(:onHttpResponse)
        );
    }

    function onHttpResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode >= 200 && responseCode < 300) {
            mStatus = "Uploaded ✓";
        } else {
            mStatus = "Error " + responseCode.toString();
        }

        Ui.requestUpdate();
    }

    // Helper function to split device ID into multiple lines
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

    // Download QR image from backend and cache in memory
    function requestQrCode() as Void {
        if (mQrRequestInFlight) {
            return;
        }

        if (mDeviceId == null || mDeviceId.equals("unknown")) {
            mQrStatus = "No Device ID";
            Ui.requestUpdate();
            return;
        }

        mQrStatus = "Loading QR…";
        mQrBitmap = null;
        mQrRequestInFlight = true;
        Ui.requestUpdate();

        var url = BACKEND_URL + "/api/pairing/qrcode/" + mDeviceId;
        Comm.makeImageRequest(
            url,
            null,
            {}, // use default sizing/palette
            method(:onQrCodeResponse)
        );
    }

    function onQrCodeResponse(responseCode as Lang.Number, data as Gfx.BitmapReference or Null) as Void {
        mQrRequestInFlight = false;
        if (responseCode >= 200 && responseCode < 300 && data != null) {
            mQrBitmap = data;
            mQrStatus = "Scan to pair";
        } else {
            mQrBitmap = null;
            mQrStatus = "QR load failed";
        }
        Ui.requestUpdate();
    }

}
