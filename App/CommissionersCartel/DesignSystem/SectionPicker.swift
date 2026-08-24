import SwiftUI

/// A tab section that can be chosen from the navigation bar.
protocol TabSection: Hashable, CaseIterable, Identifiable where AllCases: RandomAccessCollection {
    var title: String { get }
    var systemImage: String { get }
}

extension TabSection {
    /// SF Symbol by default. A section with a drawn icon overrides this —
    /// no symbol set has a cap and shades.
    var icon: Image { Image(systemName: systemImage) }
}

extension TabSection {
    var id: Self { self }
}

extension TabSection where Self: RawRepresentable, RawValue == String {
    /// Which section to open on launch.
    ///
    /// Debug builds honour `-initialSection recap`, matching `-initialTab`, so
    /// screenshots and UI tests can land on a specific screen without
    /// simulating taps through a menu. Release builds always use `fallback`.
    static func initial(default fallback: Self) -> Self {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-initialSection"),
           arguments.index(after: index) < arguments.endIndex,
           let section = Self(rawValue: arguments[arguments.index(after: index)]) {
            return section
        }
        #endif
        return fallback
    }
}

/// Turns the navigation title into a dropdown.
///
/// The tab bar only comfortably holds five destinations, and the app has more
/// than five things to show. Rather than a sixth tab or a cramped segmented
/// control, each tab keeps one job and its sections hang off the title — which
/// also leaves room to add sections later without touching the tab bar.
struct SectionPicker<Section: TabSection>: View {
    @Binding var selection: Section

    var body: some View {
        Menu {
            // An inline picker shows a checkmark against the current section,
            // which a plain list of buttons would not.
            Picker("Section", selection: $selection) {
                ForEach(Section.allCases) { section in
                    Label { Text(section.title) } icon: { section.icon }
                        .tag(section)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Text(selection.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brand)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("\(selection.title), change section")
    }
}

extension View {
    /// Places a `SectionPicker` where the navigation title would be.
    func sectionPicker<Section: TabSection>(_ selection: Binding<Section>) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SectionPicker(selection: selection)
                }
            }
    }
}
