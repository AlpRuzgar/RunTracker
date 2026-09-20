//
//  EditProfileView.swift
//  RunTracker
//
//  Created by Alp Rüzgar on 18.09.2026.
//

import SwiftUI
import SwiftData

/// Profil sekmesinden açılan ekran; onboarding'de girilen kullanıcı
/// bilgilerini düzenler. Değişiklikler doğrudan modele yazılır.
struct EditProfileView: View {
    @Environment(User.self) private var user

    private var isHeightValid: Bool { user.heightCM > 50 && user.heightCM <= 250 }
    private var isWeightValid: Bool { user.weightKG > 20 && user.weightKG <= 300 }

    var body: some View {
        @Bindable var user = user
        Form {
            Section("Avatar") {
                HStack {
                    Spacer()
                    ForEach(Avatar.allCases, id: \.self) { avatar in
                        Button {
                            user.avatar = avatar
                        } label: {
                            VStack {
                                Image(avatar.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(avatar == user.avatar ? Color.accentColor : Color.clear, lineWidth: 3)
                                    }
                                Text(avatar.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            Section("About You") {
                TextField("Your name", text: $user.name)
                    .textContentType(.name)
                Picker("Sex", selection: $user.sex) {
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                    Text("Other").tag(Sex.neither)
                }
                DatePicker("Date of Birth", selection: $user.bday, displayedComponents: .date)
            }

            Section("Height") {
                TextField("Height", value: $user.heightCM, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
            }

            Section("Weight") {
                TextField("Weight", value: $user.weightKG, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)

            }

            Section("Your Goal") {
                HStack {
                    Text("Target Distance")
                    Spacer()
                    TextField("5", value: $user.targetDistance, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    Text("km")
                        .foregroundStyle(.secondary)
                }
                Picker("Motivation", selection: $user.motivation) {
                    ForEach(Motivation.allCases, id: \.self) { option in
                        Text(option.title)
                    }
                }
                HStack {
                    Text("Weekly Target")
                    Spacer()
                    Text(user.weeklyTarget.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...2)))))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func validationMessage(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
    }
    .environment(
        User(
            name: "Alp",
            sex: .male,
            bday: .now,
            heightCM: 175,
            weightKG: 70,
            targetDistance: 5,
            motivation: .hobby
        )
    )
    .modelContainer(for: [User.self, RunSession.self, TraveledPath.self], inMemory: true)
}
