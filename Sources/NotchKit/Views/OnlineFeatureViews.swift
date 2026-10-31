import SwiftUI

struct WeatherPanelBody: View {
    let model: IslandModel
    @State private var city = ""
    @FocusState private var editingCity: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let service = model.online
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                TextField("City", text: $city)
                    .focused($editingCity)
                    .onSubmit { service.search(city: city) }
                Button("Search") { service.search(city: city) }
                    .disabled(city.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || service.weatherLoading)
                if let place = model.settings.weatherPlace {
                    Button("Refresh") { service.forecast(for: place) }.disabled(service.weatherLoading)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6 * s) {
                    if service.weatherLoading { ProgressView().controlSize(.small) }
                    ForEach(service.places) { place in
                        Button(place.label) { editingCity = false; service.forecast(for: place) }
                    }
                    if let weather = service.weather {
                        Text(model.settings.weatherPlace?.label ?? "").lineLimit(1)
                        Text(weather).font(.system(size: 20 * s, weight: .medium)).monospacedDigit()
                    }
                    if let message = service.weatherMessage { Text(message).foregroundStyle(NotchColor.secondaryText) }
                    Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                        .font(.system(size: 10 * s))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12 * s))
        .onChange(of: editingCity) { _, value in model.isTypingInNook = value }
        .onAppear {
            if model.settings.weatherEnabled, let place = model.settings.weatherPlace { service.forecast(for: place) }
        }
        .onDisappear { model.isTypingInNook = false; service.stopWeather() }
    }
}

struct LyricsPanelBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s
    private var trackKey: URL? { model.nowPlaying.info.flatMap(OnlineRequests.lyrics) }

    var body: some View {
        let service = model.online
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text(service.lyricsTitle ?? String(localized: "Lyrics")).lineLimit(1)
                Spacer()
                Button("Retry") { service.loadLyrics(for: model.nowPlaying.info) }.disabled(service.lyricsLoading)
                Link("LRCLIB", destination: URL(string: "https://lrclib.net/")!)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8 * s) {
                        if service.lyricsLoading { ProgressView().controlSize(.small) }
                        if let parsed = service.parsedLyrics, parsed.isSynced {
                            let elapsed = model.nowPlaying.info?.elapsed(at: Date()) ?? 0
                            let activeIdx = parsed.activeIndex(at: elapsed)
                            ForEach(parsed.lines) { line in
                                let isActive = line.id == activeIdx
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .id(line.id)
                                    .font(.system(size: (isActive ? 14 : 12) * s, weight: isActive ? .semibold : .regular))
                                    .foregroundStyle(isActive ? NotchColor.accent(model.nowPlaying.accent) : (line.time <= elapsed ? .white : NotchColor.secondaryText))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onChange(of: activeIdx) { _, newIdx in
                                if let newIdx { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(newIdx, anchor: .center) } }
                            }
                        } else if let lyrics = service.lyrics {
                            Text(lyrics).textSelection(.enabled)
                        }
                        if let message = service.lyricsMessage { Text(message).foregroundStyle(NotchColor.secondaryText) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 13 * s))
        .onChange(of: trackKey, initial: true) { _, _ in service.loadLyrics(for: model.nowPlaying.info) }
        .onDisappear { service.stopLyrics() }
    }
}
