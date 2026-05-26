//
//  LicensesView.swift
//  EclipsePlexClient
//

import SwiftUI

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open source")
                    .font(.title2.bold())
                Text(licensesBody)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Licenses")
    }

    private var licensesBody: String {
        """
        EclipsePlex is an independent third-party client for Plex Media Server. It is not affiliated with Plex Inc.

        VLCKit (VideoLAN)
        This app uses VLCKit for media playback. VLCKit is licensed under the GNU Lesser General Public License (LGPL) v2.1 or later.
        Source: https://github.com/videolan/vlckit

        VLCUI
        Portions of the playback UI are derived from VLCUI (MIT License).
        Source: https://github.com/LePips/VLCUI

        LGPL compliance
        You may obtain Corresponding Source for the LGPL-covered libraries used in this application by contacting the developer or visiting the project repository. This offer is valid for at least three years from distribution of this app.

        MobileVLCKit (iOS / tvOS)
        Distributed via CocoaPods / vendored XCFramework per platform build instructions in the project documentation.
        """
    }
}
