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
    var mNutritionStatus as Lang.String;
    var mNutritionData as Lang.Dictionary?;

    function initialize() {
        View.initialize();
        mStatus = "Loading…";
        mIsPaired = false;
        mDeviceId = "";
        mApiKey = null;
        mQrBitmap = null;
        mQrStatus = "Loading QR…";
        mQrRequestInFlight = false;
        mNutritionStatus = "Loading…";
        mNutritionData = null;
        
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
        mNutritionStatus = "Loading…";
        mNutritionData = null;
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
            // Pairing UI - unpaired state
            renderPairingView(dc, w, h);
        } else {
            // Nutrition UI - paired state
            renderNutritionView(dc, w, h);
        }
    }

    // Render pairing view (unpaired state)
    function renderPairingView(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number) as Void {
        // Calculate font heights for proper spacing
        var titleFont = Gfx.FONT_XTINY; // Smaller font for title
        var statusFont = Gfx.FONT_XTINY;
        var titleHeight = dc.getFontHeight(titleFont);
        var statusHeight = dc.getFontHeight(statusFont);
        
        // Top section: Title
        var titleY = 15;
        
        dc.drawText(
            w / 2,
            titleY,
            titleFont,
            "Pair Device",
            Gfx.TEXT_JUSTIFY_CENTER
        );
        
        // Only show status when QR code is NOT displaying
        var showStatus = (mQrBitmap == null);
        var statusY = titleY + titleHeight + 8;
        
        if (showStatus) {
            dc.drawText(
                w / 2,
                statusY,
                statusFont,
                mStatus,
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }

        // Middle section: QR code or loading status
        // Center QR code exactly in the center of the screen
        if (mQrBitmap != null) {
            var qr = mQrBitmap;
            var qrW = ((qr has :getWidth) && qr.getWidth() != null) ? qr.getWidth() : 0;
            var qrH = ((qr has :getHeight) && qr.getHeight() != null) ? qr.getHeight() : 0;
            
            // Center horizontally and vertically on the entire screen
            var qrX = (w - qrW) / 2;
            var qrY = (h - qrH) / 2;
            
            dc.drawBitmap(qrX, qrY, qr);
        } else {
            // Show QR loading status centered on screen
            dc.drawText(
                w / 2,
                h / 2,
                statusFont,
                mQrStatus,
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // Render nutrition view (paired state)
    function renderNutritionView(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number) as Void {
        // Calculate font heights for proper spacing
        var titleFont = Gfx.FONT_XTINY; // Smaller font for title to fit on screen
        var statusFont = Gfx.FONT_XTINY;
        var valueFont = Gfx.FONT_LARGE; // Larger font for calories
        var titleHeight = dc.getFontHeight(titleFont);
        var statusHeight = dc.getFontHeight(statusFont);
        var valueHeight = dc.getFontHeight(valueFont);
        
        // Check if we need to show bottom status
        var showBottomStatus = (mStatus != null && !mStatus.equals("Paired ✓"));
        var bottomMargin = showBottomStatus ? statusHeight + 5 : 5;
        
        // Top section: Title - ensure it fits on screen
        var titleY = 10;
        if (titleY + titleHeight <= h) {
            dc.drawText(
                w / 2,
                titleY,
                titleFont,
                "Nutrition Today",
                Gfx.TEXT_JUSTIFY_CENTER
            );
        }

        // Status section (only if nutrition data is loading/error)
        var hasNutritionData = (mNutritionData != null);
        var showStatus = !hasNutritionData && mNutritionStatus != null && !mNutritionStatus.equals("");
        
        // Calculate available space for main content
        var contentTop = titleY + titleHeight + 5;
        if (showStatus) {
            var statusY = contentTop;
            dc.drawText(
                w / 2,
                statusY,
                statusFont,
                mNutritionStatus,
                Gfx.TEXT_JUSTIFY_CENTER
            );
            contentTop = statusY + statusHeight + 10;
        }
        
        var contentBottom = h - bottomMargin;
        var availableHeight = contentBottom - contentTop;
        
        // Main content section: Nutrition data - center in available space
        if (hasNutritionData) {
            var calories = formatNutritionValue(mNutritionData.get("calories"), " kcal");
            var meals = formatNutritionValue(mNutritionData.get("meals"), "");
            
            // Calculate spacing between calories and meals
            var spacing = 12;
            var totalContentHeight = valueHeight + spacing + statusHeight;
            
            // Center the content block vertically in available space
            var contentCenterY = contentTop + (availableHeight / 2);
            var caloriesY = contentCenterY - (totalContentHeight / 2);
            var mealsY = caloriesY + valueHeight + spacing;
            
            // Ensure everything fits within bounds
            if (caloriesY < contentTop) {
                caloriesY = contentTop;
                mealsY = caloriesY + valueHeight + spacing;
            }
            
            if (mealsY + statusHeight > contentBottom) {
                mealsY = contentBottom - statusHeight;
                caloriesY = mealsY - valueHeight - spacing;
                if (caloriesY < contentTop) {
                    caloriesY = contentTop;
                }
            }
            
            // Draw calories
            if (caloriesY >= contentTop && caloriesY + valueHeight <= contentBottom) {
                dc.drawText(
                    w / 2,
                    caloriesY,
                    valueFont,
                    calories,
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }

            // Draw meals
            if (mealsY >= contentTop && mealsY + statusHeight <= contentBottom) {
                var mealsText = "Meals " + meals;
                dc.drawText(
                    w / 2,
                    mealsY,
                    statusFont,
                    mealsText,
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }
        }

        // Bottom section: Upload status (only show if not default "Paired ✓")
        // Ensure status text stays within screen bounds
        if (showBottomStatus) {
            var footerY = h - statusHeight - 5;
            // Ensure footer doesn't go off screen
            if (footerY >= 0 && footerY + statusHeight <= h) {
                dc.drawText(
                    w / 2,
                    footerY,
                    statusFont,
                    mStatus,
                    Gfx.TEXT_JUSTIFY_CENTER
                );
            }
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
                // Transitioning to paired state - clear unpaired state data
                var wasUnpaired = !mIsPaired;
                mIsPaired = true;
                
                if (wasUnpaired) {
                    // Clear QR code data when transitioning to paired
                    mQrBitmap = null;
                    mQrStatus = "";
                    mQrRequestInFlight = false;
                }
                
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
                fetchNutritionForToday();
            } else {
                // Transitioning to unpaired state - clear paired state data
                var wasPaired = mIsPaired;
                mIsPaired = false;
                
                if (wasPaired) {
                    // Clear nutrition data when transitioning to unpaired
                    mNutritionData = null;
                    mNutritionStatus = "";
                }
                
                mStatus = "Not Paired";
                Ui.requestUpdate();
                requestQrCode();
            }
        } else {
            // On error, assume not paired
            var wasPaired = mIsPaired;
            mIsPaired = false;
            
            if (wasPaired) {
                // Clear nutrition data when transitioning to unpaired
                mNutritionData = null;
                mNutritionStatus = "";
            }
            
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

    function fetchNutritionForToday() as Void {
        if (!mIsPaired) {
            mNutritionStatus = "Not Paired";
            mNutritionData = null;
            Ui.requestUpdate();
            return;
        }

        if (mApiKey == null) {
            mNutritionStatus = "No API Key";
            mNutritionData = null;
            Ui.requestUpdate();
            return;
        }

        var options = {
            :method       => Comm.HTTP_REQUEST_METHOD_GET,
            :headers      => {
                "Authorization" => "Bearer " + mApiKey
            },
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        mNutritionStatus = "Loading…";
        mNutritionData = null;
        Ui.requestUpdate();

        // Add query parameter for current day (days=1)
        var url = BACKEND_URL + "/api/stats/n?days=1";

        Comm.makeWebRequest(
            url,
            null,
            options,
            method(:onNutritionResponse)
        );
    }

    function onNutritionResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode >= 200 && responseCode < 300) {
            var payload = data;
            var nutrition = extractNutritionPayload(payload);

            if (nutrition != null) {
                mNutritionData = nutrition;
                mNutritionStatus = "Updated";
            } else {
                mNutritionData = null;
                mNutritionStatus = "No data";
            }
        } else {
            mNutritionData = null;
            mNutritionStatus = "Error " + responseCode.toString();
        }

        Ui.requestUpdate();
    }

    function extractNutritionPayload(payload as Lang.Dictionary or Lang.String or Null) as Lang.Dictionary or Null {
        if (payload == null) {
            return null;
        }

        var payloadDict = payload as Lang.Dictionary;
        if (payloadDict == null) {
            return null;
        }

        var candidate = payloadDict;
        var nestedKeys = [ :data, "data", :stats, "stats", :nutrition, "nutrition", :totals, "totals", :summary, "summary", :day, "day" ] as Lang.Array;
        for (var i = 0; i < nestedKeys.size(); i++) {
            var key = nestedKeys[i];
            var nested = candidate.get(key);
            if (nested != null && nested instanceof Lang.Dictionary) {
                candidate = nested;
                break;
            }
        }

        var calories = extractNumber(candidate, [ :totalKcal, "totalKcal", :calories, "calories", :kcal, "kcal", :energy, "energy" ]);
        var meals = extractNumber(candidate, [ :totalMeals, "totalMeals", :meals, "meals" ]);

        if (calories == null && meals == null) {
            return null;
        }

        return {
            "calories" => calories,
            "meals" => meals
        };
    }

    function extractNumber(source as Lang.Dictionary, keys as Lang.Array) as Lang.Number or Lang.Float or Null {
        if (source == null) {
            return null;
        }

        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            var value = source.get(key);
            if (value != null) {
                var numberValue = value as Lang.Number;
                if (numberValue != null) {
                    return numberValue;
                }
                var floatValue = value as Lang.Float;
                if (floatValue != null) {
                    return floatValue;
                }
            }
        }

        return null;
    }

    function formatNutritionValue(value as Lang.Number or Lang.Float or Null, suffix as Lang.String) as Lang.String {
        if (value == null) {
            return "--";
        }

        return value.toString() + suffix;
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

