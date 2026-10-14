import SwiftUI

// The beta notice and the Help window.

#Preview("Beta notice") { BetaNoticeView(version: "0.11.0") {} }

#Preview("Help") { HelpView(isBeta: true).frame(width: 620, height: 680) }

#Preview("Help, the end") { HelpView(isBeta: true).defaultScrollAnchor(.bottom).frame(width: 620, height: 680) }
