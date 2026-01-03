using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.SensorHistory as SH;
using Toybox.ActivityMonitor as AM;
using Toybox.Time as Time;
using Toybox.Lang as Lang;

class MainDelegate extends Ui.InputDelegate {

    const INTEGRATION_KEY = "";
    var mView as MainView;

    function initialize(view as MainView) {
        InputDelegate.initialize();
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
        if (info == null) {
            return null;
        }

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

        var it = SH.getBodyBatteryHistory({
            :period => period,
            :order  => SH.ORDER_OLDEST_FIRST
        });

        if (it == null) {
            return null;
        }

        var start = null;
        var end = null;
        var min = null;
        var max = null;
        var charged = 0;
        var drained = 0;
        var sampleCount = 0;
        var prevValue = null;

        var iter = it as SH.SensorHistoryIterator;
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
                if (prevValueNum == null) {
                    prevValueNum = prevValue as Lang.Float;
                }
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

    function computeTimeWeightedStats(it as SH.SensorHistoryIterator or Null, dayStartSec as Lang.Number, nowSec as Lang.Number) as Lang.Dictionary or Null {
        var iter = it as SH.SensorHistoryIterator;
        if (iter == null) {
            return null;
        }

        var weightedSum = 0;
        var totalTime = 0;
        var sum = 0;
        var sampleCount = 0;
        var min = null;
        var max = null;
        var prevValue = null;
        var prevTime = null;
        var missingTime = false;

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
                if (prevValueNum == null) {
                    prevValueNum = prevValue as Lang.Float;
                }
                if (prevTimeNum != null && prevValueNum != null) {
                    var delta = sampleEpochNum - prevTimeNum;
                    if (delta > 0) {
                        weightedSum += prevValueNum * delta;
                        totalTime += delta;
                    }
                }
            } else if (sampleEpochNum == null) {
                missingTime = true;
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

        if (prevValue != null && prevTime != null && !missingTime) {
            var prevTimeNum = prevTime as Lang.Number;
            var prevValueNum = prevValue as Lang.Number;
            if (prevValueNum == null) {
                prevValueNum = prevValue as Lang.Float;
            }
            if (prevTimeNum != null && prevValueNum != null) {
                var tail = nowSec - prevTimeNum;
                if (tail > 0) {
                    weightedSum += prevValueNum * tail;
                    totalTime += tail;
                }
            }
        }

        var avg = null;
        if (!missingTime && totalTime > 0 && sampleCount > 1) {
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

    function getSampleValue(sample as SH.SensorSample or Null) as Lang.Number or Lang.Float or Null {
        if (sample == null || sample.data == null) {
            return null;
        }
        var valueNum = sample.data as Lang.Number;
        if (valueNum != null) {
            return valueNum;
        }
        var valueFloat = sample.data as Lang.Float;
        if (valueFloat != null) {
            return valueFloat;
        }
        return null;
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
        var distanceMeters = null;
        if ((info has :distance) && info.distance != null) {
            distanceMeters = info.distance;
        } else if ((info has :totalDistance) && info.totalDistance != null) {
            distanceMeters = info.totalDistance;
        }
        if (distanceMeters == null) {
            return null;
        }
        return distanceMeters * 100;
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

        if ((info has :moderateMinutes) && info.moderateMinutes != null) {
            moderate = info.moderateMinutes;
        }
        if ((info has :vigorousMinutes) && info.vigorousMinutes != null) {
            vigorous = info.vigorousMinutes;
        }
        if ((info has :activeMinutes) && info.activeMinutes != null) {
            total = info.activeMinutes;
        } else if (moderate != null || vigorous != null) {
            total = (moderate == null ? 0 : moderate) + (vigorous == null ? 0 : vigorous);
        }

        return {
            "moderate" => (moderate == null ? 0 : moderate),
            "vigorous" => (vigorous == null ? 0 : vigorous),
            "total" => (total == null ? 0 : total)
        };
    }

}
