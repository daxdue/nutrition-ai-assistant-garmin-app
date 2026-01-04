using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Communications as Comm;
using Toybox.Lang as Lang;
using Toybox.ActivityMonitor as AM;
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
        var titleY = 20;
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
            
            // Get burned calories from ActivityMonitor
            var burnedCalories = getBurnedCalories();
            
            // Get macros
            var fat = mNutritionData.get("fat");
            var carbs = mNutritionData.get("carbs");
            var protein = mNutritionData.get("protein");
            
            // Check if macros have values (with proper type casting)
            var fatVal = (fat != null) ? (fat as Lang.Float) : null;
            var carbsVal = (carbs != null) ? (carbs as Lang.Float) : null;
            var proteinVal = (protein != null) ? (protein as Lang.Float) : null;
            var hasMacros = (fatVal != null && fatVal > 0) || (carbsVal != null && carbsVal > 0) || (proteinVal != null && proteinVal > 0);
            
            // Calculate spacing - account for bar chart and macros
            var barHeight = 8;
            var barSpacing = 8;
            var spacing = 10;
            var macroSpacing = 6;
            var macrosHeight = hasMacros ? statusHeight + macroSpacing : 0;
            var totalContentHeight = valueHeight + spacing + barSpacing + barHeight + statusHeight + macrosHeight;
            
            // Center the content block vertically in available space
            var contentCenterY = contentTop + (availableHeight / 2);
            var caloriesY = contentCenterY - (totalContentHeight / 2);
            var barY = caloriesY + valueHeight + spacing;
            var mealsY = barY + barHeight + barSpacing;
            var macrosY = mealsY + statusHeight + macroSpacing;
            
            // Ensure everything fits within bounds
            if (caloriesY < contentTop) {
                caloriesY = contentTop;
                barY = caloriesY + valueHeight + spacing;
                mealsY = barY + barHeight + barSpacing;
                macrosY = mealsY + statusHeight + macroSpacing;
            }
            
            if (macrosY + statusHeight > contentBottom) {
                macrosY = contentBottom - statusHeight;
                mealsY = macrosY - macroSpacing - statusHeight;
                barY = mealsY - barSpacing - barHeight;
                caloriesY = barY - spacing - valueHeight;
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

            // Draw horizontal bar showing consumed vs burned calories
            if (barY >= contentTop && barY + barHeight <= contentBottom) {
                var consumedKcal = mNutritionData.get("calories");
                drawCaloriesBar(dc, w, barY, barHeight, consumedKcal, burnedCalories);
                // Reset color to white after drawing the bar
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
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
            
            // Draw macros (Fat, Carbs, Protein)
            if (hasMacros && macrosY >= contentTop && macrosY + statusHeight <= contentBottom) {
                var fatDisplay = (fatVal != null && fatVal > 0) ? fatVal : 0.0;
                var carbsDisplay = (carbsVal != null && carbsVal > 0) ? carbsVal : 0.0;
                var proteinDisplay = (proteinVal != null && proteinVal > 0) ? proteinVal : 0.0;
                
                // Format macros: "F:12g C:25g P:12g"
                var macrosText = "F:" + formatMacroValue(fatDisplay) + "g C:" + formatMacroValue(carbsDisplay) + "g P:" + formatMacroValue(proteinDisplay) + "g";
                dc.drawText(
                    w / 2,
                    macrosY,
                    statusFont,
                    macrosText,
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

        // Calculate macros from foodEntries if available
        var totalFat = 0.0;
        var totalCarbs = 0.0;
        var totalProtein = 0.0;
        
        var foodEntries = candidate.get(:foodEntries);
        if (foodEntries == null) {
            foodEntries = candidate.get("foodEntries");
        }
        
        if (foodEntries != null && foodEntries instanceof Lang.Array) {
            var entries = foodEntries as Lang.Array;
            for (var i = 0; i < entries.size(); i++) {
                var entry = entries[i];
                if (entry != null && entry instanceof Lang.Dictionary) {
                    var aiParsedJson = entry.get(:aiParsedJson);
                    if (aiParsedJson == null) {
                        aiParsedJson = entry.get("aiParsedJson");
                    }
                    
                    if (aiParsedJson != null && aiParsedJson instanceof Lang.Dictionary) {
                        var items = aiParsedJson.get(:items);
                        if (items == null) {
                            items = aiParsedJson.get("items");
                        }
                        
                        if (items != null && items instanceof Lang.Array) {
                            var itemsArray = items as Lang.Array;
                            for (var j = 0; j < itemsArray.size(); j++) {
                                var item = itemsArray[j];
                                if (item != null && item instanceof Lang.Dictionary) {
                                    var fat = extractNumber(item, [ :fat_g, "fat_g", :fat, "fat" ]);
                                    var carbs = extractNumber(item, [ :carbs_g, "carbs_g", :carbs, "carbs", :carbohydrates_g, "carbohydrates_g" ]);
                                    var protein = extractNumber(item, [ :protein_g, "protein_g", :protein, "protein" ]);
                                    
                                    if (fat != null) {
                                        totalFat += fat.toFloat();
                                    }
                                    if (carbs != null) {
                                        totalCarbs += carbs.toFloat();
                                    }
                                    if (protein != null) {
                                        totalProtein += protein.toFloat();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Try to get macros from top-level if not found in foodEntries
        if (totalFat == 0 && totalCarbs == 0 && totalProtein == 0) {
            var fatNum = extractNumber(candidate, [ :totalFatG, "totalFatG", :fat_g, "fat_g", :fat, "fat" ]);
            var carbsNum = extractNumber(candidate, [ :totalCarbsG, "totalCarbsG", :carbs_g, "carbs_g", :carbs, "carbs" ]);
            var proteinNum = extractNumber(candidate, [ :totalProteinG, "totalProteinG", :protein_g, "protein_g", :protein, "protein" ]);
            
            if (fatNum != null) {
                var fatFloat = fatNum as Lang.Float;
                if (fatFloat != null) {
                    totalFat = fatFloat;
                } else {
                    var fatNumber = fatNum as Lang.Number;
                    if (fatNumber != null) {
                        totalFat = fatNumber.toFloat();
                    }
                }
            }
            if (carbsNum != null) {
                var carbsFloat = carbsNum as Lang.Float;
                if (carbsFloat != null) {
                    totalCarbs = carbsFloat;
                } else {
                    var carbsNumber = carbsNum as Lang.Number;
                    if (carbsNumber != null) {
                        totalCarbs = carbsNumber.toFloat();
                    }
                }
            }
            if (proteinNum != null) {
                var proteinFloat = proteinNum as Lang.Float;
                if (proteinFloat != null) {
                    totalProtein = proteinFloat;
                } else {
                    var proteinNumber = proteinNum as Lang.Number;
                    if (proteinNumber != null) {
                        totalProtein = proteinNumber.toFloat();
                    }
                }
            }
        }

        if (calories == null && meals == null && totalFat == 0 && totalCarbs == 0 && totalProtein == 0) {
            return null;
        }

        return {
            "calories" => calories,
            "meals" => meals,
            "fat" => totalFat,
            "carbs" => totalCarbs,
            "protein" => totalProtein
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

    function formatMacroValue(value as Lang.Number or Lang.Float) as Lang.String {
        if (value == null || value == 0) {
            return "0";
        }
        
        // Always format as integer (round to nearest whole number)
        var floatValue = value.toFloat();
        var intValue = floatValue.toNumber();
        
        // Round to nearest integer
        if (floatValue - intValue.toFloat() >= 0.5) {
            intValue = intValue + 1;
        }
        
        return intValue.toString();
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

    // Get burned calories from ActivityMonitor
    function getBurnedCalories() as Lang.Number {
        if (!(Toybox has :ActivityMonitor)) {
            return 0;
        }

        var info = null;
        try {
            info = AM.getInfo();
        } catch (ex) {
            return 0;
        }

        if (info == null) {
            return 0;
        }

        // Try to get total calories burned (active + resting)
        var totalCalories = null;
        if ((info has :totalCalories) && info.totalCalories != null) {
            totalCalories = info.totalCalories;
        } else if ((info has :calories) && info.calories != null) {
            totalCalories = info.calories;
        }

        if (totalCalories != null) {
            return totalCalories;
        }

        // Fallback: try active calories + resting calories
        var activeCalories = null;
        if ((info has :activeCalories) && info.activeCalories != null) {
            activeCalories = info.activeCalories;
        } else if ((info has :calories) && info.calories != null) {
            activeCalories = info.calories;
        }

        var restingCalories = null;
        if ((info has :restingCalories) && info.restingCalories != null) {
            restingCalories = info.restingCalories;
        }

        if (activeCalories != null && restingCalories != null) {
            return activeCalories + restingCalories;
        } else if (activeCalories != null) {
            return activeCalories;
        }

        return 0;
    }

    // Draw horizontal bar showing consumed vs burned calories correlation
    // Based on Garmin Connect IQ SDK Graphics API
    // Shows consumed calories from left (red/green) and burned calories from right (blue)
    function drawCaloriesBar(dc as Graphics.Dc, w as Lang.Number, y as Lang.Number, barHeight as Lang.Number, consumedKcal as Lang.Number or Null, burnedKcal as Lang.Number) as Void {
        if (consumedKcal == null) {
            consumedKcal = 0;
        }

        // Bar dimensions with margins
        var barMargin = 20; // Margin on each side
        var barWidth = w - (barMargin * 2);
        var barX = barMargin;

        // Determine max value for scaling (use the larger of consumed or burned, or default to 2000)
        var maxKcal = consumedKcal > burnedKcal ? consumedKcal : burnedKcal;
        if (maxKcal < 2000) {
            maxKcal = 2000; // Default scale for better visibility
        }

        // Draw background bar (dark gray)
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(barX, y, barWidth, barHeight);

        // Draw consumed calories bar from the left
        var consumedWidth = (consumedKcal.toFloat() / maxKcal.toFloat()) * barWidth;
        if (consumedWidth > barWidth) {
            consumedWidth = barWidth;
        }
        
        if (consumedWidth > 0) {
            // Green if consumed <= burned, red if consumed > burned
            var consumedColor = (consumedKcal <= burnedKcal) ? Gfx.COLOR_GREEN : Gfx.COLOR_RED;
            dc.setColor(consumedColor, Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, y, consumedWidth, barHeight);
        }

        // Draw burned calories bar from the right (blue)
        // This creates a visual correlation - they meet in the middle if balanced
        if (burnedKcal > 0) {
            var burnedWidth = (burnedKcal.toFloat() / maxKcal.toFloat()) * barWidth;
            if (burnedWidth > barWidth) {
                burnedWidth = barWidth;
            }
            
            // Draw burned calories as a filled segment from the right
            var burnedX = barX + barWidth - burnedWidth;
            dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(burnedX, y, burnedWidth, barHeight);
            
            // Draw a white divider line where burned calories start (for clarity)
            if (burnedX > barX) {
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawLine(burnedX, y, burnedX, y + barHeight);
            }
        } else {
            // If no burned calories data, show a message or indicator
            // For now, just don't draw anything for burned
        }
        
        // Reset color to white for text drawing after this function
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
    }

}

