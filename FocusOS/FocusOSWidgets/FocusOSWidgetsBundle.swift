import WidgetKit
import SwiftUI

@main
struct FocusOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusStatusWidget()
        FocusLiveActivity()
    }
}
