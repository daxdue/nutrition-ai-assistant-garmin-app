using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;
import Toybox.Application;

class NutritionAiAssistantApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Lang.Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Lang.Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() {
        var view = new MainView();
        return [ view, new MainDelegate(view) ];
    }

}

function getApp() as NutritionAiAssistantApp {
    return Application.getApp() as NutritionAiAssistantApp;
}

