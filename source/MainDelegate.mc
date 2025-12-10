using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;

class MainDelegate extends Ui.InputDelegate {

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

}

