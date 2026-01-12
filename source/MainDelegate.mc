using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.SensorHistory as SH;
using Toybox.ActivityMonitor as AM;
using Toybox.Activity as Activity;
using Toybox.Time as Time;
using Toybox.UserProfile as UserProfile;
using Toybox.Lang as Lang;

class MainDelegate extends Ui.BehaviorDelegate {

    const INTEGRATION_KEY = "";
    var mView as MainView;

    function initialize(view as MainView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onKey(evt as Ui.KeyEvent) as Lang.Boolean {
        // Manual resend via START/ENTER
        if (evt.getKey() == Ui.KEY_START || evt.getKey() == Ui.KEY_ENTER) {
            mView.sendNow();
            return true;
        }

        return false;
    }

    function onMenu() as Lang.Boolean {
        var menu = new $.Rez.Menus.MainMenu();
        var delegate = new MainMenuDelegate(mView);
        Ui.pushView(menu, delegate, Ui.SLIDE_UP);
        return true;
    }

    function buildGarminDailySnapshotV2(deviceId as Lang.String) as Lang.Dictionary or Null {
        var nowSec = Time.now().value();
        var dayStartSec = Time.today().value();
        var periodSec = nowSec - dayStartSec;
        if (periodSec < 0) {
            periodSec = 0;
        }
        var period = new Time.Duration(periodSec);

        var metrics = collectActivityMetrics();
        if (metrics == null) {
            metrics = {} as Lang.Dictionary;
        }
        metrics.put("dayStartTimestamp", dayStartSec);

        var heartRate = collectDailyAggregateHeartRate(dayStartSec, nowSec, period);
        if (heartRate != null) {
            metrics.put("heartRate", heartRate);
        }

        var stress = collectDailyAggregateStress(dayStartSec, nowSec, period);
        if (stress != null) {
            metrics.put("stress", stress);
        }

        var spo2 = collectDailyAggregateSpo2(dayStartSec, nowSec, period);
        if (spo2 != null) {
            metrics.put("spo2", spo2);
        }

        var bodyBattery = collectDailyAggregateBodyBattery(dayStartSec, nowSec, period);
        if (bodyBattery != null) {
            metrics.put("bodyBatteryDaily", bodyBattery);
        }

        addSystemMetrics(metrics);

        var activities = collectDailyActivities(dayStartSec, nowSec);
        if (activities != null) {
            metrics.put("activities", activities);
            var activitySummary = buildActivitySummary(activities);
            if (activitySummary != null) {
                metrics.put("activitySummary", activitySummary);
            }
        }

        return {
            "schemaVersion" => "2.0",
            "device" => buildDeviceInfo(deviceId),
            "timestamp" => nowSec,
            "metrics" => metrics
        };
    }

    function buildDeviceInfo(deviceId as Lang.String) as Lang.Dictionary {
        var device = {
            "deviceId" => deviceId
        } as Lang.Dictionary;

        var settings = Sys.getDeviceSettings();
        if (settings != null) {
            if ((settings has :partNumber) && settings.partNumber != null) {
                device.put("deviceName", settings.partNumber);
                device.put("model", settings.partNumber);
            }
            if ((settings has :firmwareVersion) && settings.firmwareVersion != null) {
                var fw = formatFirmwareVersion(settings.firmwareVersion);
                if (fw != null) {
                    device.put("firmwareVersion", fw);
                }
            }
        }

        if (device.get("deviceName") == null) {
            device.put("deviceName", "Garmin");
        }

        return device;
    }

    function formatFirmwareVersion(version as Lang.Array<Lang.Number>) as Lang.String or Null {
        if (version == null || version.size() == 0) {
            return null;
        }
        if (version.size() == 1) {
            return version[0].toString();
        }
        return version[0].toString() + "." + version[1].toString();
    }

    function collectActivityMetrics() as Lang.Dictionary or Null {
        if (!(Toybox has :ActivityMonitor) || !(AM has :getInfo)) {
            return null;
        }

        var info = AM.getInfo();

        var steps = getStepsToday(info);
        var distanceCm = getDistanceCm(info);
        var activeCaloriesKcal = getActiveCaloriesKcal(info);
        var totalCaloriesKcal = getTotalCaloriesKcal(info, activeCaloriesKcal);
        var floorsClimbed = getFloorsClimbed(info);
        var floorsDescended = getFloorsDescended(info);
        var activeMinutes = getActiveMinutes(info);

        return {
            "steps" => (steps == null ? 0 : steps),
            "distanceCm" => (distanceCm == null ? 0 : distanceCm),
            "activeCaloriesKcal" => (activeCaloriesKcal == null ? 0 : activeCaloriesKcal),
            "totalCaloriesKcal" => (totalCaloriesKcal == null ? 0 : totalCaloriesKcal),
            "floorsClimbed" => (floorsClimbed == null ? 0 : floorsClimbed),
            "floorsDescended" => (floorsDescended == null ? 0 : floorsDescended),
            "activeMinutes" => activeMinutes
        };
    }

    function addSystemMetrics(metrics as Lang.Dictionary) as Void {
        var stats = Sys.getSystemStats();
        if (stats != null) {
            if ((stats has :battery) && stats.battery != null) {
                metrics.put("deviceBatteryPercent", stats.battery);
            } else if ((stats has :batteryPercent) && stats.batteryPercent != null) {
                metrics.put("deviceBatteryPercent", stats.batteryPercent);
            }

            if ((stats has :memoryFree) && stats.memoryFree != null) {
                metrics.put("deviceMemoryFreeBytes", stats.memoryFree);
            } else if ((stats has :freeMemory) && stats.freeMemory != null) {
                metrics.put("deviceMemoryFreeBytes", stats.freeMemory);
            }
        }
    }

    function buildActivitySummary(activities as Lang.Array) as Lang.Dictionary or Null {
        var totalCount = 0;
        var totalDurationSeconds = 0;
        var totalDistanceCm = 0;
        var totalCaloriesKcal = 0;
        var byTypeBuckets = {} as Lang.Dictionary;

        for (var i = 0; i < activities.size(); i++) {
            var activity = activities[i];
            if (activity == null || !(activity instanceof Lang.Dictionary)) {
                continue;
            }

            var activityDict = activity as Lang.Dictionary;
            var typeValue = activityDict.get("type");
            if (typeValue == null) {
                continue;
            }

            var typeStr = typeValue.toString();

            totalCount += 1;

            var duration = getNumberFromDict(activityDict, "durationSeconds");
            if (duration != null) {
                totalDurationSeconds += duration;
            }

            var distance = getNumberFromDict(activityDict, "distanceCm");
            if (distance != null) {
                totalDistanceCm += distance;
            }

            var calories = getNumberFromDict(activityDict, "caloriesKcal");
            if (calories != null) {
                totalCaloriesKcal += calories;
            }

            var bucket = byTypeBuckets.get(typeStr);
            if (bucket == null || !(bucket instanceof Lang.Dictionary)) {
                bucket = {
                    "type" => typeStr,
                    "count" => 0,
                    "durationSeconds" => 0,
                    "distanceCm" => 0,
                    "caloriesKcal" => 0
                } as Lang.Dictionary;
                byTypeBuckets.put(typeStr, bucket);
            }

            var bucketDict = bucket as Lang.Dictionary;
            bucketDict.put("count", getNumberOrZero(bucketDict.get("count")) + 1);
            if (duration != null) {
                bucketDict.put("durationSeconds", getNumberOrZero(bucketDict.get("durationSeconds")) + duration);
            }
            if (distance != null) {
                bucketDict.put("distanceCm", getNumberOrZero(bucketDict.get("distanceCm")) + distance);
            }
            if (calories != null) {
                bucketDict.put("caloriesKcal", getNumberOrZero(bucketDict.get("caloriesKcal")) + calories);
            }
        }

        if (totalCount == 0) {
            return null;
        }

        var byType = [] as Lang.Array;
        var keys = byTypeBuckets.keys();
        for (var j = 0; j < keys.size(); j++) {
            var key = keys[j];
            var entry = byTypeBuckets.get(key);
            if (entry != null) {
                byType.add(entry);
            }
        }

        return {
            "totalCount" => totalCount,
            "totalDurationSeconds" => totalDurationSeconds,
            "totalDistanceCm" => totalDistanceCm,
            "totalCaloriesKcal" => totalCaloriesKcal,
            "byType" => byType
        };
    }

    function collectDailyActivities(dayStartSec as Lang.Number, nowSec as Lang.Number) as Lang.Array or Null {
        if (!(Toybox has :UserProfile) || !(UserProfile has :getUserActivityHistory)) {
            return null;
        }

        var iterator = UserProfile.getUserActivityHistory();
        var activities = [] as Lang.Array;

        while (true) {
            var activity = nextUserActivity(iterator);
            if (activity == null) {
                break;
            }

            var startTime = activity.startTime;
            if (startTime == null) {
                continue;
            }

            var startEpochNum = startTime.value();
            if (startEpochNum < dayStartSec || startEpochNum > nowSec) {
                continue;
            }

            var typeStr = normalizeActivityType(activity.type);
            if (typeStr == null) {
                continue;
            }

            var entry = {
                "type" => typeStr,
                "startTimestamp" => startEpochNum
            } as Lang.Dictionary;

            var duration = activity.duration;
            if (duration != null) {
                var durationSec = duration.value();
                var durationNum = durationSec as Lang.Number;
                if (durationNum != null) {
                    entry.put("durationSeconds", durationNum);
                }
            }

            var distanceMeters = activity.distance;
            var distanceNum = distanceMeters as Lang.Number;
            if (distanceNum != null) {
                entry.put("distanceCm", distanceNum * 100);
            }

            activities.add(entry);
        }

        if (activities.size() == 0) {
            return null;
        }

        return activities;
    }

    function nextUserActivity(iterator as UserProfile.UserActivityHistoryIterator) as UserProfile.UserActivity or Null {
        return iterator.next();
    }

    function normalizeActivityType(typeValue as Lang.Object or Null) as Lang.String or Null {
        if (typeValue == null || !(typeValue instanceof Lang.Number)) {
            return null;
        }

        var mapped = mapSportType(typeValue as Lang.Number);
        if (mapped != null) {
            return mapped;
        }

        return "UNKNOWN";
    }

    function mapSportType(typeNum as Lang.Number) as Lang.String or Null {
        switch (typeNum) {
            case Activity.SPORT_GENERIC:
                return "GENERIC";
            case Activity.SPORT_RUNNING:
                return "RUNNING";
            case Activity.SPORT_CYCLING:
                return "CYCLING";
            case Activity.SPORT_TRANSITION:
                return "TRANSITION";
            case Activity.SPORT_FITNESS_EQUIPMENT:
                return "FITNESS_EQUIPMENT";
            case Activity.SPORT_SWIMMING:
                return "SWIMMING";
            case Activity.SPORT_BASKETBALL:
                return "BASKETBALL";
            case Activity.SPORT_SOCCER:
                return "SOCCER";
            case Activity.SPORT_TENNIS:
                return "TENNIS";
            case Activity.SPORT_AMERICAN_FOOTBALL:
                return "AMERICAN_FOOTBALL";
            case Activity.SPORT_TRAINING:
                return "TRAINING";
            case Activity.SPORT_WALKING:
                return "WALKING";
            case Activity.SPORT_CROSS_COUNTRY_SKIING:
                return "CROSS_COUNTRY_SKIING";
            case Activity.SPORT_ALPINE_SKIING:
                return "ALPINE_SKIING";
            case Activity.SPORT_SNOWBOARDING:
                return "SNOWBOARDING";
            case Activity.SPORT_ROWING:
                return "ROWING";
            case Activity.SPORT_MOUNTAINEERING:
                return "MOUNTAINEERING";
            case Activity.SPORT_HIKING:
                return "HIKING";
            case Activity.SPORT_MULTISPORT:
                return "MULTISPORT";
            case Activity.SPORT_PADDLING:
                return "PADDLING";
            case Activity.SPORT_FLYING:
                return "FLYING";
            case Activity.SPORT_E_BIKING:
                return "E_BIKING";
            case Activity.SPORT_MOTORCYCLING:
                return "MOTORCYCLING";
            case Activity.SPORT_BOATING:
                return "BOATING";
            case Activity.SPORT_DRIVING:
                return "DRIVING";
            case Activity.SPORT_GOLF:
                return "GOLF";
            case Activity.SPORT_HANG_GLIDING:
                return "HANG_GLIDING";
            case Activity.SPORT_HORSEBACK_RIDING:
                return "HORSEBACK_RIDING";
            case Activity.SPORT_HUNTING:
                return "HUNTING";
            case Activity.SPORT_FISHING:
                return "FISHING";
            case Activity.SPORT_INLINE_SKATING:
                return "INLINE_SKATING";
            case Activity.SPORT_ROCK_CLIMBING:
                return "ROCK_CLIMBING";
            case Activity.SPORT_SAILING:
                return "SAILING";
            case Activity.SPORT_ICE_SKATING:
                return "ICE_SKATING";
            case Activity.SPORT_SKY_DIVING:
                return "SKY_DIVING";
            case Activity.SPORT_SNOWSHOEING:
                return "SNOWSHOEING";
            case Activity.SPORT_SNOWMOBILING:
                return "SNOWMOBILING";
            case Activity.SPORT_STAND_UP_PADDLEBOARDING:
                return "STAND_UP_PADDLEBOARDING";
            case Activity.SPORT_SURFING:
                return "SURFING";
            case Activity.SPORT_WAKEBOARDING:
                return "WAKEBOARDING";
            case Activity.SPORT_WATER_SKIING:
                return "WATER_SKIING";
            case Activity.SPORT_KAYAKING:
                return "KAYAKING";
            case Activity.SPORT_RAFTING:
                return "RAFTING";
            case Activity.SPORT_WINDSURFING:
                return "WINDSURFING";
            case Activity.SPORT_KITESURFING:
                return "KITESURFING";
            case Activity.SPORT_TACTICAL:
                return "TACTICAL";
            case Activity.SPORT_JUMPMASTER:
                return "JUMPMASTER";
            case Activity.SPORT_BOXING:
                return "BOXING";
            case Activity.SPORT_FLOOR_CLIMBING:
                return "FLOOR_CLIMBING";
            case Activity.SPORT_BASEBALL:
                return "BASEBALL";
            case Activity.SPORT_SOFTBALL_FAST_PITCH:
                return "SOFTBALL_FAST_PITCH";
            case Activity.SPORT_SOFTBALL_SLOW_PITCH:
                return "SOFTBALL_SLOW_PITCH";
            case Activity.SPORT_SHOOTING:
                return "SHOOTING";
            case Activity.SPORT_AUTO_RACING:
                return "AUTO_RACING";
            case Activity.SPORT_WINTER_SPORT:
                return "WINTER_SPORT";
            case Activity.SPORT_GRINDING:
                return "GRINDING";
            case Activity.SPORT_HEALTH_MONITORING:
                return "HEALTH_MONITORING";
            case Activity.SPORT_MARINE:
                return "MARINE";
            case Activity.SPORT_HIIT:
                return "HIIT";
            case Activity.SPORT_VIDEO_GAMING:
                return "VIDEO_GAMING";
            case Activity.SPORT_RACKET:
                return "RACKET";
            case Activity.SPORT_WHEELCHAIR_PUSH_WALK:
                return "WHEELCHAIR_PUSH_WALK";
            case Activity.SPORT_WHEELCHAIR_PUSH_RUN:
                return "WHEELCHAIR_PUSH_RUN";
            case Activity.SPORT_MEDITATION:
                return "MEDITATION";
            case Activity.SPORT_PARA_SPORT:
                return "PARA_SPORT";
            case Activity.SPORT_DISC_GOLF:
                return "DISC_GOLF";
            case Activity.SPORT_TEAM_SPORT:
                return "TEAM_SPORT";
            case Activity.SPORT_CRICKET:
                return "CRICKET";
            case Activity.SPORT_RUGBY:
                return "RUGBY";
            case Activity.SPORT_HOCKEY:
                return "HOCKEY";
            case Activity.SPORT_LACROSSE:
                return "LACROSSE";
            case Activity.SPORT_VOLLEYBALL:
                return "VOLLEYBALL";
            case Activity.SPORT_WATER_TUBING:
                return "WATER_TUBING";
            case Activity.SPORT_WAKESURFING:
                return "WAKESURFING";
            case Activity.SPORT_INVALID:
                return "INVALID";
        }

        return null;
    }

    function collectDailyAggregateHeartRate(dayStartSec as Lang.Number, nowSec as Lang.Number, period as Time.Duration) as Lang.Dictionary or Null {
        if (!(Toybox has :SensorHistory) || !(SH has :getHeartRateHistory)) {
            return null;
        }

        var it = SH.getHeartRateHistory({
            :period => period,
            :order  => SH.ORDER_OLDEST_FIRST
        });

        var stats = computeTimeWeightedStats(it, dayStartSec, nowSec);
        if (stats == null) {
            return null;
        }

        return {
            "avgBpm" => stats.get("avg"),
            "minBpm" => stats.get("min"),
            "maxBpm" => stats.get("max"),
            "sampleCount" => stats.get("sampleCount")
        };
    }

    function collectDailyAggregateStress(dayStartSec as Lang.Number, nowSec as Lang.Number, period as Time.Duration) as Lang.Dictionary or Null {
        if (!(Toybox has :SensorHistory) || !(SH has :getStressHistory)) {
            return null;
        }

        var it = SH.getStressHistory({
            :period => period,
            :order  => SH.ORDER_OLDEST_FIRST
        });

        var stats = computeTimeWeightedStats(it, dayStartSec, nowSec);
        if (stats == null) {
            return null;
        }

        return {
            "avg" => stats.get("avg"),
            "min" => stats.get("min"),
            "max" => stats.get("max"),
            "sampleCount" => stats.get("sampleCount")
        };
    }

    function collectDailyAggregateSpo2(dayStartSec as Lang.Number, nowSec as Lang.Number, period as Time.Duration) as Lang.Dictionary or Null {
        if (!(Toybox has :SensorHistory) || !(SH has :getOxygenSaturationHistory)) {
            return null;
        }

        var it = SH.getOxygenSaturationHistory({
            :period => period,
            :order  => SH.ORDER_OLDEST_FIRST
        });

        var stats = computeTimeWeightedStats(it, dayStartSec, nowSec);
        if (stats == null) {
            return null;
        }

        return {
            "avgPercent" => stats.get("avg"),
            "minPercent" => stats.get("min"),
            "maxPercent" => stats.get("max"),
            "sampleCount" => stats.get("sampleCount")
        };
    }

    function collectDailyAggregateBodyBattery(dayStartSec as Lang.Number, nowSec as Lang.Number, period as Time.Duration) as Lang.Dictionary or Null {
        if (!(Toybox has :SensorHistory) || !(SH has :getBodyBatteryHistory)) {
            return null;
        }

        var iter = SH.getBodyBatteryHistory({
            :period => period,
            :order  => SH.ORDER_OLDEST_FIRST
        });

        var start = null;
        var end = null;
        var min = null;
        var max = null;
        var charged = 0;
        var drained = 0;
        var sampleCount = 0;
        var prevValue = null;

        while (true) {
            var sample = iter.next();
            if (sample == null) {
                break;
            }
            if (!(sample has :data) || sample.data == null) {
                continue;
            }
            var sampleEpoch = getSampleEpoch(sample as SH.SensorSample);
            var sampleEpochNum = sampleEpoch as Lang.Number;
            if (sampleEpochNum != null && sampleEpochNum < dayStartSec) {
                continue;
            }

            var value = getSampleValue(sample as SH.SensorSample);
            if (value == null) {
                continue;
            }
            if (start == null) {
                start = value;
            }
            end = value;

            if (min == null || value < min) {
                min = value;
            }
            if (max == null || value > max) {
                max = value;
            }

            if (prevValue != null) {
                var prevValueNum = prevValue as Lang.Number;
                if (prevValueNum != null) {
                    var delta = value - prevValueNum;
                    if (delta > 0) {
                        charged += delta;
                    } else if (delta < 0) {
                        drained += (-delta);
                    }
                }
            }

            prevValue = value;
            sampleCount += 1;
        }

        if (sampleCount == 0 || start == null || end == null) {
            return null;
        }

        return {
            "start" => start,
            "end" => end,
            "min" => min,
            "max" => max,
            "charged" => charged,
            "drained" => drained,
            "netChange" => end - start,
            "sampleCount" => sampleCount
        };
    }

    function computeTimeWeightedStats(iter as SH.SensorHistoryIterator, dayStartSec as Lang.Number, nowSec as Lang.Number) as Lang.Dictionary or Null {
        var weightedSum = 0;
        var totalTime = 0;
        var sum = 0;
        var sampleCount = 0;
        var min = null;
        var max = null;
        var prevValue = null;
        var prevTime = null;

        while (true) {
            var sample = iter.next();
            if (sample == null) {
                break;
            }
            if (!(sample has :data) || sample.data == null) {
                continue;
            }
            var sampleEpoch = getSampleEpoch(sample as SH.SensorSample);
            var sampleEpochNum = sampleEpoch as Lang.Number;
            if (sampleEpochNum != null && sampleEpochNum < dayStartSec) {
                continue;
            }

            if (prevValue != null && prevTime != null && sampleEpochNum != null) {
                var prevTimeNum = prevTime as Lang.Number;
                var prevValueNum = prevValue as Lang.Number;
                if (prevTimeNum != null && prevValueNum != null) {
                    var delta = sampleEpochNum - prevTimeNum;
                    if (delta > 0) {
                        weightedSum += prevValueNum * delta;
                        totalTime += delta;
                    }
                }
            }

            var value = getSampleValue(sample as SH.SensorSample);
            if (value == null) {
                continue;
            }
            if (min == null || value < min) {
                min = value;
            }
            if (max == null || value > max) {
                max = value;
            }
            sum += value;
            sampleCount += 1;
            prevValue = value;
            prevTime = sampleEpochNum;
        }

        if (sampleCount == 0) {
            return null;
        }

        if (prevValue != null && prevTime != null) {
            var prevTimeNum = prevTime as Lang.Number;
            var prevValueNum = prevValue as Lang.Number;
            if (prevTimeNum != null && prevValueNum != null) {
                var tail = nowSec - prevTimeNum;
                if (tail > 0) {
                    weightedSum += prevValueNum * tail;
                    totalTime += tail;
                }
            }
        }

        var avg = null;
        if (totalTime > 0 && sampleCount > 1) {
            avg = weightedSum / totalTime;
        } else {
            avg = sum / sampleCount;
        }

        return {
            "avg" => avg,
            "min" => min,
            "max" => max,
            "sampleCount" => sampleCount
        };
    }

    function getSampleEpoch(sample as SH.SensorSample or Null) as Lang.Number or Null {
        if (sample == null || sample.when == null) {
            return null;
        }
        var moment = sample.when;
        return moment.value();
    }

    function getSampleValue(sample as SH.SensorSample or Null) as Lang.Number or Null {
        if (sample == null || sample.data == null) {
            return null;
        }
        if (sample.data instanceof Lang.Number) {
            return sample.data as Lang.Number;
        }
        return null;
    }

    function getNumberFromDict(dict as Lang.Dictionary, key as Lang.String) as Lang.Number or Null {
        var value = dict.get(key);
        if (value == null || !(value instanceof Lang.Number)) {
            return null;
        }
        return value as Lang.Number;
    }

    function getNumberOrZero(value as Lang.Object or Null) as Lang.Number {
        if (value == null || !(value instanceof Lang.Number)) {
            return 0;
        }
        return value as Lang.Number;
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

    function getDistanceCm(info as AM.Info) as Lang.Number or Null {
        var distanceCm = null;
        if ((info has :distance) && info.distance != null) {
            distanceCm = info.distance;
        } else if ((info has :totalDistance) && info.totalDistance != null) {
            distanceCm = info.totalDistance;
        }
        if (distanceCm == null) {
            return null;
        }
        return distanceCm;
    }

    function getActiveCaloriesKcal(info as AM.Info) as Lang.Number or Null {
        if ((info has :activeCalories) && info.activeCalories != null) {
            return info.activeCalories;
        }
        if ((info has :calories) && info.calories != null) {
            return info.calories;
        }
        return null;
    }

    function getTotalCaloriesKcal(info as AM.Info, activeCaloriesKcal as Lang.Number or Null) as Lang.Number or Null {
        if ((info has :totalCalories) && info.totalCalories != null) {
            return info.totalCalories;
        }
        if ((info has :calories) && info.calories != null) {
            return info.calories;
        }
        if ((info has :restingCalories) && info.restingCalories != null && activeCaloriesKcal != null) {
            return info.restingCalories + activeCaloriesKcal;
        }
        return null;
    }

    function getFloorsClimbed(info as AM.Info) as Lang.Number or Null {
        if ((info has :floorsClimbed) && info.floorsClimbed != null) {
            return info.floorsClimbed;
        }
        if ((info has :floors) && info.floors != null) {
            return info.floors;
        }
        return null;
    }

    function getFloorsDescended(info as AM.Info) as Lang.Number or Null {
        if ((info has :floorsDescended) && info.floorsDescended != null) {
            return info.floorsDescended;
        }
        return null;
    }

    function getActiveMinutes(info as AM.Info) as Lang.Dictionary {
        var moderate = null;
        var vigorous = null;
        var total = null;

        var activeMinutesObj = null;
        if ((info has :activeMinutesDay) && info.activeMinutesDay != null) {
            activeMinutesObj = info.activeMinutesDay;
        } else if ((info has :activeMinutes) && info.activeMinutes != null && info.activeMinutes instanceof AM.ActiveMinutes) {
            activeMinutesObj = info.activeMinutes;
        }

        if (activeMinutesObj != null) {
            if ((activeMinutesObj has :moderate) && activeMinutesObj.moderate != null) {
                moderate = activeMinutesObj.moderate;
            }
            if ((activeMinutesObj has :vigorous) && activeMinutesObj.vigorous != null) {
                vigorous = activeMinutesObj.vigorous;
            }
            if ((activeMinutesObj has :total) && activeMinutesObj.total != null) {
                total = activeMinutesObj.total;
            }
        }

        if (moderate == null && (info has :moderateMinutes) && info.moderateMinutes != null) {
            moderate = info.moderateMinutes;
        }
        if (vigorous == null && (info has :vigorousMinutes) && info.vigorousMinutes != null) {
            vigorous = info.vigorousMinutes;
        }
        if (total == null && (info has :activeMinutes) && info.activeMinutes != null) {
            var activeMinutesValue = info.activeMinutes as Lang.Number;
            if (activeMinutesValue != null) {
                total = activeMinutesValue;
            }
        }
        if (total == null && (moderate != null || vigorous != null)) {
            total = (moderate == null ? 0 : moderate) + (vigorous == null ? 0 : vigorous);
        }

        return {
            "moderate" => (moderate == null ? 0 : moderate),
            "vigorous" => (vigorous == null ? 0 : vigorous),
            "total" => (total == null ? 0 : total)
        };
    }

}
