using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;

class MainMenuDelegate extends Ui.MenuInputDelegate {
    var mView as MainView;

    function initialize(view as MainView) {
        MenuInputDelegate.initialize();
        mView = view;
    }

    function onMenuItem(item as Lang.Symbol) as Void {
        if (item == :open_widget) {
            mView.openWidget();
        }
    }

}
