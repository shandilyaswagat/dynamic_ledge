import SwiftUI

// MARK: Clipboard

/// Recently copied text as a row of cards. Click one to copy it again.
struct ClipboardBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let entries = model.clipboard.history.entries
        if entries.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                VStack(spacing: 6 * s) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 20 * s, weight: .semibold))
                    Text("Text you copy shows up here")
                        .font(.system(size: 12 * s, weight: .medium))
                    Text("Passwords are skipped and nothing is saved to disk.")
                        .font(.system(size: 10 * s))
                        .foregroundStyle(NotchColor.secondaryText.opacity(0.8))
                }
                .foregroundStyle(NotchColor.secondaryText)
            }
            .padding(.bottom, 2 * s)
        } else {
            HStack(alignment: .center, spacing: 8 * s) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8 * s) {
                        ForEach(entries) { entry in
                            ClipboardCard(model: model, entry: entry)
                        }
                    }
                }
                Button {
                    model.clipboard.removeAll()
                } label: {
                    Image(systemName: "xmark.bin.fill")
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(width: 28 * s, height: 28 * s)
                        .background(Circle().fill(NotchColor.buttonFill))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Clear the history")
                .accessibilityLabel(Text("Clear the clipboard history"))
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 2 * s)
        }
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
            }
            .padding(10 * s)
            .frame(width: 150 * s)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.13 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { model.clipboard.remove(entry.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14 * s))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.35))
                }
                .buttonStyle(PressableButtonStyle())
                .offset(x: 4 * s, y: -4 * s)
                .accessibilityLabel(Text("Remove from history"))
            }
        }
        .onHover { isHovering = $0 }
        .help("Click to copy")
        .accessibilityLabel(Text("Copy \(ClipboardHistory.preview(entry.text, limit: 60))"))
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
