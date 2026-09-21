//
//  UserQAView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 16.09.2026.
//

import SwiftUI
import SwiftData

/// İlk açılışta gösterilen onboarding anketi. Karşılama sayfasından sonra
/// üç adımda kullanıcı bilgilerini toplar ve sonunda bir `User` oluşturur.
struct UserQAView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var questionIndex: Int = 0
    @State private var name: String = ""
    @State private var sex: Sex = .male
    @State private var bday: Date = .now
    @State private var heightCM: Double = 0.0
    @State private var weightKG: Double = 0.0
    @State private var targetDistance: Double = 0.0
    @State private var motivation: Motivation = .hobby

    var isBdayValid: Bool { bday <= .now }
    var isHeightValid: Bool { heightCM > 50 && heightCM <= 250 }
    var isWeightValid: Bool { weightKG > 20 && weightKG <= 300 }
    var isTargetDistanceValid: Bool { targetDistance > 0 }

    private let lastStep = 3

    /// Bulunulan adımın cevapları geçerli olmadan ilerlenemez.
    private var canAdvance: Bool {
        switch questionIndex {
        case 1: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: return isBdayValid && isHeightValid && isWeightValid
        case 3: return isTargetDistanceValid
        default: return true
        }
    }

    private var primaryButtonTitle: String {
        switch questionIndex {
        case 0: return "Get Started"
        case lastStep: return "Start Running"
        default: return "Continue"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if questionIndex > 0 {
                stepHeader
            }

            ScrollView {
                Group {
                    switch questionIndex {
                    case 0: welcomeStep
                    case 1: aboutYouStep
                    case 2: bodyStep
                    case 3: goalStep
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, questionIndex == 0 ? 48 : 12)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(Color(.systemGroupedBackground))
        .animation(.snappy, value: questionIndex)
    }

    // MARK: - Adımlar

    private var welcomeStep: some View {
        VStack(spacing: 36) {
            VStack(spacing: 16) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(.tint)

                Text("Welcome to RunTracker")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Answer a few quick questions so we can tailor routes and goals to you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 24) {
                featureRow(
                    icon: "map.fill",
                    title: "Smart Routes",
                    subtitle: "Generate running loops that match your target distance."
                )
                featureRow(
                    icon: "cloud.sun.fill",
                    title: "Run-Ready Forecasts",
                    subtitle: "See when the weather is right for your next run."
                )
                featureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track Your Progress",
                    subtitle: "Every session is saved to your profile automatically."
                )
            }
            .padding(.horizontal, 8)
        }
    }

    private var aboutYouStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepTitle("About You", subtitle: "Tell us who's lacing up.")

            card {
                fieldLabel("Name")
                TextField("Your name", text: $name)
                    .font(.title3)
                    .textContentType(.name)
            }

            card {
                fieldLabel("Sex")
                Picker("Sex", selection: $sex) {
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                    Text("Other").tag(Sex.neither)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepTitle("Your Body", subtitle: "Used to estimate pace and effort.")

            card {
                fieldLabel("Date of Birth")
                DatePicker("Date of Birth", selection: $bday, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                if !isBdayValid {
                    validationMessage("Date of birth can't be in the future.")
                }
            }

            card {
                fieldLabel("Height")
                measurementField(value: $heightCM, placeholder: "175", unit: "cm")
                if !isHeightValid {
                    validationMessage("Enter a height between 50 and 250 centimeters.")
                }
            }

            card {
                fieldLabel("Weight")
                measurementField(value: $weightKG, placeholder: "70", unit: "kg")
                if !isWeightValid {
                    validationMessage("Enter a weight between 20 and 300 kilograms.")
                }
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepTitle("Your Goal", subtitle: "We'll suggest routes that match it.")

            card {
                fieldLabel("Target Distance")
                measurementField(value: $targetDistance, placeholder: "5", unit: "km")
                if !isTargetDistanceValid {
                    validationMessage("Enter a target distance greater than 0.")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("What drives you?")
                ForEach(Motivation.allCases, id: \.self) { option in
                    motivationRow(option)
                }
            }
        }
    }

    // MARK: - Parçalar

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    questionIndex -= 1
                } label: {
                    Image(systemName: "chevron.backward")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Back")

                Spacer()

                Text("Step \(questionIndex) of \(lastStep)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(questionIndex), total: Double(lastStep))
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var footer: some View {
        Button {
            if questionIndex == lastStep {
                finish()
            } else {
                questionIndex += 1
            }
        } label: {
            Text(primaryButtonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canAdvance)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private func measurementField(value: Binding<Double>, placeholder: String, unit: String) -> some View {
        HStack {
            TextField(placeholder, value: value, format: .number.precision(.fractionLength(0...2)))
                .font(.title3)
                .keyboardType(.decimalPad)
            Text(unit)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func validationMessage(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func motivationRow(_ option: Motivation) -> some View {
        Button {
            motivation = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32)

                Text(option.title)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: motivation == option ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(motivation == option ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(motivation == option ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tamamlama

    /// Anket bitince kullanıcıyı oluşturur; onboarding'den önce kaydedilmiş
    /// koşular varsa onları da bu kullanıcıya bağlar.
    private func finish() {
        let user = User(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sex: sex,
            bday: bday,
            heightCM: heightCM,
            weightKG: weightKG,
            targetDistance: targetDistance,
            motivation: motivation
        )
        if let existing = try? modelContext.fetch(FetchDescriptor<RunSession>()) {
            user.sessions = existing
        }
        modelContext.insert(user)
        print("Finished: \(user)")
    }
}

extension Motivation {
    var title: String {
        switch self {
        case .fatLoss: return "Lose Weight"
        case .condition: return "Stay in Shape"
        case .racePrep: return "Train for a Race"
        case .hobby: return "Run for Fun"
        }
    }

    var icon: String {
        switch self {
        case .fatLoss: return "flame.fill"
        case .condition: return "heart.fill"
        case .racePrep: return "flag.checkered"
        case .hobby: return "face.smiling"
        }
    }
}

#Preview {
    UserQAView()
        .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
