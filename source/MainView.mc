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

    // TODO: Replace with your real backend URL
    const BACKEND_URL = "https://<backend>/api/garmin/daily";
    var mStatus as Lang.String;

    function initialize() {
        View.initialize();
        mStatus = "Loading…";
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        // Auto-send on app start
        mStatus = "Collecting…";
        Ui.requestUpdate();
        sendNow();
    }

    // Update the view
    function onUpdate(dc as Graphics.Dc) as Void {
        // Full-screen black view with centered white text
        dc.clear();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(
            w / 2,
            h / 2,
            Gfx.FONT_MEDIUM,
            mStatus,
            Gfx.TEXT_JUSTIFY_CENTER
        );
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    // Public method for manual resend via delegate
    function sendNow() as Void {
        var payload = buildPayload();

        if (payload == null) {
            mStatus = "Error No data";
            Ui.requestUpdate();
            return;
        }

        var options = {
            :method       => Comm.HTTP_REQUEST_METHOD_POST,
            :headers      => {
                "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
            },
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        mStatus = "Uploading…";
        Ui.requestUpdate();

        Comm.makeWebRequest(
            BACKEND_URL,
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

        // Collect device info
        var settings = Sys.getDeviceSettings();
        var deviceId = (settings != null && (settings has :uniqueIdentifier) && settings.uniqueIdentifier != null)
            ? settings.uniqueIdentifier
            : "unknown";
        var deviceName = (settings != null && (settings has :deviceName)) 
            ? settings.deviceName 
            : null;

        // Collect metrics
        var steps = getStepsToday(info);
        var heartRate = getLatestHeartRate();
        var bodyBattery = getLatestBodyBattery();
        var stress = getLatestStress();

        // Build payload dictionary
        return {
            "deviceId"   => deviceId,
            "deviceName" => deviceName,
            "timestamp"  => Time.now().value(),
            "metrics"    => {
                "steps"       => steps,
                "heartRate"   => heartRate,
                "bodyBattery" => bodyBattery,
                "stress"      => stress
            }
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

}

