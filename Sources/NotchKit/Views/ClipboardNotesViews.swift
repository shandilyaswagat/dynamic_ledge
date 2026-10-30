import SwiftUI

// MARK: Clipboard

/// Recently copied text as a row of cards, pinned clips first. Click one to copy it again.
/// Search opens a bar below the clips (the notch grows to fit it) and filters as you type.
struct ClipboardBody: View {
    let model: IslandModel
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let history = model.clipboard.history
        if history.entries.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                VStack(spacing: 6 * s) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 20 * s, weight: .semibold))
                    Text("Text you copy shows up here")
                        .font(.system(size: 12 * s, weight: .medium))
                    Text("Passwords are skipped. Pin a clip to keep it after you quit.")
                        .font(.system(size: 10 * s))
                        .foregroundStyle(NotchColor.secondaryText.opacity(0.8))
                }
                .foregroundStyle(NotchColor.secondaryText)
            }
            .frame(height: (IslandMetrics.Nook.body - 2) * s)
        } else {
            let isSearching = model.isSearchingClipboard
            let entries = history.matching(isSearching ? query : "")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8 * s) {
                    ZStack {
                        if entries.isEmpty {
                            VStack(spacing: 4 * s) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16 * s, weight: .semibold))
                                Text("No clips match “\(query)”")
                                    .font(.system(size: 12 * s, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(NotchColor.secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8 * s) {
                                    ForEach(entries) { entry in
                                        ClipboardCard(model: model, entry: entry)
                                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    VStack(spacing: 6 * s) {
                        SideButton(
                            symbol: "magnifyingglass",
                            label: isSearching ? "Close search" : "Search clips",
                            isOn: isSearching
                        ) {
                            if isSearching { closeSearch() } else { openSearch() }
                        }
                        SideButton(symbol: "xmark.bin.fill", label: history.pinnedCount > 0 ? "Clear the history (pinned clips stay)" : "Clear the history") {
                            withAnimation(.snappy(duration: 0.25)) { model.clipboard.removeAll() }
                        }
                        .disabled(history.pinnedCount == history.entries.count)
                        .opacity(history.pinnedCount == history.entries.count ? 0.4 : 1)
                    }
                }
                // The clips keep their size; the notch grows below them for the search bar.
                .frame(height: (IslandMetrics.Nook.body - 2) * s)
                if isSearching {
                    searchField
                        .padding(.top, 10 * s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: entries.map(\.id))
        }
    }

    private var searchField: some View {
        HStack(spacing: 7 * s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(searchFocused ? .white : NotchColor.secondaryText)
            TextField("Search clips", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5 * s, weight: .medium))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit {
                    // Return copies the first match, like a launcher.
                    if let first = model.clipboard.history.matching(query).first {
                        model.clipboard.copy(first)
                    }
                }
                .onKeyPress(.escape) {
                    closeSearch()
                    return .handled
                }
            if !query.isEmpty {
                Text("\(model.clipboard.history.matching(query).count)")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NotchColor.secondaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("\(model.clipboard.history.matching(query).count) matches"))
            }
            Button { closeSearch() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13 * s))
                    .foregroundStyle(NotchColor.secondaryText)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Close search")
            .accessibilityLabel(Text("Close search"))
        }
        .padding(.horizontal, 12 * s)
        .frame(height: 28 * s)
        .background(Capsule().fill(Color.white.opacity(searchFocused ? 0.12 : 0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(searchFocused ? 0.16 : 0), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .task {
            // The notch takes the keyboard as search opens; focus the field once it has.
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
        }
        .onChange(of: searchFocused) { _, focused in model.isTypingInNook = focused }
        .onDisappear {
            model.isSearchingClipboard = false
            model.isTypingInNook = false
        }
    }

    private func openSearch() {
        withAnimation(Motion.resize) { model.isSearchingClipboard = true }
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(Motion.resize) {
            query = ""
            model.isSearchingClipboard = false
        }
    }
}

/// A round grey button beside the cards; filled white while its mode is on.
private struct SideButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var isOn = false
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(isOn ? .black : (isHovering ? .white : NotchColor.secondaryText))
                .frame(width: 28 * s, height: 28 * s)
                .background(Circle().fill(isOn ? Color.white : (isHovering ? Color.white.opacity(0.18) : NotchColor.buttonFill)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(label)
        .accessibilityLabel(Text(label))
    }
}

private struct ClipboardCard: View {
    let model: IslandModel
    let entry: ClipboardHistory.Entry
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let copied = model.clipboard.justCopied == entry.id
        Button {
            model.clipboard.copy(entry)
        } label: {
            VStack(alignment: .leading, spacing: 6 * s) {
                Text(ClipboardHistory.preview(entry.text))
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 4 * s) {
                    if copied {
                        Image(systemName: "checkmark")
                        Text("Copied")
                    } else {
                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(NotchColor.orange)
                                .accessibilityLabel(Text("Pinned"))
                        }
                        if let app = entry.appName {
                            Text(app).lineLimit(1)
                            Text("·")
                        }
                        Text(entry.copiedAt, style: .relative)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundStyle(copied ? NotchColor.green : NotchColor.secondaryText)
                // Room for the pin and remove buttons, which sit at the end of this line.
                .padding(.trailing, (isHovering ? 42 : 0) * s)
            }
            .padding(10 * s)
            .frame(width: 150 * s)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.13 : 0.07))
            )
            .overlay {
                if entry.isPinned {
                    RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                        .strokeBorder(NotchColor.orange.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .overlay(alignment: .bottomTrailing) {
            // Inside the card, level with the app and time, so they never cover the text or
            // hang off the corner.
            if isHovering {
                HStack(spacing: 4 * s) {
                    CardButton(
                        symbol: entry.isPinned ? "pin.slash" : "pin",
                        label: entry.isPinned ? "Unpin" : "Pin, so it stays after you quit",
                        isEnabled: entry.isPinned || model.clipboard.history.canPin
                    ) {
                        withAnimation(.snappy(duration: 0.25)) { _ = model.clipboard.togglePin(entry.id) }
                    }
                    CardButton(symbol: "trash", label: "Remove from history") {
                        withAnimation(.snappy(duration: 0.25)) { model.clipboard.remove(entry.id) }
                    }
                }
                .padding(.trailing, 7 * s)
                .padding(.bottom, 7 * s)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") { model.clipboard.copy(entry) }
            Button(entry.isPinned ? "Unpin" : "Pin") { _ = model.clipboard.togglePin(entry.id) }
                .disabled(!entry.isPinned && !model.clipboard.history.canPin)
            Divider()
            Button("Remove from History") { model.clipboard.remove(entry.id) }
        }
        .help("Click to copy")
        .accessibilityLabel(Text("Copy \(ClipboardHistory.preview(entry.text, limit: 60))"))
    }
}

/// A small round button in a clipboard card's footer.
private struct CardButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
                .frame(width: 18 * s, height: 18 * s)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(isEnabled ? label : "All 20 pins are in use")
        .accessibilityLabel(Text(label))
    }
}

// MARK: Notes

/// A quick scratchpad. Saved as you type, with formatting; Escape or a click outside closes it.
struct NotesBody: View {
    let model: IslandModel
    @State private var controller = RichTextController()
    @Environment(\.notchScale) private var s

    var body: some View {
        NoteCard(model: model, controller: controller, fontSize: 13 * s, focusOnAppear: true)
            .padding(.bottom, 2 * s)
    }
}

/// The note in a soft grey card, with a colour dot and A, B, I and U along the bottom.
struct NoteCard: View {
    let model: IslandModel
    let controller: RichTextController
    let fontSize: CGFloat
    var focusOnAppear = false
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if model.notes.text.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: fontSize))
                        .foregroundStyle(NotchColor.secondaryText)
                        .padding(.horizontal, 7 * s)
                        .padding(.vertical, 4 * s)
                        .allowsHitTesting(false)
                }
                RichTextEditor(
                    notes: model.notes,
                    controller: controller,
                    fontSize: fontSize,
                    focusOnAppear: focusOnAppear,
                    onFocus: { model.isTypingInNook = $0 },
                    onEscape: { model.collapse() }
                )
                .accessibilityLabel(Text("Notes"))
            }
            HStack(spacing: 2 * s) {
                Button { controller.nextColor() } label: {
                    Circle()
                        .fill(controller.colorIndex == 0 ? NotchColor.blue : controller.currentColor)
                        .frame(width: 11 * s, height: 11 * s)
                        .frame(width: 22 * s, height: 22 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Text colour")
                Spacer(minLength: 0)
                FormatButton(label: "A", help: "Bigger text") { controller.toggleSize() }
                FormatButton(label: "B", weight: .heavy, help: "Bold") { controller.toggleBold() }
                FormatButton(label: "I", italic: true, help: "Italic") { controller.toggleItalic() }
                FormatButton(label: "U", underline: true, help: "Underline") { controller.toggleUnderline() }
            }
            .padding(.horizontal, 4 * s)
            .padding(.bottom, 3 * s)
        }
        .padding(.top, 6 * s)
        .padding(.horizontal, 4 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

private struct FormatButton: View {
    let label: String
    var weight: Font.Weight = .semibold
    var italic = false
    var underline = false
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11 * s, weight: weight))
                .italic(italic)
                .underline(underline)
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22 * s, height: 22 * s)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .help(help)
    }
}
