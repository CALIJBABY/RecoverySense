import SwiftUI

struct WatchEMAView: View {
  @EnvironmentObject private var model: RecoverySenseWatchModel

  private let background = Color(red: 248 / 255, green: 251 / 255, blue: 244 / 255)
  private let primaryGreen = Color(red: 79 / 255, green: 155 / 255, blue: 23 / 255)
  private let softGreen = Color(red: 231 / 255, green: 244 / 255, blue: 218 / 255)
  private let darkGreen = Color(red: 53 / 255, green: 110 / 255, blue: 12 / 255)

  var body: some View {
    ZStack {
      background.ignoresSafeArea()

      ScrollView {
        VStack(spacing: 9) {
          Text("Craving right now?")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)

          Text(model.emaSelectionMade ? "\(model.emaScore) / 10" : "Choose 0-10")
            .font(.title3)
            .fontWeight(.bold)
            .foregroundStyle(darkGreen)

          Slider(
            value: Binding(
              get: { Double(model.emaScore) },
              set: { model.updateEMAScore(Int($0.rounded())) }
            ),
            in: 0...10,
            step: 1
          )
          .tint(primaryGreen)
          .accessibilityLabel("Craving score")
          .accessibilityValue(
            model.emaSelectionMade
              ? "\(model.emaScore) out of 10"
              : "No score selected"
          )

          HStack {
            Text("0 none")
            Spacer()
            Text("10 extreme")
          }
          .font(.caption2)
          .foregroundStyle(darkGreen)

          Button(action: model.submitEMA) {
            Text("Save rating")
              .font(.caption)
              .fontWeight(.bold)
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity, minHeight: 40)
              .background(
                model.emaSelectionMade ? primaryGreen : Color.gray,
                in: RoundedRectangle(cornerRadius: 14)
              )
          }
          .buttonStyle(.plain)
          .disabled(!model.emaSelectionMade)

          Text(model.emaStatusText)
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(darkGreen)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(softGreen.opacity(0.22))
      }
    }
    .navigationTitle("Check-in")
  }
}
