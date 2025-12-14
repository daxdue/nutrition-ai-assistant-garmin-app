using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Communications as Comm;
using Toybox.SensorHistory as SH;
using Toybox.ActivityMonitor as AM;
using Toybox.Time as Time;
using Toybox.Lang as Lang;
import Toybox.Graphics;

class MainView extends Ui.View {

    const BACKEND_URL = "https://nutrition-assistant-backend-production-cd64.up.railway.app";
    const API_KEY_STORAGE_KEY = "apiKey";
    var mStatus as Lang.String;
    var mIsPaired as Lang.Boolean;
    var mDeviceId as Lang.String;
    var mApiKey as Lang.String?;

    function initialize() {
        View.initialize();
        mStatus = "Loading…";
        mIsPaired = false;
        mDeviceId = "";
        mApiKey = null;
        
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

        // Check pairing status
        mStatus = "Checking…";
        Ui.requestUpdate();
        checkPairingStatus();
    }

    // Update the view
    function onUpdate(dc as Graphics.Dc) as Void {
        // Full-screen black view with centered white text
        dc.clear();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (!mIsPaired) {
            // Show pairing instructions with device ID
            // Note: QR code can be accessed at BACKEND_URL + "/api/pairing/qrcode/" + mDeviceId
            // but Connect IQ has limitations displaying arbitrary images, so we show the device ID text
            dc.drawText(
                w / 2,
                20,
                Gfx.FONT_SMALL,
                "Not Paired",
                Gfx.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                w / 2,
                45,
                Gfx.FONT_XTINY,
                "Device ID:",
                Gfx.TEXT_JUSTIFY_CENTER
            );
            
            // Display device ID (split into multiple lines if needed)
            var deviceIdDisplay = mDeviceId;
            var maxLineLength = 18;
            if (deviceIdDisplay.length() > maxLineLength) {
                // Split into multiple lines
                var lines = splitDeviceId(deviceIdDisplay, maxLineLength);
                var startY = h / 2 - (lines.size() * 12) / 2;
                for (var i = 0; i < lines.size(); i++) {
                    dc.drawText(
                        w / 2,
                        startY + (i * 12),
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
            
            dc.drawText(
                w / 2,
                h - 35,
                Gfx.FONT_XTINY,
                "Use /pair in bot",
                Gfx.TEXT_JUSTIFY_CENTER
            );
            dc.drawText(
                w / 2,
                h - 20,
                Gfx.FONT_XTINY,
                "to pair device",
                Gfx.TEXT_JUSTIFY_CENTER
            );
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

    // Check if device is paired
    function checkPairingStatus() as Void {
        if (mDeviceId.equals("unknown")) {
            mStatus = "Error: No Device ID";
            mIsPaired = false;
            Ui.requestUpdate();
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
            if (data != null && (data has :paired) && data.get(:paired) == true) {
                mIsPaired = true;
                
                // Store API key if provided
                if ((data has :apiKey) && data.get(:apiKey) != null) {
                    var apiKey = data.get(:apiKey) as Lang.String;
                    mApiKey = apiKey;
                    // Persist API key
                    var app = App.getApp();
                    app.setProperty(API_KEY_STORAGE_KEY, apiKey);
                }
                
                mStatus = "Paired ✓";
                Ui.requestUpdate();
                // Auto-send data after pairing check
                sendNow();
            } else {
                mIsPaired = false;
                mStatus = "Not Paired";
                Ui.requestUpdate();
            }
        } else {
            // On error, assume not paired
            mIsPaired = false;
            mStatus = "Check Failed";
            Ui.requestUpdate();
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

        var payload = buildPayload();

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

    function buildPayload() as Lang.Dictionary or Null {
        // Guard: Check ActivityMonitor availability
        if (!(Toybox has :ActivityMonitor) || !(AM has :getInfo)) {
            return null;
        }

        var info = AM.getInfo();
        if (info == null) {
            return null;
        }

        // Use stored device ID
        var deviceId = mDeviceId;

        // Collect activity metrics
        var steps = getStepsToday(info);
        var activeCalories = getActiveCalories(info);
        var bodyBattery = getLatestBodyBattery();
        var stressAvg = getLatestStress();

        // Backend requires steps and activeCalories to be numbers (not null)
        // Default to 0 if null
        if (steps == null) {
            steps = 0;
        }
        if (activeCalories == null) {
            activeCalories = 0;
        }

        // Build payload dictionary matching backend format
        // Include all fields - backend will handle null optional values
        return {
            "deviceId" => deviceId,
            "timestamp" => Time.now().value(),
            "steps" => steps,
            "activeCalories" => activeCalories,
            "bodyBattery" => bodyBattery,
            "stressAvg" => stressAvg
        };
    }

    function getStepsToday(info as AM.Info) as Lang.Number or Null {
        if ((info has :stepsToday) && info.stepsToday != null) {
            return info.stepsToday;
        }
        if ((info has :steps) && info.steps != null) {
            return info.steps;
        }
        return null;
    }

    function getActiveCalories(info as AM.Info) as Lang.Number or Null {
        // Try activeCalories first (calories burned during activities)
        if ((info has :activeCalories) && info.activeCalories != null) {
            return info.activeCalories;
        }
        // Fallback to calories (total active calories for the day)
        if ((info has :calories) && info.calories != null) {
            return info.calories;
        }
        return null;
    }

    function getLatestHeartRate() as Lang.Number or Null {
        // Try history first
        if ((Toybox has :SensorHistory) && (SH has :getHeartRateHistory)) {
            var it = SH.getHeartRateHistory({
                :period => 1,
                :order  => SH.ORDER_NEWEST_FIRST
            });

            if (it != null && (it has :next)) {
                var sample = it.next();
                if (sample != null && (sample has :data) && sample.data != null) {
                    return sample.data;
                }
            }
        }

        // Fallback to current heart rate
        if ((Toybox has :ActivityMonitor) && (AM has :getInfo)) {
            var info = AM.getInfo();
            if (info != null && (info has :currentHeartRate) && info.currentHeartRate != null) {
                return info.currentHeartRate;
            }
        }

        return null;
    }

    function getLatestBodyBattery() as Lang.Number or Null {
        if (!(Toybox has :SensorHistory) || !(SH has :getBodyBatteryHistory)) {
            return null;
        }

        var it = SH.getBodyBatteryHistory({
            :period => 1,
            :order  => SH.ORDER_NEWEST_FIRST
        });

        if (it != null && (it has :next)) {
            var sample = it.next();
            if (sample != null && (sample has :data) && sample.data != null) {
                return sample.data;
            }
        }

        return null;
    }

    function getLatestStress() as Lang.Number or Null {
        if (!(Toybox has :SensorHistory) || !(SH has :getStressHistory)) {
            return null;
        }

        var it = SH.getStressHistory({
            :period => 1,
            :order  => SH.ORDER_NEWEST_FIRST
        });

        if (it != null && (it has :next)) {
            var sample = it.next();
            if (sample != null && (sample has :data) && sample.data != null) {
                return sample.data;
            }
        }

        return null;
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

}

