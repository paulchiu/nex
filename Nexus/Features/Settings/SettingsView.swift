import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            Section("Appearance") {
                HStack {
                    Text("Background Opacity")
                    Slider(
                        value: $store.backgroundOpacity.sending(\.setBackgroundOpacity),
                        in: 0.1...1.0,
                        step: 0.05
                    )
                    Text("\(Int(store.backgroundOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                ColorPicker(
                    "Background Color",
                    selection: backgroundColorBinding,
                    supportsOpacity: false
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear {
            store.send(.loadSettings)
        }
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: store.backgroundColorR,
                    green: store.backgroundColorG,
                    blue: store.backgroundColorB
                )
            },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    store.send(.setBackgroundColor(
                        r: Double(components.redComponent),
                        g: Double(components.greenComponent),
                        b: Double(components.blueComponent)
                    ))
                }
            }
        )
    }
}
