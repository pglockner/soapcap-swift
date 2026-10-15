import SwiftUI

// The beta notice, the Help window and Report a Problem.

#Preview("Beta notice") { BetaNoticeView(version: "0.11.0") {} }

#Preview("Help") { HelpView(isBeta: true).frame(width: 620, height: 680) }

#Preview("Help, the end") { HelpView(isBeta: true).defaultScrollAnchor(.bottom).frame(width: 620, height: 680) }

#Preview("Report a Problem") {
    ProblemReportView(report: ProblemReport(version: AppVersion(marketing: "0.12.1", build: "161"),
                                            macOS: "Version 27.0.1 (Build 27A5301)", memoryGB: 16, noteModel: "llama3.1:8b"))
}
