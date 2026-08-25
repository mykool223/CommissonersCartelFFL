import SafariServices
import SwiftUI

/// Reads an article inside the app.
///
/// `SFSafariViewController` rather than a bare web view: it keeps the reader
/// in the app, but loads the publisher's own page — their layout, their
/// advertising, their byline. Extracting the text and re-rendering it here
/// would read better and would be republishing somebody else's work, which is
/// neither ours to do nor what our licence covers.
///
/// It also brings Reader mode, which is the closest thing to "just the
/// article" that is honestly available to us.
struct ArticleReader: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        // Offer Reader where the page supports it; most articles do.
        configuration.entersReaderIfAvailable = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(Color.brand)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
